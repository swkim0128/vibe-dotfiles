//! Manual, bounded layout repair. Never replaces a terminal or closes a pane.
use super::{rpc_timeout, string, Result};
use fs2::FileExt;
use serde_json::{json, Value};
use std::env;
use std::fs::OpenOptions;
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
        if same_binary && argv.is_some_and(|v| v.len() == 2 && v[1] == "view") {
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

fn ensure(tab: &str, config: &Value) -> Result<Value> {
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
    let worktree = without(&original["root"], previous_bar.as_deref().unwrap_or(""))
        .ok_or("작업 분할이 없습니다")?;
    let ratio = config["ratio"]
        .as_f64()
        .ok_or("상태 영역 비율이 없습니다")?;
    let correctly_placed = previous_bar.as_ref().is_some_and(|bar| {
        original["root"]["type"] == "split"
            && original["root"]["direction"] == config["direction"]
            && original["root"]["second"]["pane_id"] == *bar
            && same_shape(&original["root"]["first"], &worktree)
    });
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
        return Ok(json!({"tab_id":tab,"pane_id":previous_bar,"ratio":ratio,"status":"reused"}));
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
        Ok(
            json!({"tab_id":tab,"pane_id":bar,"ratio":ratio,"status":if correctly_placed {"reused"} else {"restored"}}),
        )
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
    let tab = match args {
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
        _ => return Err("사용법: vibe-herdr bar ensure --current | bar ensure --tab <ID>".into()),
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
    match ensure(&tab,&config) {
        Ok(result) => { println!("{result}"); Ok(()) },
        Err(error) => Err(format!("{error}\n기존 작업 pane은 닫지 않았습니다. 현재 위치 확인: herdr pane list\n다시 배치: ~/.config/herdr/vibe-herdr bar ensure --tab {tab}").into()),
    }
}
