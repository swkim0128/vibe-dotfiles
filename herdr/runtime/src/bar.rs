//! Manual, bounded layout repair. Never replaces a terminal or closes a pane.
use super::{rpc_timeout, scope_path, string, subagent_scope, view_options, Result};
use fs2::FileExt;
use serde_json::{json, Value};
use std::env;
use std::fs::OpenOptions;
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::time::Duration;

fn call(method: &str, params: Value) -> Result<Value> {
    rpc_timeout(method, params, Duration::from_secs(5))
}

fn without(node: &Value, bar: &str) -> Option<Value> {
    if node["type"] == "pane" {
        return (node["pane_id"] != bar).then(|| node.clone());
    }
    if node["type"] != "split" {
        return None;
    }
    match (without(&node["first"], bar), without(&node["second"], bar)) {
        (Some(first), Some(second)) => Some(json!({"type":"split","direction":node["direction"],
            "ratio":node["ratio"],"first":first,"second":second})),
        (first, second) => first.or(second),
    }
}

fn same_shape(a: &Value, b: &Value) -> bool {
    if a["type"] == "pane" {
        return b["type"] == "pane" && a["pane_id"] == b["pane_id"];
    }
    b["type"] == "split"
        && a["direction"] == b["direction"]
        && (a["ratio"].as_f64().unwrap_or(-1.0) - b["ratio"].as_f64().unwrap_or(-2.0)).abs()
            < 0.00001
        && same_shape(&a["first"], &b["first"])
        && same_shape(&a["second"], &b["second"])
}

fn process(pane: &Value) -> Result<(bool, Value)> {
    let info =
        call("pane.process_info", json!({"pane_id":pane["pane_id"]}))?["process_info"].clone();
    let processes = info["foreground_processes"]
        .as_array()
        .ok_or("전경 프로세스를 확인할 수 없습니다")?;
    if processes.is_empty() || info["shell_pid"].as_u64().is_none() {
        return Err("전경 프로세스가 준비되지 않았습니다. 잠시 후 다시 실행하세요".into());
    }
    let executable = env::current_exe()?.canonicalize()?;
    let mut is_bar = false;
    let mut cli_pids = Vec::new();
    for process in processes {
        if matches!(process["name"].as_str(), Some("codex" | "claude")) {
            cli_pids.push(process["pid"].clone());
        }
        let argv = process["argv"].as_array();
        let first = argv
            .and_then(|v| v.first())
            .and_then(Value::as_str)
            .unwrap_or("");
        let path = if Path::new(first).is_absolute() {
            PathBuf::from(first)
        } else {
            PathBuf::from(string(process, "cwd")).join(first)
        };
        let same_binary = path.canonicalize().is_ok_and(|path| path == executable);
        if same_binary && argv.is_some_and(|v| {
            if v.get(1).and_then(Value::as_str) != Some("view") { return false; }
            let options = v.iter().skip(2).map(Value::as_str).collect::<Option<Vec<_>>>();
            options.is_some_and(|values| view_options(&values.into_iter().map(str::to_owned).collect::<Vec<_>>()).is_ok())
        }) {
            is_bar = true;
        }
        if !same_binary && process["name"] == "vibe-herdr" {
            return Err("상태 실행기의 실제 경로를 확인할 수 없습니다".into());
        }
    }
    Ok((
        is_bar,
        json!({"terminal_id":pane["terminal_id"],"shell_pid":info["shell_pid"],"cli_pids":cli_pids}),
    ))
}

fn export(tab: &str) -> Result<Value> {
    Ok(call("layout.export", json!({"tab_id":tab}))?["layout"].clone())
}

fn required_work_rows(node: &Value, minimum: u64) -> Result<u64> {
    match node["type"].as_str() {
        Some("pane") => Ok(minimum),
        Some("split") => {
            let first = required_work_rows(&node["first"], minimum)?;
            let second = required_work_rows(&node["second"], minimum)?;
            if node["direction"] != "down" { return Ok(first.max(second)); }
            let ratio = node["ratio"].as_f64().filter(|v| v.is_finite() && *v > 0.0 && *v < 1.0)
                .ok_or("작업 분할 비율을 확인할 수 없습니다")?;
            Ok((first as f64 / ratio).max(second as f64 / (1.0 - ratio)).ceil() as u64)
        },
        _ => Err("작업 분할의 최소 높이를 확인할 수 없습니다".into()),
    }
}

