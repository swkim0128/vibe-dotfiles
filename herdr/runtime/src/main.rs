//! Local display transport. Semantic agent state belongs to Herdr.
use regex::Regex;
use serde_json::{json, Value};
use std::env;
use std::fs::{self, OpenOptions};
use std::io::{self, BufRead, BufReader, Read, Write};
use std::os::unix::fs::MetadataExt;
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use unicode_width::UnicodeWidthChar;

type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
mod bar;
mod dock;
mod actions;

fn run(program: &str, args: &[&str], timeout: Duration) -> Result<String> {
    let mut child = Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()?;
    let output = child.stdout.take().unwrap();
    let (sender, receiver) = std::sync::mpsc::channel();
    thread::spawn(move || {
        let mut bytes = Vec::new();
        let result = output
            .take(1_048_576)
            .read_to_end(&mut bytes)
            .map(|_| bytes);
        let _ = sender.send(result);
    });
    let start = Instant::now();
    loop {
        if let Some(status) = child.try_wait()? {
            let bytes = receiver.recv_timeout(timeout.saturating_sub(start.elapsed()))??;
            if !status.success() {
                return Err(format!("{program}: {status}").into());
            }
            return Ok(String::from_utf8(bytes)?.trim().to_owned());
        }
        if start.elapsed() >= timeout {
            let _ = child.kill();
            let _ = child.wait();
            return Err(io::Error::new(io::ErrorKind::TimedOut, program.to_owned()).into());
        }
        thread::sleep(Duration::from_millis(2));
    }
}

fn quick(program: &str, args: &[&str]) -> Option<String> {
    run(program, args, Duration::from_millis(500)).ok()
}

fn now() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64()
}
fn home() -> PathBuf {
    PathBuf::from(env::var_os("HOME").unwrap_or_default())
}
fn string(value: &Value, key: &str) -> String {
    value[key].as_str().unwrap_or("").to_owned()
}

fn plain(value: &str, width: usize) -> String {
    let re = Regex::new(r"\x1b\[[0-?]*[ -/]*[@-~]|#\[[^]]*\]|\p{C}").unwrap();
    let clean = re.replace_all(value, "");
    let mut result = String::new();
    let mut size = 0;
    for c in clean
        .chars()
        .filter(|c| !c.is_control() && c.width().is_some())
    {
        size += c.width().unwrap_or(0);
        if size > width {
            result.push('…');
            break;
        }
        result.push(c);
    }
    result
}

fn dock(cache: &Path) -> String {
    dock::read(cache)
}

fn metrics() -> Value {
    let cpu = quick("ps", &["-A", "-o", "%cpu="])
        .and_then(|text| {
            text.split_whitespace()
                .map(str::parse::<f64>)
                .collect::<std::result::Result<Vec<_>, _>>()
                .ok()
        })
        .map(|values| {
            format!(
                "CPU~{:.0}%",
                values.iter().sum::<f64>()
                    / thread::available_parallelism()
                        .map(|n| n.get())
                        .unwrap_or(1) as f64
            )
        })
        .unwrap_or("CPU?".into());
    let ram = quick("vm_stat", &[])
        .and_then(|text| {
            let page = Regex::new(r"page size of (\d+) bytes")
                .ok()?
                .captures(&text)?[1]
                .parse::<f64>()
                .ok()?;
            let mut count = 0.0;
            for key in [
                "Pages active",
                "Pages wired down",
                "Pages occupied by compressor",
            ] {
                let line = text
                    .lines()
                    .find(|line| line.starts_with(&format!("{key}:")))?;
                count += line
                    .split(':')
                    .nth(1)?
                    .trim()
                    .trim_end_matches('.')
                    .parse::<f64>()
                    .ok()?;
            }
            Some(format!("RAM{:.1}GiB", count * page / 1_073_741_824.0))
        })
        .unwrap_or("RAM?".into());
    let battery = quick("pmset", &["-g", "batt"])
        .and_then(|text| {
            Some(format!(
                "BAT{}%",
                &Regex::new(r"(\d+)%").ok()?.captures(&text)?[1]
            ))
        })
        .unwrap_or("AC/BAT?".into());
    json!({"sys_cpu":cpu,"sys_ram":ram,"sys_battery":battery})
}

fn rpc(method: &str, params: Value) -> Result<Value> {
    rpc_timeout(method, params, Duration::from_millis(300))
}

fn rpc_timeout(method: &str, params: Value, timeout: Duration) -> Result<Value> {
    let mut client = UnixStream::connect(env::var("HERDR_SOCKET_PATH")?)?;
    client.set_read_timeout(Some(timeout))?;
    client.set_write_timeout(Some(timeout))?;
    writeln!(
        client,
        "{}",
        json!({"id":"vibe-display","method":method,"params":params})
    )?;
    let mut response = String::new();
    BufReader::new(client.take(1_048_576)).read_line(&mut response)?;
    let value: Value = serde_json::from_str(&response)?;
    if value.get("error").is_some() {
        return Err(format!("Herdr: {}", value["error"]).into());
    }
    value
        .get("result")
        .cloned()
        .ok_or_else(|| "Herdr response missing result".into())
}

fn metadata(method: &str, mut params: Value) -> Result<Value> {
    params["seq"] = json!(SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos() as u64);
    params["ttl_ms"] = json!(15000);
    rpc(method, params)
}

fn refresh_status(tokens: &Value) -> Result<()> {
    let workspaces = rpc("workspace.list", json!({}))?;
    for workspace in workspaces["workspaces"]
        .as_array()
        .ok_or("missing workspaces")?
    {
        metadata(
            "workspace.report_metadata",
            json!({"workspace_id":workspace["workspace_id"],
            "source":"vibe:status","tokens":tokens}),
        )?;
    }
    Ok(())
}

fn refresh_paths() -> Result<Value> {
    let result = rpc("pane.list", json!({}))?;
    let home = home().to_string_lossy().into_owned();
    for pane in result["panes"].as_array().ok_or("missing panes")? {
        let agent = string(pane, "agent");
        if agent.is_empty() {
            continue;
        }
        let cwd = pane["foreground_cwd"]
            .as_str()
            .filter(|s| !s.is_empty())
            .or_else(|| pane["cwd"].as_str())
            .unwrap_or("");
        if cwd.is_empty() {
            continue;
        }
        let path = if cwd == home || cwd.starts_with(&format!("{home}/")) {
            format!("~{}", &cwd[home.len()..])
        } else {
            cwd.into()
        };
        let title = if agent == "codex" {
            let branch = quick("git", &["-C", cwd, "branch", "--show-current"]).unwrap_or_default();
            let native = pane["terminal_title_stripped"]
                .as_str()
                .filter(|s| !s.is_empty())
                .or_else(|| pane["terminal_title"].as_str())
                .unwrap_or("");
            let details = native.split_once(" | ").map(|(_, s)| s).unwrap_or("");
            let details = if branch.is_empty() {
                details
            } else {
                details
                    .strip_prefix(&format!("{branch} | "))
                    .unwrap_or(details)
            };
            let (model, task) = details.split_once(" | ").unwrap_or((details, ""));
            format!(
                "{path} | {} | {} | {}",
                if branch.is_empty() { "-" } else { &branch },
                if model.is_empty() {
                    "모델 미확인"
                } else {
                    model
                },
                if task.is_empty() {
                    "작업 제목 미확인"
                } else {
                    task
                }
            )
        } else {
            format!("{agent} · {path}")
        };
        metadata(
            "pane.report_metadata",
            json!({"pane_id":pane["pane_id"],"source":"vibe:project",
            "agent":agent,"title":title,"tokens":{"project_path":path}}),
        )?;
    }
    Ok(result)
}

fn hud(panes: Option<&Value>, generation: Option<u64>) {
    let Ok(workspace) = env::var("HERDR_ACTIVE_WORKSPACE_ID") else {
        return;
    };
    if let Some(panes) = panes.and_then(|result| result["panes"].as_array()) {
        let active = panes
            .iter()
            .filter(|pane| {
                pane["workspace_id"] == workspace
                    && pane["agent"].as_str().is_some_and(|s| !s.is_empty())
            })
            .collect::<Vec<_>>();
        if active.iter().all(|pane| pane["agent_session"].is_null()) {
            for pane in active {
                let current_generation = env::var("HERDR_SOCKET_PATH")
                    .ok()
                    .and_then(|path| fs::metadata(path).ok())
                    .map(|meta| meta.ino());
                if generation.is_none() || current_generation != generation {
                    return;
                }
                let _ = metadata(
                    "pane.report_metadata",
                    json!({"pane_id":pane["pane_id"],"source":"vibe:display","tokens":{"hud":"HUD 미연결"}}),
                );
            }
            return;
        }
    }
    // The dashboard exposes its configured storage contract as a Python API.
    // Keep its exact identity checks there; no legacy-file fallback in Rust.
    let script = env::var_os("VIBE_HERDR_HUD_ADAPTER")
        .map(PathBuf::from)
        .unwrap_or(home().join(".config/herdr/hud.py"));
    if let Some(path) = script.to_str() {
        let _ = run("python3", &["-B", path], Duration::from_secs(2));
    }
}

fn status(sidebar_only: bool) {
    let cache = env::var_os("VIBE_CACHE_DIR")
        .map(PathBuf::from)
        .unwrap_or(home().join(".cache/vibe"));
    let notifications = dock(&cache);
    let mut tokens = metrics();
    tokens["sys_notifications"] = json!(if notifications.starts_with("알림") {
        notifications.clone()
    } else {
        format!("알림 {notifications}")
    });
    tokens["sys_datetime"] = json!(quick("date", &["+%Y-%m-%d %H:%M"]).unwrap_or("시각?".into()));
    let _ = refresh_status(&tokens);
    let generation = env::var("HERDR_SOCKET_PATH")
        .ok()
        .and_then(|path| fs::metadata(path).ok())
        .map(|meta| meta.ino());
    let panes = refresh_paths().ok();
    hud(panes.as_ref(), generation);
    if !sidebar_only {
        println!(
            "{notifications} · {} {} {}",
            tokens["sys_cpu"].as_str().unwrap(),
            tokens["sys_ram"].as_str().unwrap(),
            tokens["sys_battery"].as_str().unwrap()
        );
    }
}

fn hs_cli() -> Result<String> {
    for root in env::split_paths(&env::var_os("PATH").unwrap_or_default()) {
        let path = root.join("hs");
        if path.is_file() {
            return Ok(path.to_string_lossy().into_owned());
        }
    }
    for root in [home().join("Applications"), PathBuf::from("/Applications")] {
        let path = root.join("Hammerspoon.app/Contents/Frameworks/hs/hs");
        if path.is_file() {
            return Ok(path.to_string_lossy().into_owned());
        }
    }
    Err("Hammerspoon CLI missing: brew install --cask hammerspoon".into())
}

fn notify(test: Option<&str>) -> Result<()> {
    let payload = if let Some(status) = test {
        if !["done", "blocked"].contains(&status) {
            return Err("test status must be done or blocked".into());
        }
        json!({"status":status,"text":"상단 중앙 알림 연결 테스트"})
    } else {
        let event: Value = serde_json::from_str(&env::var("HERDR_PLUGIN_EVENT_JSON")?)?;
        let data = &event["data"];
        let status = string(data, "agent_status");
        if !["done", "blocked"].contains(&status.as_str()) {
            return Ok(());
        }
        let context: Value =
            serde_json::from_str(&env::var("HERDR_PLUGIN_CONTEXT_JSON").unwrap_or("{}".into()))?;
        let choose = |a: &Value, b: &Value| {
            a.as_str()
                .filter(|s| !s.is_empty())
                .or_else(|| b.as_str())
                .unwrap_or("")
                .to_owned()
        };
        let location = [
            choose(&context["workspace_label"], &data["workspace_id"]),
            string(data, "pane_id"),
            choose(&data["display_agent"], &data["agent"]),
        ]
        .into_iter()
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>()
        .join(" · ");
        let title = choose(&data["title"], &context["tab_label"])
            .split_whitespace()
            .collect::<Vec<_>>()
            .join(" ");
        json!({"status":status,"text":format!("{location}\n{title}").chars().take(300).collect::<String>()})
    };
    let encoded = serde_json::to_vec(&payload)?
        .iter()
        .map(|byte| format!("\\{byte:03}"))
        .collect::<String>();
    let code = format!("local id = vibeHerdrAlert(hs.json.decode(\"{encoded}\")) return id");
    let receipt = run(&hs_cli()?, &["-c", &code], Duration::from_secs(5))?;
    let id = receipt
        .lines()
        .last()
        .ok_or("Hammerspoon did not acknowledge the alert")?;
    if !Regex::new(
        r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
    )?
    .is_match(id)
    {
        return Err("Hammerspoon response is not a UUID".into());
    }
    println!("{id}");
    Ok(())
}