fn desired_size(pane: &str, tree: &Value, config: &Value) -> Result<(f64, u64)> {
    let layout = call("pane.layout", json!({"pane_id":pane}))?["layout"].clone();
    let height = layout["area"]["height"].as_u64().ok_or("탭 높이를 확인할 수 없습니다")?;
    let rows = config["target_content_rows"].as_u64().ok_or("목표 내용 높이가 없습니다")?
        + config["pane_border_rows"].as_u64().ok_or("테두리 높이가 없습니다")?;
    let work_rows = required_work_rows(tree, config["minimum_work_rows"].as_u64().ok_or("작업 최소 높이가 없습니다")?)?;
    if rows == 0 || height < rows + work_rows {
        return Err("화면이 작아 상태 3행과 기존 작업 pane의 최소 높이를 함께 보존할 수 없습니다. 기존 배치를 유지합니다".into());
    }
    let ratio = (height - rows) as f64 / height as f64;
    let minimum = config["ratio_limits"]["min"].as_f64().ok_or("최소 비율이 없습니다")?;
    let maximum = config["ratio_limits"]["max"].as_f64().ok_or("최대 비율이 없습니다")?;
    if ratio < minimum || ratio > maximum {
        return Err("목표 높이가 정의된 비율 범위를 벗어납니다. 기존 배치를 유지합니다".into());
    }
    Ok((ratio, rows))
}

fn measured_height(pane: &str, expected: u64) -> Result<u64> {
    let layout = call("pane.layout", json!({"pane_id":pane}))?["layout"].clone();
    let rect = layout["panes"].as_array().and_then(|panes|
        panes.iter().find(|item| item["pane_id"] == pane)).ok_or("상태 pane 크기를 확인할 수 없습니다")?["rect"].clone();
    let height = rect["height"].as_u64().ok_or("상태 pane 높이가 없습니다")?;
    if height != expected || rect["width"] != layout["area"]["width"] {
        return Err(format!("목표 외곽 {expected}행·전체 폭이 적용되지 않았습니다(실측 {height}행). Herdr의 세밀한 분할 비율 지원을 확인하세요. 요청 접수를 높이 축소 성공으로 처리하지 않습니다").into());
    }
    Ok(height)
}

fn park(pane: &str, workspace: &str, config: &Value) -> Result<()> {
    let result = call(
        "pane.move",
        json!({"pane_id":pane,"destination":{"type":"new_tab",
        "workspace_id":workspace,"label":config["temporary_tab_label"]},"focus":false}),
    )?;
    if result["move_result"]["changed"] != true {
        return Err(format!("pane 이동이 적용되지 않았습니다: {result}").into());
    }
    Ok(())
}

fn move_back(pane: &str, tab: &str, target: &str, direction: &str, ratio: f64) -> Result<()> {
    let result = call(
        "pane.move",
        json!({"pane_id":pane,"destination":{"type":"tab","tab_id":tab,
        "target_pane_id":target,"split":direction,"ratio":ratio},"focus":false}),
    )?;
    if result["move_result"]["changed"] != true {
        return Err(format!("pane 복귀가 적용되지 않았습니다: {result}").into());
    }
    Ok(())
}

fn relaunch(tab: &str, old: &str, work: &[(Value, Value)], tree: &Value,
    config: &Value, scope: &(String, String), ratio: f64, rows: u64) -> Result<Value> {
    let old_pane = call("pane.get", json!({"pane_id":old}))?["pane"].clone();
    let (is_bar, old_identity) = process(&old_pane)?;
    if !is_bar { return Err("교체 대상이 상태 TUI가 아닙니다".into()); }
    call("layout.set_split_ratio", json!({"tab_id":tab,"path":[],"ratio":ratio}))?;
    measured_height(old, rows)?;
    let opened = call("plugin.pane.open", json!({"plugin_id":config["plugin_id"],
        "entrypoint":config["entrypoint"],"placement":config["placement"],
        "target_pane_id":old,"direction":config["direction"],"focus":false}))?;
    let new = string(&opened["plugin_pane"]["pane"], "pane_id");
    if new.is_empty() { return Err("새 상태 pane을 식별하지 못했습니다. 기존 TUI는 유지합니다".into()); }
    let mut new_identity = None;
    let mut old_closed = false;
    let outcome = (|| -> Result<Value> {
        let pane = call("pane.get", json!({"pane_id":new}))?["pane"].clone();
        let (is_bar, identity) = process(&pane)?;
        if !is_bar || pane["tab_id"] != tab || pane["workspace_id"] != old_pane["workspace_id"] {
            return Err("새 상태 TUI의 실행·위치를 확인하지 못했습니다. 기존 TUI는 유지합니다".into());
        }
        new_identity = Some(identity);
        let binding = subagent_scope(&scope.0, &new, &scope.1)?;
        let mut file = OpenOptions::new().write(true).create_new(true).mode(0o600).open(scope_path(&new)?)?;
        write!(file, "{binding}")?;
        let nested = export(tab)?;
        if !same_shape(&nested["root"]["first"], tree)
            || nested["root"]["second"]["direction"] != config["direction"]
            || nested["root"]["second"]["first"]["pane_id"] != old
            || nested["root"]["second"]["second"]["pane_id"] != new {
            return Err("기존 작업 분할 보존을 확인하지 못했습니다. 기존 TUI는 유지합니다".into());
        }
        for (pane, identity) in work {
            let live = call("pane.get", json!({"pane_id":pane["pane_id"]}))?["pane"].clone();
            if process(&live)?.1 != *identity { return Err("작업 프로세스 또는 terminal ID가 변경되었습니다".into()); }
        }
        let live_old = call("pane.get", json!({"pane_id":old}))?["pane"].clone();
        if process(&live_old)? != (true, old_identity.clone()) {
            return Err("기존 TUI의 실행 주체가 변경되어 종료하지 않았습니다".into());
        }
        call("pane.close", json!({"pane_id":old}))?;
        old_closed = true;
        let current = export(tab)?;
        if !same_shape(&current["root"]["first"], tree)
            || current["root"]["second"]["pane_id"] != new {
            return Err("교체 후 작업 분할 보존을 확인하지 못했습니다".into());
        }
        call("layout.set_split_ratio", json!({"tab_id":tab,"path":[],"ratio":ratio}))?;
        let height = measured_height(&new, rows)?;
        for (pane, identity) in work {
            let live = call("pane.get", json!({"pane_id":pane["pane_id"]}))?["pane"].clone();
            if process(&live)?.1 != *identity { return Err("교체 후 작업 프로세스 또는 terminal ID가 변경되었습니다".into()); }
        }
        Ok(json!({"tab_id":tab,"pane_id":new,"previous_pane_id":old,"ratio":ratio,
            "height_rows":height,"status":"relaunched","subagents":"opted_in_identity_unverified"}))
    })();
    if outcome.is_err() && !old_closed {
        if let Some(identity) = new_identity {
            if let Ok(live) = call("pane.get", json!({"pane_id":new})) {
                if process(&live["pane"]).is_ok_and(|current| current == (true, identity)) {
                    if call("pane.close", json!({"pane_id":new})).is_ok() {
                        if let Ok(path) = scope_path(&new) { let _ = std::fs::remove_file(path); }
                    }
                }
            }
        }
    }
    outcome
}