fn usage() -> Result<()> {
    use fs2::FileExt;
    let cache = env::var_os("VIBE_CACHE_DIR")
        .map(PathBuf::from)
        .unwrap_or(home().join(".cache/vibe"));
    fs::create_dir_all(&cache)?;
    let path = cache.join("herdr-codexbar.json");
    let saved: Value = fs::read_to_string(&path)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or(json!({}));
    let age = now() - saved["at"].as_f64().unwrap_or(0.0);
    if (0.0..60.0).contains(&age) && saved["label"].is_string() {
        println!("{}", string(&saved, "label"));
        return Ok(());
    }
    let lock = OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .open(cache.join("herdr-codexbar.lock"))?;
    if lock.try_lock_exclusive().is_err() {
        println!("CB?조회중");
        return Ok(());
    }
    let binary = env::var("CODEXBAR_CLI")
        .unwrap_or("/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI".into());
    let mut label = match run(
        &binary,
        &[
            "usage",
            "--provider",
            "codex",
            "--source",
            "cli",
            "--format",
            "json",
            "--no-credits",
        ],
        Duration::from_secs(8),
    ) {
        Ok(text) => match serde_json::from_str::<Vec<Value>>(&text) {
            Ok(items) => items
                .iter()
                .find_map(|item| {
                    if item["provider"] != "codex"
                        || item["error"].as_bool() == Some(true)
                        || item["error"].as_str().is_some_and(|s| !s.is_empty())
                    {
                        return None;
                    }
                    let values = [("primary", "5h"), ("secondary", "주")]
                        .iter()
                        .filter_map(|(key, name)| {
                            let percent = item["usage"][key]["usedPercent"].as_f64()?;
                            if !(0.0..=100.0).contains(&percent) {
                                return None;
                            }
                            Some(format!("{name}{}%", 100.0 - percent))
                        })
                        .collect::<Vec<_>>();
                    if values.is_empty() {
                        None
                    } else {
                        Some(format!("Codex {}", values.join("/")))
                    }
                })
                .unwrap_or("CB?데이터없음".into()),
            Err(_) => "CB?조회실패".into(),
        },
        Err(error) => match error.downcast_ref::<io::Error>().map(io::Error::kind) {
            Some(io::ErrorKind::NotFound) => "CB?미설치".into(),
            Some(io::ErrorKind::TimedOut) => "CB?시간초과".into(),
            _ => "CB?조회실패".into(),
        },
    };
    let success = label.starts_with("Codex ");
    let good_at = if success {
        json!(now())
    } else {
        saved["good_at"].clone()
    };
    let good_label = if success {
        json!(label)
    } else {
        saved["good_label"].clone()
    };
    if !success {
        if let (Some(at), Some(text)) = (good_at.as_f64(), good_label.as_str()) {
            let age = (now() - at).max(0.0) as u64;
            label = if age <= 300 {
                format!("{text}~{age}s")
            } else {
                format!("CB 오래됨({age}s)")
            };
        }
    }
    let temporary = path.with_extension(format!("{}.tmp", std::process::id()));
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&temporary)?;
    file.set_permissions(fs::Permissions::from_mode(0o600))?;
    write!(
        file,
        "{}",
        json!({"at":now(),"label":label,"good_at":good_at,"good_label":good_label})
    )?;
    fs::rename(temporary, path)?;
    println!("{label}");
    Ok(())
}

fn view_options(args: &[String]) -> Result<Option<(String, String)>> {
    match args {
        [] => Ok(None),
        [flag, pane] if flag == "--parent-pane" && !pane.is_empty() =>
            Ok(Some((pane.clone(), env::var("VIBE_SUBAGENTS_API_URL").unwrap_or_default()))),
        [flag, pane, api, url] if flag == "--parent-pane" && !pane.is_empty() && api == "--api-url" =>
            Ok(Some((pane.clone(), url.clone()))),
        _ => Err("사용법: view [--parent-pane <pane-id> [--api-url <loopback dashboard URL>]]".into()),
    }
}

fn view_pane() -> Option<String> {
    env::var("HERDR_PANE_ID").ok().filter(|v| !v.is_empty()).or_else(|| {
        let context: Value = serde_json::from_str(&env::var("HERDR_PLUGIN_CONTEXT_JSON").ok()?).ok()?;
        context["pane_id"].as_str().filter(|v| !v.is_empty()).map(str::to_owned)
    })
}

fn scope_path(pane: &str) -> Result<PathBuf> {
    if !pane.chars().all(|c| c.is_ascii_alphanumeric() || ":-_".contains(c)) || pane.is_empty() {
        return Err("invalid pane ID".into());
    }
    let socket = PathBuf::from(env::var("HERDR_SOCKET_PATH")?);
    Ok(socket.with_extension(format!("vibe-subagents-{}-{pane}.json", fs::metadata(&socket)?.ino())))
}

fn subagent_scope(parent_id: &str, pane_id: &str, api_url: &str) -> Result<Value> {
    let socket = PathBuf::from(env::var("HERDR_SOCKET_PATH")?);
    let generation = fs::metadata(&socket)?.ino();
    let parent = rpc_timeout("pane.get", json!({"pane_id":parent_id}), Duration::from_millis(500))?["pane"].clone();
    let pane = rpc_timeout("pane.get", json!({"pane_id":pane_id}), Duration::from_millis(500))?["pane"].clone();
    if parent_id == pane_id || parent["agent"] != "codex" || parent["tab_id"] != pane["tab_id"]
        || parent["workspace_id"] != pane["workspace_id"] || parent["terminal_id"].as_str().is_none()
        || pane["terminal_id"].as_str().is_none() || fs::metadata(&socket)?.ino() != generation {
        return Err("parent pane scope is not connected to this TUI".into());
    }
    let info = rpc_timeout("pane.process_info", json!({"pane_id":parent_id}), Duration::from_millis(500))?;
    let pids = info["process_info"]["foreground_processes"].as_array().ok_or("missing parent processes")?
        .iter().filter(|p| Path::new(p["name"].as_str().unwrap_or("")).file_name().is_some_and(|v| v == "codex"))
        .filter_map(|p| p["pid"].as_u64()).collect::<Vec<_>>();
    if pids.len() != 1 { return Err("parent Codex process is not unique".into()); }
    let parent_stamp = run("ps", &["-p", &pids[0].to_string(), "-o", "lstart=", "-o", "comm="], Duration::from_millis(300))?;
    if parent_stamp.is_empty() { return Err("parent Codex process ended".into()); }
    let view_info = rpc_timeout("pane.process_info", json!({"pane_id":pane_id}), Duration::from_millis(500))?;
    let view_processes = view_info["process_info"]["foreground_processes"].as_array().ok_or("missing TUI processes")?;
    let executable = env::current_exe()?.canonicalize()?;
    let view_pids = view_processes.iter().filter(|process| {
        let Some(argv) = process["argv"].as_array() else { return false; };
        let Some(first) = argv.first().and_then(Value::as_str) else { return false; };
        let path = if Path::new(first).is_absolute() { PathBuf::from(first) }
            else { PathBuf::from(string(process,"cwd")).join(first) };
        path.canonicalize().is_ok_and(|path| path == executable)
            && argv.get(1).and_then(Value::as_str) == Some("view")
    }).filter_map(|process| process["pid"].as_u64()).collect::<Vec<_>>();
    if view_pids.len() != 1 { return Err("TUI process is not ready or unique; no scope was installed".into()); }
    Ok(json!({"parent_pane":parent_id,"view_pane":pane_id,"view_terminal":pane["terminal_id"],
        "parent_terminal":parent["terminal_id"],"parent_session":parent["agent_session"],
        "parent_cli_pids":pids,"parent_stamp":parent_stamp,"socket_generation":generation,"api_url":api_url,"view_pid":view_pids[0]}))
}

fn subagent_line(scope: &mut Value, style: &Value) -> String {
    if scope["view_pid"].as_u64() != Some(u64::from(std::process::id())) {
        return "서브 TUI 연결 미확인".into();
    }
    scope["http_timeout_seconds"] = style["subagents"]["http_timeout_seconds"].clone();
    let script = env::var_os("VIBE_HERDR_HUD_ADAPTER").map(PathBuf::from)
        .unwrap_or(home().join(".config/herdr/hud.py"));
    let python = home().join(string(&style["subagents"], "python_relative_path"));
    let result = (|| -> Result<Value> {
        let raw = run(python.to_str().ok_or("invalid adapter Python path")?, &["-B", script.to_str().ok_or("invalid adapter path")?,
            "--subagents", &scope.to_string()], Duration::from_secs(style["subagents"]["adapter_timeout_seconds"].as_u64().unwrap_or(3)))?;
        Ok(serde_json::from_str(&raw)?)
    })();
    let Ok(result) = result else { return "서브 조회 실패".into(); };
    if !result["binding"].is_null() && scope["binding"].is_null() {
        scope["binding"] = result["binding"].clone();
    }
    match result["state"].as_str() {
        Some("parent_unbound") => return "서브 부모 대화 미연결".into(),
        Some("unconnected") => return "서브 연결 불일치".into(),
        Some("observed") => {},
        _ => return "서브 조회 실패".into(),
    }
    let ttl = style["subagents"]["ttl_seconds"].as_f64().unwrap_or(60.0);
    let age = result["age"].as_f64().unwrap_or(f64::INFINITY);
    let Some(running) = result["data"]["running"].as_array() else { return "서브 조회 실패".into(); };
    let limit = style["subagents"]["max_agents"].as_u64().unwrap_or(2) as usize;
    let id_chars = style["subagents"]["id_chars"].as_u64().unwrap_or(8) as usize;
    let labels = running.iter().take(limit).map(|agent| {
        let role = agent["agent_name"].as_str().filter(|v| !v.is_empty())
            .or_else(|| agent["agent_type"].as_str().filter(|v| !v.is_empty())).unwrap_or("역할 미확인");
        let id = agent["agent_id"].as_str().unwrap_or("?");
        let suffix = id.chars().rev().take(id_chars).collect::<String>().chars().rev().collect::<String>();
        format!("{}#{}", plain(role, 20), suffix)
    }).collect::<Vec<_>>().join(" · ");
    if age < 0.0 || age > ttl {
        return if labels.is_empty() { "서브 현재 관측 오래됨".into() }
            else { format!("서브 현재 관측 오래됨 · {labels}") };
    }
    let current_provider = result["data"]["observation"]["kind"] == "codex-app-server";
    if !current_provider {
        return if running.is_empty() { "서브 현재 관측 없음".into() }
            else { format!("서브 과거 실행 관측 {} · {labels}", running.len()) };
    }
    if running.is_empty() {
        let mut summary = "서브 실행 0".to_owned();
        if let Some(recent) = result["data"]["recent"].as_array() {
            let limited = result["data"]["counts"]["recent"].as_u64().unwrap_or(0) > recent.len() as u64;
            for (state, label) in [("idle", "유휴"), ("notLoaded", "미적재"), ("systemError", "오류")] {
                let count = recent.iter().filter(|agent| agent["state"] == state).count();
                if count > 0 { summary.push_str(&format!(" · {label}{}{count}", if limited { "≥" } else { " " })); }
            }
        }
        return summary;
    }
    format!("서브 실행 관측 {} · {labels}{}", running.len(),
        if running.len() > limit { format!(" · +{}", running.len() - limit) } else { String::new() })
}