fn ensure(tab: &str, config: &Value, scope: Option<&(String, String)>, replace: bool) -> Result<Value> {
    let snapshot = call("session.snapshot", json!({}))?["snapshot"].clone();
    let original = export(tab)?;
    if original["zoomed"] == true {
        return Err("확대된 탭은 재배치하지 않습니다. 먼저 확대를 해제하세요".into());
    }
    let panes = snapshot["panes"]
        .as_array()
        .ok_or("pane 목록이 없습니다")?
        .iter()
        .filter(|pane| pane["tab_id"] == tab)
        .cloned()
        .collect::<Vec<_>>();
    let mut bars = Vec::new();
    let mut work = Vec::new();
    for pane in &panes {
        let (is_bar, identity) = process(pane)?;
        if is_bar {
            bars.push(string(pane, "pane_id"));
        } else {
            work.push((pane.clone(), identity));
        }
    }
    if bars.len() > 1 {
        return Err("상태 TUI가 두 개 이상입니다. 기존 pane을 닫지 않고 중단합니다".into());
    }
    if work.is_empty() {
        return Err("작업 pane이 없습니다. 기존 화면을 유지합니다".into());
    }
    let previous_bar = bars.first().cloned();
    if scope.is_some() && previous_bar.is_some() && !replace {
        return Ok(json!({"tab_id":tab,"pane_id":previous_bar,"status":"scope_requires_relaunch",
            "message":"기존 상태 TUI를 보존했습니다. 직접 닫은 뒤 같은 scope 명령으로 새로 여세요."}));
    }
    if let Some((parent, _)) = scope {
        if !work.iter().any(|(pane, _)| pane["pane_id"].as_str() == Some(parent.as_str()) && pane["agent"] == "codex") {
            return Err("명시한 부모 Codex pane이 이 탭에 없습니다".into());
        }
    }
    let worktree = without(&original["root"], previous_bar.as_deref().unwrap_or(""))
        .ok_or("작업 분할이 없습니다")?;
    let (ratio, target_rows) = desired_size(&string(&work[0].0, "pane_id"), &worktree, config)?;
    let correctly_placed = previous_bar.as_ref().is_some_and(|bar| {
        original["root"]["type"] == "split"
            && original["root"]["direction"] == config["direction"]
            && original["root"]["second"]["pane_id"] == *bar
            && same_shape(&original["root"]["first"], &worktree)
    });
    if replace {
        if !correctly_placed { return Err("명시 교체는 기존 전체 폭 하단 TUI에서만 지원합니다".into()); }
        return relaunch(tab, previous_bar.as_deref().unwrap(), &work, &worktree,
            config, scope.ok_or("명시 교체에는 --parent-pane이 필요합니다")?, ratio, target_rows);
    }
    if correctly_placed {
        call(
            "layout.set_split_ratio",
            json!({"tab_id":tab,"path":[],"ratio":ratio}),
        )?;
        let current = export(tab)?;
        if !same_shape(&current["root"]["first"], &worktree)
            || current["root"]["second"]["pane_id"] != previous_bar.as_deref().unwrap()
        {
            return Err("기존 상태 분할 보존 검증에 실패했습니다".into());
        }
        for (pane, identity) in &work {
            let live = call("pane.get", json!({"pane_id":pane["pane_id"]}))?["pane"].clone();
            if process(&live)?.1 != *identity {
                return Err("작업 프로세스 또는 terminal ID가 변경되었습니다".into());
            }
        }
        let height = measured_height(previous_bar.as_deref().unwrap(), target_rows)?;
        return Ok(json!({"tab_id":tab,"pane_id":previous_bar,"ratio":ratio,"height_rows":height,"status":"reused"}));
    }
    if work.len() > 2 {
        return Err(
            "새 배치는 작업 pane 1~2개인 탭만 지원합니다. 기존 분할을 유지하고 중단합니다".into(),
        );
    }
    let (anchor, secondary, direction, split_ratio) = if work.len() == 1 {
        (string(&worktree, "pane_id"), None, String::new(), 0.5)
    } else {
        if worktree["first"]["type"] != "pane" || worktree["second"]["type"] != "pane" {
            return Err("지원하지 않는 분할입니다. 기존 화면을 유지합니다".into());
        }
        (
            string(&worktree["first"], "pane_id"),
            Some(string(&worktree["second"], "pane_id")),
            string(&worktree, "direction"),
            worktree["ratio"].as_f64().ok_or("분할 비율이 없습니다")?,
        )
    };
    if anchor.is_empty() {
        return Err("작업 pane을 식별하지 못했습니다".into());
    }
    let mut parked = Vec::new();
    let outcome = (|| -> Result<Value> {
        let bar = if correctly_placed {
            previous_bar.clone().unwrap()
        } else {
            if let Some(bar) = &previous_bar {
                parked.push((bar.clone(),format!("herdr pane move {bar} --tab {tab} --split {} --target-pane {anchor} --ratio {ratio} --no-focus",string(config,"direction"))));
                park(bar, &string(&original, "workspace_id"), config)?;
            }
            if let Some(second) = &secondary {
                parked.push((second.clone(),format!("herdr pane move {second} --tab {tab} --split {direction} --target-pane {anchor} --ratio {split_ratio} --no-focus")));
                park(second, &string(&original, "workspace_id"), config)?;
            }
            let bar = if let Some(bar) = &previous_bar {
                move_back(bar, tab, &anchor, &string(config, "direction"), ratio)?;
                bar.clone()
            } else {
                let result = call(
                    "plugin.pane.open",
                    json!({"plugin_id":config["plugin_id"],"entrypoint":config["entrypoint"],
                "placement":config["placement"],"target_pane_id":anchor,"direction":config["direction"],"focus":false}),
                )?;
                let bar = string(&result["plugin_pane"]["pane"], "pane_id");
                if bar.is_empty() {
                    return Err(
                        format!("상태 pane 생성 응답을 확인할 수 없습니다: {result}").into(),
                    );
                }
                bar
            };
            if let Some(second) = &secondary {
                move_back(second, tab, &anchor, &direction, split_ratio)?;
            }
            bar
        };
        call(
            "layout.set_split_ratio",
            json!({"tab_id":tab,"path":[],"ratio":ratio}),
        )?;
        let current = export(tab)?;
        if current["root"]["direction"] != config["direction"]
            || current["root"]["second"]["pane_id"] != bar
            || !same_shape(&current["root"]["first"], &worktree)
        {
            return Err("분할 보존 검증에 실패했습니다".into());
        }
        for (pane, identity) in &work {
            let live = call("pane.get", json!({"pane_id":pane["pane_id"]}))?["pane"].clone();
            if process(&live)?.1 != *identity {
                return Err("작업 프로세스 또는 terminal ID가 변경되었습니다".into());
            }
        }
        let height = measured_height(&bar, target_rows)?;
        // Restore a temporarily displaced selection, then the originally active tab.
        let selected = string(&original, "focused_pane_id");
        if current["focused_pane_id"] != selected {
            let (origin, focus_direction) =
                if secondary.as_ref().is_some_and(|second| *second == selected) {
                    (anchor.clone(), direction.clone())
                } else if selected == anchor {
                    (
                        secondary.clone().unwrap_or_else(|| bar.clone()),
                        if secondary.is_none() || direction == "down" {
                            "up"
                        } else {
                            "left"
                        }
                        .into(),
                    )
                } else {
                    (
                        secondary.clone().unwrap_or_else(|| anchor.clone()),
                        "down".into(),
                    )
                };
            call(
                "pane.focus_direction",
                json!({"pane_id":origin,"direction":focus_direction}),
            )?;
            if snapshot["focused_tab_id"]
                .as_str()
                .is_some_and(|id| !id.is_empty())
            {
                call("tab.focus", json!({"tab_id":snapshot["focused_tab_id"]}))?;
            }
        }
        if let Some((parent, url)) = scope {
            let binding = subagent_scope(parent, &bar, url)?;
            let mut file = OpenOptions::new().write(true).create_new(true).mode(0o600)
                .open(scope_path(&bar)?)?;
            write!(file, "{binding}")?;
        }
        Ok(json!({"tab_id":tab,"pane_id":bar,"ratio":ratio,"height_rows":height,
            "status":if correctly_placed {"reused"} else {"restored"},
            "subagents":if scope.is_some() {"opted_in_identity_unverified"} else {"disabled"}}))
    })();
    outcome.map_err(|error| {
        let recovery = parked.iter().filter_map(|(pane,command)| {
            match call("pane.get",json!({"pane_id":pane})) {
                Ok(live) if live["pane"]["tab_id"] == tab => None,
                _ => Some(command.clone()),
            }
        }).collect::<Vec<_>>().join("\n");
        if recovery.is_empty() { error } else {
            format!("{error}\n임시 이동한 pane이 남아 있습니다. 먼저 원래 탭으로 복귀한 뒤 다시 배치하세요:\n{recovery}").into()
        }
    })
}