fn task_observation(scope: Option<&mut Value>, style: &Value) -> Value {
    let Some(scope) = scope else { return json!({"state":"unconnected","reason":"공식 부모 연결 미확인"}); };
    if scope["view_pid"].as_u64() != Some(u64::from(std::process::id())) {
        return json!({"state":"unconnected","reason":"현재 TUI scope 아님"});
    }
    scope["queue_timeout_seconds"] = style["task"]["queue_timeout_seconds"].clone();
    let script = env::var_os("VIBE_HERDR_HUD_ADAPTER").map(PathBuf::from)
        .unwrap_or(home().join(".config/herdr/hud.py"));
    let python = home().join(string(&style["subagents"], "python_relative_path"));
    let result = (|| -> Result<Value> {
        let raw = run(python.to_str().ok_or("invalid adapter Python path")?,
            &["-B", script.to_str().ok_or("invalid adapter path")?, "--current-task", &scope.to_string()],
            Duration::from_secs(style["task"]["adapter_timeout_seconds"].as_u64().unwrap_or(6)))?;
        Ok(serde_json::from_str(&raw)?)
    })();
    let result = result.unwrap_or_else(|_| json!({"state":"failed"}));
    if !result["binding"].is_null() && scope["binding"].is_null() {
        scope["binding"] = result["binding"].clone();
    }
    result
}

fn task_line(task: &Value, style: &Value) -> String {
    match task["state"].as_str() {
        Some("parent_unbound") => return "작업 thread 부모 미연결 · t 상세".into(),
        Some("unconnected") => return "작업 thread 연결 불일치/미확인 · t 상세".into(),
        Some("observed") => {},
        _ => return "작업 thread 조회 실패 · 현재 상태 미확인 · t 상세".into(),
    }
    let thread = task["thread"].as_str().unwrap_or("?").chars().take(8).collect::<String>();
    let at = task["observed_at"].as_str().unwrap_or("미확인");
    let at = at.get(11..19).unwrap_or(at);
    let Some(record) = task["records"].as_array().and_then(|records| records.first()) else {
        let count = task["requests"].as_array().map_or(0, Vec::len);
        return format!("작업 thread {thread} · 요청 {count} · 선택/진척 미확인 · 확인 {at} · t 상세");
    };
    let stage = record["stage"].as_str().unwrap_or("세부단계 미기록");
    let freshness = match record["updated_age"].as_f64() {
        Some(age) if age < 0.0 || age > style["task"]["stale_seconds"].as_f64().unwrap_or(60.0) => " · 기록 오래됨",
        None => " · 기록 갱신시각 미확인",
        _ => "",
    };
    format!("작업 {thread}/#{} · 확인 {at} · {stage} · {}{freshness} · {} · t 상세",
        record["id"], string(record, "state"), plain(&string(record, "goal"), 40))
}

const TASK_DETAIL_BUTTON: &str = "[t 작업 상세]";

fn task_rows(task: &Value, style: &Value) -> Vec<String> {
    let thread = task["thread"].as_str().unwrap_or("미확인").chars().take(8).collect::<String>();
    let observed = task["observed_at"].as_str().unwrap_or("미확인");
    let at = observed.get(11..19).unwrap_or(observed);
    let record = task["records"].as_array().and_then(|records| records.first());
    if task["state"] != "observed" || record.is_none() {
        return vec![format!("현재 작업  설정 스레드 {thread} · 확인 {at}"),
            "목표       연결된 작업 상세에서 확인".into(),
            format!("상태       {}", task_line(task, style)),
            format!("최근 결과  {}", task["reason"].as_str().unwrap_or("선택된 작업 결과 미확인")),
            "다음 행동  작업 상세에서 연결 상태와 요청 목록 확인".into()];
    }
    let record = record.unwrap();
    let freshness = match record["updated_age"].as_f64() {
        Some(age) if age < 0.0 || age > style["task"]["stale_seconds"].as_f64().unwrap_or(60.0) => "기록 오래됨",
        None => "기록 갱신시각 미확인",
        _ => "최근 갱신 기록",
    };
    let wait = record["wait"].as_str().filter(|v| !v.is_empty());
    let state = if let Some(reason) = wait { format!("{} · 대기: {reason}", string(record, "state")) }
        else { string(record, "state") };
    let next = if matches!(record["queue_status"].as_str(), Some("done" | "failed")) {
        "종료 기록 · 후속 안내는 작업 상세에서 확인"
    } else { record["next_action"].as_str().filter(|v| !v.is_empty()).unwrap_or("미기록") };
    vec![format!("현재 작업  #{} · 스레드 {thread} · 확인 {at} · {freshness}", record["id"]),
        format!("목표       {}", string(record, "goal")),
        format!("상태       {state}    │ 단계  {}", record["stage"].as_str().unwrap_or("미기록")),
        format!("최근 결과  {}", record["result"].as_str().filter(|v| !v.is_empty()).unwrap_or("현재 판본의 결과 미확인")),
        format!("다음 행동  {next}")]
}

fn task_overlay(output: &mut impl Write, width: u16, height: u16, task: &Value, offset: &mut usize) -> Result<()> {
    use crossterm::{cursor, execute};
    let mut lines = vec![format!("스레드: {}", string(task, "thread")),
        format!("관측: {} · 확인 {} · {} {}", string(task, "state"), string(task, "observed_at"), string(task, "phase"), string(task, "error_type")),
        format!("연결: {}", task["reason"].as_str().unwrap_or(if task["state"] == "observed" {
            "공식 부모 thread/PID/cwd 검증 · public vibe queue" } else { "검증/조회 미완료" })),
        "에이전트·thread·pane은 별개 · 실행/접수/열람은 완료·승인 근거 아님".into()];
    if task["state"] != "observed" {
        lines.push(format!("연결 확인 후 Codex 패널에서 실행: {} bar ensure --current --parent-current --relaunch",
            home().join(".config/herdr/vibe-herdr").display()));
    }
    for record in task["records"].as_array().into_iter().flatten() {
        lines.extend([format!("요청 #{} 목표: {}", record["id"], string(record, "goal")),
            format!("현재 단계: {} · 상태: {} · 큐 기록: {}", record["stage"].as_str().unwrap_or("세부단계 미기록"), string(record, "state"), string(record, "queue_status")),
            format!("대기사유: {}", record["wait"].as_str().filter(|v| !v.is_empty()).unwrap_or("미기록")),
            format!("현재 단계/판본/시도의 실제 결과: {}", record["result"].as_str().filter(|v| !v.is_empty()).unwrap_or("미확인")),
            format!("실행 판본: {} · 시도 {} · 기록 갱신 {}", record["version"], record["attempt"], record["updated_at"].as_str().unwrap_or("미확인")),
            format!("다음 행동(저장된 재개조건/안내): {}", record["next_action"].as_str().filter(|v| !v.is_empty()).unwrap_or("미확인"))]);
        if record["artifacts"].as_array().is_none_or(Vec::is_empty) {
            lines.push("확인 산출물/판본/원문 참조: 미기록 · 열람을 확인으로 추정하지 않음".into());
        }
        for artifact in record["artifacts"].as_array().into_iter().flatten() {
            lines.extend([format!("산출물 {} / {} v{} · 확인 {}", artifact["stage"], artifact["id"], artifact["version"], string(artifact, "decision")),
                format!("원문 참조: {}", artifact["reference"]),
                format!("확인 근거: {}", artifact["confirmation_reference"])]);
        }
    }
    for request in task["requests"].as_array().into_iter().flatten() {
        lines.push(format!("연결 요청 #{} · 큐 {} · {}", request["id"], string(request, "status"), string(request, "goal")));
    }
    if task["limited"] == true { lines.push("연결 요청 목록 일부만 표시".into()); }
    if let Some(subagents) = task["subagents"].as_str() { lines.push(format!("별도 서브 실행 관측: {subagents}")); }
    let columns = usize::from(width).max(1);
    let mut wrapped = Vec::new();
    for line in lines {
        let mut row = String::new();
        let mut used = 0;
        for c in line.chars().filter(|c| !c.is_control()) {
            let size = c.width().unwrap_or(0);
            if used + size > columns && !row.is_empty() { wrapped.push(row); row = String::new(); used = 0; }
            row.push(c); used += size;
        }
        wrapped.push(row);
    }
    let visible = usize::from(height.saturating_sub(1));
    *offset = (*offset).min(wrapped.len().saturating_sub(visible));
    for (index, line) in wrapped.iter().skip(*offset).take(visible).enumerate() {
        execute!(output, cursor::MoveTo(0, index as u16))?;
        write!(output, "{}", plain(line, columns))?;
    }
    if height > 0 {
        execute!(output, cursor::MoveTo(0, height - 1))?;
        write!(output, "{}", plain("작업 상세 · ↑↓ 스크롤 · s 서브관측 · t/Esc 복귀 · /agents에서 기존 thread 선택", columns))?;
    }
    output.flush()?;
    Ok(())
}