pub(super) fn entry(args: &[String]) -> Result<()> {
    let replace = args.iter().any(|arg| arg == "--relaunch");
    if args.iter().filter(|arg| arg.as_str() == "--relaunch").count() > 1 {
        return Err("--relaunch는 한 번만 지정하세요".into());
    }
    let parent_current = args.iter().any(|arg| arg == "--parent-current");
    if args.iter().filter(|arg| arg.as_str() == "--parent-current").count() > 1
        || parent_current && args.iter().any(|arg| arg == "--parent-pane") {
        return Err("--parent-current와 --parent-pane 중 하나만 한 번 지정하세요".into());
    }
    let mut args = args.iter().filter(|arg| arg.as_str() != "--relaunch").cloned().collect::<Vec<_>>();
    if let Some(index) = args.iter().position(|arg| arg == "--parent-current") {
        let context: Value = serde_json::from_str(
            &env::var("HERDR_PLUGIN_CONTEXT_JSON").unwrap_or("{}".into()),
        )?;
        let invoked = context["pane_id"].as_str().filter(|id| !id.is_empty());
        let inherited = env::var("HERDR_PANE_ID").ok().filter(|id| !id.is_empty());
        if invoked.is_some() && inherited.as_deref().is_some_and(|id| Some(id) != invoked) {
            return Err("호출 pane 문맥이 다릅니다. Codex pane에서 ~/.config/herdr/vibe-herdr bar ensure --current --parent-current를 실행하세요".into());
        }
        let parent = invoked.map(str::to_owned).or(inherited)
            .ok_or("호출 pane 문맥이 없습니다. Codex pane에서 prefix+i 또는 prefix+ㅑ를 사용하세요")?;
        let pane = call("pane.get", json!({"pane_id":parent}))?["pane"].clone();
        if pane["agent"] != "codex" || pane["agent_session"].is_null() {
            return Err("호출 pane의 공식 Codex 부모 대화가 없습니다. Codex pane에서 prefix+i 또는 prefix+ㅑ를 사용하세요. 기존 pane은 유지합니다".into());
        }
        args.splice(index..=index, ["--parent-pane".to_owned(), parent]);
    }
    let option_start = args.iter().position(|arg| arg == "--parent-pane").unwrap_or(args.len());
    let scope = view_options(&args[option_start..])?;
    let tab = match &args[..option_start] {
        [command, flag, tab] if command == "ensure" && flag == "--tab" => tab.clone(),
        [command, flag] if command == "ensure" && flag == "--current" => {
            let context: Value = serde_json::from_str(
                &env::var("HERDR_PLUGIN_CONTEXT_JSON").unwrap_or("{}".into()),
            )?;
            context["tab_id"]
                .as_str()
                .filter(|id| !id.is_empty())
                .map(str::to_owned)
                .or_else(|| env::var("HERDR_TAB_ID").ok())
                .ok_or("현재 탭 문맥이 없습니다. bar ensure --tab <ID>로 지정하세요")?
        }
        _ => return Err("사용법: vibe-herdr bar ensure --current|--tab <ID> [--parent-current|--parent-pane <ID> [--api-url <URL>]] [--relaunch]".into()),
    };
    let socket = PathBuf::from(env::var("HERDR_SOCKET_PATH")?);
    let lock = OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .mode(0o600)
        .open(socket.with_extension("vibe-bar.lock"))?;
    lock.try_lock_exclusive()
        .map_err(|_| "다른 상태 배치 명령이 실행 중입니다. 잠시 후 다시 실행하세요")?;
    let config: Value = serde_json::from_str(include_str!("../bar.json"))?;
    let outcome = ensure(&tab,&config,scope.as_ref(),replace).and_then(|result| {
        if parent_current && !replace && result["status"] == "scope_requires_relaunch" {
            if let (Some((parent, url)), Some(bar)) = (scope.as_ref(), result["pane_id"].as_str()) {
                let saved: Option<Value> = scope_path(bar).ok()
                    .and_then(|path| std::fs::read_to_string(path).ok())
                    .and_then(|text| serde_json::from_str(&text).ok());
                if saved.is_some() && saved == subagent_scope(parent, bar, url).ok() {
                    return ensure(&tab, &config, None, false);
                }
            }
        }
        Ok(result)
    });
    match outcome {
        Ok(result) => { println!("{result}"); Ok(()) },
        Err(error) => Err(format!("{error}\n기존 작업 pane은 닫지 않았습니다. 현재 위치 확인: herdr pane list\n다시 배치: ~/.config/herdr/vibe-herdr bar ensure --tab {tab}").into()),
    }
}