fn render_view(
    output: &mut impl Write,
    values: &Value,
    notifications: &str,
    date: &str,
    style: &Value,
    task: &Value,
    interaction: (&actions::Actions, usize, Option<(&Value, &mut usize)>),
) -> Result<Vec<actions::Hit>> {
    use crossterm::{cursor, execute, terminal};
    let (actions, notification_offset, task_detail) = interaction;
    let (width, height) = terminal::size()?;
    execute!(
        output,
        cursor::MoveTo(0, 0),
        terminal::Clear(terminal::ClearType::All)
    )?;
    if let Some((task, offset)) = task_detail { task_overlay(output, width, height, task, offset)?; return Ok(vec![]); }
    if actions.open { return actions.overlay(output, width, height); }
    let summary = task_line(task, style);
    let subagents = Some(summary.as_str());
    let mut action_hits = Vec::new();
    if height >= 7 {
        let columns = usize::from(width);
        for (index, line) in task_rows(task, style).iter().enumerate() {
            execute!(output, cursor::MoveTo(0, index as u16))?;
            let color = if index == 0 { string(style, "heading") } else { "0".into() };
            write!(output, "\x1b[{color}m{}\x1b[0m", plain(line, columns))?;
        }
        let system = format!("{} {} {} · {date}", string(values, "sys_cpu"), string(values, "sys_ram"), string(values, "sys_battery"));
        let system_width = unicode_width::UnicodeWidthStr::width(system.as_str());
        let notice_width = columns.saturating_sub(system_width + 3);
        execute!(output, cursor::MoveTo(0, height - 2))?;
        if notice_width >= 20 {
            write!(output, "{}", plain(notifications, notice_width))?;
            execute!(output, cursor::MoveTo((columns - system_width) as u16, height - 2))?;
            write!(output, "{}", plain(&system, system_width))?;
        } else { write!(output, "{}", plain(notifications, columns))?; }
        let row = height - 1;
        execute!(output, cursor::MoveTo(0, row))?;
        write!(output, "{}", plain(TASK_DETAIL_BUTTON, columns))?;
        let (_, buttons, hits) = actions.bar(width, row);
        if !buttons.is_empty() {
            execute!(output, cursor::MoveTo(hits.first().map(|hit| hit.start).unwrap_or(0), row))?;
            write!(output, "{buttons}")?;
            action_hits.extend(hits);
        }
    } else {
        let width = usize::from(width).saturating_sub(2);
        let mut rows = style["compact"]["rows"]
            .as_array()
            .ok_or("missing compact rows")?.clone();
        if subagents.is_some() && usize::from(height) > rows.len() {
            let before = style["subagents"]["before"].as_str().unwrap_or("notifications");
            let position = rows.iter().position(|row| row.as_str() == Some(before)).unwrap_or(0);
            rows.insert(position, json!("subagents"));
        }
        let visible = rows.len().min(usize::from(height));
        for (index, row) in rows.iter().skip(rows.len() - visible).enumerate() {
            let y = if style["compact"]["align"] == "bottom" {
                height - visible as u16 + index as u16
            } else if style["compact"]["align"] == "edges" && index + 1 == visible {
                height - 1
            } else {
                index as u16
            };
            let (notification_width, buttons, hits) = if row == "notifications" {
                actions.bar(width as u16, y)
            } else { (width as u16, String::new(), Vec::new()) };
            let (text, color) = match row.as_str() {
                Some("subagents") => (subagents.unwrap_or_default().to_owned(), string(&style["subagents"], "color")),
                Some("notifications") => {
                    let notification_width = usize::from(notification_width);
                    let text = if unicode_width::UnicodeWidthStr::width(notifications) > notification_width {
                        let mut used = 0;
                        let text = notifications.chars().skip(notification_offset)
                            .take_while(|c| {
                                used += c.width().unwrap_or(0);
                                used <= notification_width.saturating_sub(2)
                            }).collect::<String>();
                        format!("↔ {text}")
                    } else { notifications.to_owned() };
                    (text, string(style, "notifications"))
                }
                Some("metrics_datetime") => {
                    let metrics = format!(
                        "{} {} {}",
                        string(values, "sys_cpu"),
                        string(values, "sys_ram"),
                        string(values, "sys_battery")
                    );
                    let mut date = date.to_owned();
                    while unicode_width::UnicodeWidthStr::width(date.as_str()) > width {
                        date.remove(0);
                    }
                    let remaining = width
                        .saturating_sub(unicode_width::UnicodeWidthStr::width(date.as_str()) + 3);
                    let text = if remaining == 0 {
                        date
                    } else {
                        let metrics = if unicode_width::UnicodeWidthStr::width(metrics.as_str())
                            <= remaining
                        {
                            metrics
                        } else {
                            plain(&metrics, remaining - 1)
                        };
                        format!("{metrics} | {date}")
                    };
                    (text, string(style, "heading"))
                }
                _ => return Err("unknown compact row".into()),
            };
            execute!(output, cursor::MoveTo(0, y))?;
            let mut text = plain(&text, if row == "notifications" { usize::from(notification_width) } else { width });
            if row == "metrics_datetime" {
                for (key, style_key) in [
                    ("sys_cpu", "cpu"),
                    ("sys_ram", "ram"),
                    ("sys_battery", "battery"),
                ] {
                    let value = string(values, key);
                    if !value.is_empty() {
                        text = text.replace(
                            &value,
                            &format!("\x1b[0;{}m{value}\x1b[0;{color}m", string(style, style_key)),
                        );
                    }
                }
            }
            write!(output, "\x1b[{color}m{text}\x1b[0m")?;
            if !buttons.is_empty() {
                let x = hits.first().map(|hit| hit.start).unwrap_or(0);
                execute!(output, cursor::MoveTo(x, y))?;
                write!(output, "{buttons}")?;
                action_hits.extend(hits);
            }
        }
    }
    output.flush()?;
    Ok(action_hits)
}

fn view(args: &[String]) -> Result<()> {
    use crossterm::event::{DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEventKind, MouseButton, MouseEventKind};
    use crossterm::{cursor, event, execute, terminal};
    let style: Value = serde_json::from_str(include_str!("../view.json"))?;
    let mut actions = actions::Actions::new(&style["actions"])?;
    let options = view_options(args)?;
    let own_pane = view_pane();
    let scope_file = own_pane.as_deref().and_then(|pane| scope_path(pane).ok());
    let mut scope = options.as_ref().and_then(|(parent, url)|
        own_pane.as_deref().and_then(|pane| subagent_scope(parent, pane, url).ok()));
    let mut opted_in = options.is_some();
    let mut notification_offset = 0;
    let mut task_open = false;
    let mut task_offset = 0;
    let mut show_subagents = false;
    struct Screen;
    impl Drop for Screen {
        fn drop(&mut self) {
            let _ = terminal::disable_raw_mode();
            let _ = execute!(io::stdout(), DisableMouseCapture, cursor::Show, terminal::LeaveAlternateScreen);
        }
    }
    terminal::enable_raw_mode()?;
    let _screen = Screen;
    let mut output = io::stdout();
    execute!(output, terminal::EnterAlternateScreen, cursor::Hide, EnableMouseCapture)?;
    let cache = env::var_os("VIBE_CACHE_DIR")
        .map(PathBuf::from)
        .unwrap_or(home().join(".cache/vibe"));
    loop {
        if scope.is_none() && options.is_none() {
            if let Some(path) = &scope_file {
                if let Ok(metadata) = fs::symlink_metadata(path) {
                    opted_in = true;
                    if metadata.is_file() && metadata.uid() == fs::metadata(home())?.uid()
                        && metadata.permissions().mode() & 0o777 == 0o600 && metadata.len() <= 16384 {
                        scope = fs::read_to_string(path).ok().and_then(|raw| serde_json::from_str(&raw).ok());
                        if scope.as_ref().is_some_and(|v| v["view_pane"].as_str() != own_pane.as_deref()) {
                            scope = None;
                        }
                    }
                }
            }
        }
        let mut task = task_observation(scope.as_mut(), &style);
        if task_open && show_subagents {
            task["subagents"] = json!(if let Some(scope) = scope.as_mut() { subagent_line(scope, &style) }
                else { "서브 TUI 연결 미확인".into() });
        }
        if opted_in && scope.is_none() { task["reason"] = json!("저장된 scope/현재 TUI 검증 실패"); }
        let values = metrics();
        let notifications = dock(&cache);
        let notifications = if notifications.starts_with("알림") {
            notifications
        } else {
            format!("알림 {notifications}")
        };
        let date = quick("date", &["+%Y-%m-%d %H:%M:%S"]).unwrap_or("시각 미확인".into());
        let notices = if actions.message.is_empty() { notifications.clone() }
            else { format!("{} · {notifications}", actions.message) };
        notification_offset = notification_offset.min(notices.chars().count().saturating_sub(1));
        let mut action_hits = render_view(&mut output, &values, &notices, &date, &style, &task, (&actions, notification_offset, task_open.then_some((&task, &mut task_offset))))?;
        let mut rendered_size = terminal::size()?;
        let deadline = Instant::now() + Duration::from_secs(5);
        while Instant::now() < deadline {
            if actions.poll() {
                action_hits = render_view(&mut output, &values, &format!("{} · {notifications}", actions.message), &date, &style, &task, (&actions, notification_offset, task_open.then_some((&task, &mut task_offset))))?;
                rendered_size = terminal::size()?;
            }
            let wait = deadline.saturating_duration_since(Instant::now());
            if event::poll(if actions.busy() { wait.min(Duration::from_millis(100)) } else { wait })? {
                match event::read()? {
                    Event::Key(key) if key.kind == KeyEventKind::Press && key.code == KeyCode::Esc && task_open => {
                        task_open = false;
                    }
                    Event::Key(key) if key.kind == KeyEventKind::Press && key.code == KeyCode::Char('t') => {
                        task_open = !task_open; task_offset = 0; actions.close();
                    }
                    Event::Key(key) if key.kind == KeyEventKind::Press && task_open && key.code == KeyCode::Char('s') => {
                        show_subagents = !show_subagents;
                        task["subagents"] = json!(if show_subagents {
                            if let Some(scope) = scope.as_mut() { subagent_line(scope, &style) } else { "서브 TUI 연결 미확인".into() }
                        } else { "표시 안 함".into() });
                    }
                    Event::Key(key) if key.kind == KeyEventKind::Press && task_open && matches!(key.code, KeyCode::Up | KeyCode::Down) => {
                        task_offset = if key.code == KeyCode::Up { task_offset.saturating_sub(1) } else { task_offset.saturating_add(1) };
                    }
                    Event::Key(key) if key.kind == KeyEventKind::Press && key.code == KeyCode::Esc && actions.open => {
                        actions.close();
                    }
                    Event::Key(key)
                        if key.kind == KeyEventKind::Press
                            && matches!(key.code, KeyCode::Char('q' | 'Q') | KeyCode::Esc) =>
                    {
                        if scope.is_some() && options.is_none() {
                            if let Some(path) = &scope_file {
                                let _ = fs::remove_file(path);
                                let _ = fs::remove_file(path.with_extension("observation.json"));
                            }
                        }
                        return Ok(())
                    }
                    Event::Resize(_, _) => {
                        // Redraw before accepting any click at the new terminal size.
                    }
                    Event::Key(key) if key.kind == KeyEventKind::Press && key.code == KeyCode::Char('a') => { task_open = false; actions.toggle(); },
                    Event::Key(_) if task_open => (),
                    Event::Key(key) if key.kind == KeyEventKind::Press && matches!(key.code, KeyCode::Tab | KeyCode::BackTab) =>
                        actions.select(key.code == KeyCode::Tab),
                    Event::Key(key) if key.kind == KeyEventKind::Press && actions.open && matches!(key.code, KeyCode::Left | KeyCode::Right) =>
                        actions.select(key.code == KeyCode::Right),
                    Event::Key(key) if key.kind == KeyEventKind::Press && key.code == KeyCode::Enter => {
                        if let Some(index) = actions.selected().filter(|index| action_hits.iter().any(|hit| hit.action == Some(*index))) {
                            actions.submit(index, scope.as_ref());
                        }
                    }
                    Event::Mouse(mouse) if mouse.kind == MouseEventKind::Down(MouseButton::Left) => {
                        if terminal::size()? == rendered_size {
                            if !task_open && !actions.open && rendered_size.1 >= 7 && mouse.row == rendered_size.1 - 1
                                && usize::from(mouse.column) < unicode_width::UnicodeWidthStr::width(TASK_DETAIL_BUTTON) {
                                task_open = true; task_offset = 0;
                            } else if let Some(hit) = action_hits.iter().find(|hit| hit.row == mouse.row && mouse.column >= hit.start && mouse.column < hit.end) {
                                if let Some(index) = hit.action { actions.submit(index, scope.as_ref()); }
                                else { actions.toggle(); }
                            }
                        }
                    }
                    Event::Key(key) if key.kind == KeyEventKind::Press
                        && matches!(key.code, KeyCode::Left | KeyCode::Right | KeyCode::Home) => {
                        let notification_length = notifications.chars().count()
                            + if actions.message.is_empty() { 0 } else { actions.message.chars().count() + 3 };
                        notification_offset = match key.code {
                            KeyCode::Left => notification_offset.saturating_sub(1),
                            KeyCode::Right => (notification_offset + 1).min(notification_length.saturating_sub(1)),
                            _ => 0,
                        };
                    }
                    _ => (),
                }
                let notifications = if actions.message.is_empty() { notifications.clone() }
                    else { format!("{} · {notifications}", actions.message) };
                action_hits = render_view(&mut output, &values, &notifications, &date, &style, &task, (&actions, notification_offset, task_open.then_some((&task, &mut task_offset))))?;
                rendered_size = terminal::size()?;
            }
        }
    }
}

fn main() {
    let args = env::args().skip(1).collect::<Vec<_>>();
    let result = match args.first().map(String::as_str) {
        Some("status") => {
            status(args.iter().any(|s| s == "--sidebar-only"));
            Ok(())
        }
        Some("notify") if args.len() == 1 => notify(None),
        Some("notify") if args.len() == 3 && args[1] == "--test" => notify(Some(&args[2])),
        Some("usage") => usage(),
        Some("view") => view(&args[1..]),
        Some("bar") => bar::entry(&args[1..]),
        _ => Err(
            "usage: vibe-herdr status [--sidebar-only] | notify [--test done|blocked] | usage | view"
                .into(),
        ),
    };
    if let Err(error) = result {
        eprintln!("vibe-herdr: {error}");
        std::process::exit(1);
    }
}
