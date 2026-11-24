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
use std::sync::mpsc::{self, Receiver, TryRecvError};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use unicode_width::{UnicodeWidthChar, UnicodeWidthStr};

type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
mod bar;
mod dock;
mod actions;
mod slack_mentions;
mod ace_inbox;
mod completion_alert;

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

fn hud_adapter() -> PathBuf {
    if let Some(path) = env::var_os("VIBE_HERDR_HUD_ADAPTER") {
        return PathBuf::from(path);
    }
    if let Ok(executable) = env::current_exe().and_then(fs::canonicalize) {
        let bundled = executable.with_file_name("hud.py");
        if bundled.is_file() {
            return bundled;
        }
    }
    home().join(".config/herdr/hud.py")
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
            while unicode_width::UnicodeWidthStr::width(result.as_str()) >= width {
                if result.pop().is_none() { break; }
            }
            if width > 0 { result.push('…'); }
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
    rpc_on_socket(Path::new(&env::var("HERDR_SOCKET_PATH")?), method, params, timeout)
}

fn rpc_on_socket(socket: &Path, method: &str, params: Value, timeout: Duration) -> Result<Value> {
    let mut client = UnixStream::connect(socket)?;
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
    let mut result = rpc("pane.list", json!({}))?;
    let home = home().to_string_lossy().into_owned();
    for pane in result["panes"].as_array_mut().ok_or("missing panes")? {
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
            let git = quick("git", &["-C", cwd, "rev-parse", "--path-format=absolute", "--git-common-dir", "--abbrev-ref", "HEAD"]).unwrap_or_default();
            let (common, branch) = git.split_once('\n').unwrap_or(("", ""));
            let branch = if branch == "HEAD" { "" } else { branch };
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
            let title = format!(
                "{path} | {} | {} | {}",
                if branch.is_empty() { "-" } else { branch },
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
            );
            if let Some(root) = Path::new(common).parent().filter(|_| Path::new(common).file_name().is_some_and(|name| name == ".git")) {
                pane["project_root"] = json!(root);
            }
            title
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
    let (Some(panes), Some(generation)) = (panes.and_then(|result| result["panes"].as_array()), generation) else { return; };
    let agents: Vec<_> = panes.iter().filter(|pane| pane["agent"].as_str().is_some_and(|agent| !agent.is_empty()))
        .map(|pane| json!({"pane_id":pane["pane_id"], "workspace_id":pane["workspace_id"],
            "terminal_id":pane["terminal_id"], "agent":pane["agent"], "agent_session":pane["agent_session"],
            "agent_status":pane["agent_status"], "cwd":pane["cwd"], "foreground_cwd":pane["foreground_cwd"],
            "project_root":pane["project_root"]})).collect();
    if agents.is_empty() { return; }
    // The dashboard exposes its configured storage contract as a Python API.
    // Keep its exact identity checks there; no legacy-file fallback in Rust.
    let script = hud_adapter();
    if let Some(path) = script.to_str() {
        let snapshot = json!({"generation":generation,"panes":agents}).to_string();
        let _ = run("python3", &["-B", path, "--sidebar", &snapshot], Duration::from_secs(2));
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
        if status == "done" {
            return show_alert(&completion_alert::payload(data, &context));
        }
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
    show_alert(&payload)
}

fn show_alert(payload: &Value) -> Result<()> {
    let encoded = serde_json::to_vec(payload)?
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
    let script = hud_adapter();
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
    let agent_label = |agent: &Value| {
        let role = agent["agent_name"].as_str().filter(|v| !v.is_empty())
            .or_else(|| agent["agent_type"].as_str().filter(|v| !v.is_empty())).unwrap_or("역할 미확인");
        let id = agent["agent_id"].as_str().unwrap_or("?");
        let suffix = id.chars().rev().take(id_chars).collect::<String>().chars().rev().collect::<String>();
        format!("{}#{}", plain(role, 20), suffix)
    };
    let labels = running.iter().take(limit).map(agent_label).collect::<Vec<_>>().join(" · ");
    if age < 0.0 || age > ttl {
        return if labels.is_empty() { "서브 현재 관측 오래됨".into() }
            else { format!("서브 현재 관측 오래됨 · {labels}") };
    }
    let current_provider = result["data"]["observation"]["kind"] == "codex-app-server";
    if !current_provider {
        return if running.is_empty() { "서브 현재 관측 없음".into() }
            else { format!("서브 과거 실행 관측 {} · {labels}", running.len()) };
    }
    let Some(recent) = result["data"]["recent"].as_array() else { return "서브 조회 실패".into(); };
    let recent_status = |agent: &Value| match agent["state"].as_str() {
        Some("idle") => "유휴",
        Some("notLoaded") => "미적재",
        Some("systemError") => "오류",
        _ => "상태 미확인",
    };
    let mut summary = if running.is_empty() { "서브 실행 0".to_owned() }
        else { format!("서브 실행 관측 {}", running.len()) };
    let recent_count = result["data"]["counts"]["recent"].as_u64().unwrap_or(0).max(recent.len() as u64);
    let limited = recent_count > recent.len() as u64;
    for label in ["유휴", "미적재", "오류", "상태 미확인"] {
        let count = recent.iter().filter(|agent| recent_status(agent) == label).count();
        if count > 0 { summary.push_str(&format!(" · {label}{}{count}", if limited { "≥" } else { " " })); }
    }
    if !labels.is_empty() { summary.push_str(&format!(" · {labels}")); }
    for agent in recent.iter().take(limit.saturating_sub(running.len())) {
        summary.push_str(&format!(" · {} {}", recent_status(agent), agent_label(agent)));
    }
    let hidden = (running.len() as u64 + recent_count).saturating_sub(limit as u64);
    if hidden > 0 { summary.push_str(&format!(" · +{hidden}")); }
    summary
}

fn task_observation(scope: Option<&mut Value>, style: &Value) -> Value {
    let Some(scope) = scope else { return json!({"state":"unconnected","reason":"공식 부모 연결 미확인"}); };
    if scope["view_pid"].as_u64() != Some(u64::from(std::process::id())) {
        return json!({"state":"unconnected","reason":"현재 TUI scope 아님"});
    }
    scope["queue_timeout_seconds"] = style["task"]["queue_timeout_seconds"].clone();
    let script = hud_adapter();
    let python = home().join(string(&style["subagents"], "python_relative_path"));
    let result = (|| -> Result<Value> {
        let raw = run(python.to_str().ok_or("invalid adapter Python path")?,
            &["-B", script.to_str().ok_or("invalid adapter path")?, "--current-task", &scope.to_string()],
            Duration::from_secs(style["task"]["adapter_timeout_seconds"].as_u64().unwrap_or(6)))?;
        Ok(serde_json::from_str(&raw)?)
    })();
    let mut result = result.unwrap_or_else(|_| json!({"state":"failed"}));
    result["view"] = json!("queue");
    if !result["binding"].is_null() && scope["binding"].is_null() {
        scope["binding"] = result["binding"].clone();
    }
    result
}

const QUEUE_REFRESH_INTERVAL: Duration = Duration::from_secs(1);

struct QueueRefresh {
    pending: Option<Receiver<Value>>,
    next: Instant,
    default_definition: Value,
}

impl QueueRefresh {
    fn new() -> Self {
        Self { pending: None, next: Instant::now(), default_definition: Value::Null }
    }

    fn poll(&mut self, scope: Option<&mut Value>, style: &Value, task: &mut Value) -> bool {
        let Some(scope) = scope else { return false };
        let received = self.pending.as_ref().map(Receiver::try_recv);
        let mut changed = false;
        match received {
            Some(Ok(snapshot)) => {
                self.pending = None;
                if matches!(snapshot["state"].as_str(), Some("observed" | "transient_failure"))
                    && snapshot["read_only"] != true
                    && !scope["binding"].is_null() && snapshot["binding"] != scope["binding"]
                {
                    *task = json!({"state":"unconnected","reason":"큐 조회 중 부모 연결 변경"});
                    self.default_definition = Value::Null;
                } else if snapshot["state"] == "transient_failure" && task["state"] == "observed"
                    && !snapshot["binding"].is_null() && snapshot["binding"] == task["binding"]
                    && snapshot["binding"] == scope["binding"]
                {
                    changed = task["stale"] != true;
                    task["stale"] = json!(true);
                    return changed;
                } else {
                    if snapshot["state"] == "observed" {
                        if snapshot["read_only"] != true {
                            scope["binding"] = snapshot["binding"].clone();
                        }
                        self.default_definition = snapshot["queue_default_definition"].clone();
                    } else {
                        self.default_definition = Value::Null;
                    }
                    *task = snapshot;
                }
                changed = true;
            }
            Some(Err(TryRecvError::Disconnected)) => {
                self.pending = None;
                self.default_definition = Value::Null;
                *task = json!({"state":"failed"});
                changed = true;
            }
            _ => {}
        }
        if self.pending.is_none() && Instant::now() >= self.next {
            let (send, receive) = mpsc::channel();
            let mut scope = scope.clone();
            scope["queue_default_definition"] = self.default_definition.clone();
            let style = style.clone();
            self.pending = Some(receive);
            self.next = Instant::now() + QUEUE_REFRESH_INTERVAL;
            thread::spawn(move || {
                let _ = send.send(task_observation(Some(&mut scope), &style));
            });
        }
        changed
    }
}

fn refresh_selection(task: &Value, top: bool, selected: &mut Option<i64>) -> bool {
    if task["state"] != "observed" { return selected.take().is_some(); }
    let Some(records) = task["records"].as_array() else { return false; };
    let missing = !records.iter().any(|row| row["id"].as_i64() == *selected);
    if top || missing {
        *selected = records.first().and_then(|row| row["id"].as_i64());
    }
    missing
}

fn hide_confirmed(task: &mut Value, confirmed: &[(i64, String)]) {
    let Some(records) = task["records"].as_array_mut() else { return; };
    let count = records.len();
    records.retain(|row| !confirmed.iter().any(|(id, token)|
        row["id"].as_i64() == Some(*id) && row["completion_token"].as_str() == Some(token)));
    if count != records.len() {
        let total = records.len();
        let pending = records.iter().filter(|row| row["needs_review"] == true).count();
        task["total"] = json!(total);
        task["review_count"] = json!(pending);
    }
}

fn task_line(task: &Value, style: &Value) -> String {
    match task["state"].as_str() {
        Some("parent_unbound") => return "작업 thread 부모 미연결 · t 상세".into(),
        Some("unconnected") => return "작업 thread 연결 불일치/미확인 · t 상세".into(),
        Some("observed") => {},
        _ => return "작업 thread 조회 실패 · 현재 상태 미확인 · t 상세".into(),
    }
    let thread = if task["read_only"] == true { "공개 큐 조회 전용".into() }
        else { task["thread"].as_str().unwrap_or("?").chars().take(8).collect::<String>() };
    let at = task["observed_at"].as_str().unwrap_or("미확인");
    let at = at.get(11..19).unwrap_or(at);
    if task["stale"] == true {
        return format!("큐 갱신 실패 · 마지막 조회 {at} · t 상세");
    }
    let Some(record) = task["records"].as_array().and_then(|records| records.first()) else {
        let count = task["requests"].as_array().map_or(0, Vec::len);
        return format!("작업 thread {thread} · 요청 {count} · 선택/진척 미확인 · 확인 {at} · t 상세");
    };
    let stage = record["stage"].as_str().map(stage_label).unwrap_or("세부단계 미기록");
    let freshness = match record["updated_age"].as_f64() {
        Some(age) if age < 0.0 || age > style["task"]["stale_seconds"].as_f64().unwrap_or(60.0) => " · 기록 오래됨",
        None => " · 기록 갱신시각 미확인",
        _ => "",
    };
    format!("작업 {thread}/#{} · 확인 {at} · {stage} · {}{freshness} · {} · t 상세",
        record["id"], string(record, "state"), plain(&string(record, "goal"), 40))
}

const TASK_DETAIL_BUTTON: &str = "[t 작업 상세]";

fn stage_label(id: &str) -> &str {
    match id {
        "intake" => "접수", "requirements" => "요구", "plan" => "계획", "test_design" => "테스트",
        "implement" => "실행", "verify" => "검증", "report" => "보고", "publish" => "저장·배포",
        "local_verify" => "로컬 검증", "deploy_prepare" => "배포 준비", "deploy" => "배포",
        "request_review" => "운영 확인 요청", "requester_confirm" => "요청자 확인", _ => id,
    }
}

fn stage_diagram(record: &Value, compact: bool) -> String {
    if record["queue_status"] == "done" && matches!(record["stage_definition"].as_str(), Some("default" | "undefined")) && record["stage"].is_null()
        && record["stages"].as_array().is_none_or(Vec::is_empty) {
        return "작업 완료 · 과거 단계 기록 없음".into();
    }
    if record["queue_status"] == "queued" && record["stage_definition"] == "undefined" {
        return "착수 전 · 단계 기록 없음".into();
    }
    if record["stage_definition"] != "observed" && record["stage_definition"] != "default" {
        return if record["stage_definition"] == "mismatch" { "단계 정의/실행 판본 미확인" } else { "단계 미정의" }.into();
    }
    let diagram = record["stages"].as_array().into_iter().flatten().map(|stage| {
        let id = string(stage, "id");
        let label = stage_label(&id);
        let (mark, state) = match stage["state"].as_str() {
            Some("completed") => ("✓", "완료"), Some("current") => ("●", "진행"),
            Some("recorded") => ("◇", "현재 단계"),
            Some("blocked") => ("Ⅱ", "대기"), Some("failed") => ("!", "실패"),
            Some("not_applicable") => ("—", "해당 없음"),
            Some("waiting") => ("○", "예정"), _ => ("?", "미확인"),
        };
        if compact { format!("[{mark} {label}]") } else { format!("[{mark} {label} {state}]") }
    }).collect::<Vec<_>>().join(" → ");
    if !compact && record["stage_definition"] == "default" {
        format!("공통 기준 · 실제 단계 기록 없음 · {diagram}")
    } else { diagram }
}

fn list_stage_diagram(record: &Value, width: usize) -> String {
    let diagram = stage_diagram(record, true);
    if diagram.width() <= width || record["stage_definition"] != "observed" {
        return diagram;
    }
    let Some(stage) = record["stage"].as_str() else { return diagram; };
    let active = record["stages"].as_array().into_iter().flatten()
        .find(|entry| entry["id"] == stage);
    let state = match active.and_then(|entry| entry["state"].as_str()) {
        Some("completed") => "✓",
        Some("current") => "●",
        Some("recorded") => "◇",
        Some("blocked") => "Ⅱ",
        Some("failed") => "!",
        Some("not_applicable") => "—",
        _ => "?",
    };
    format!("[{state} {}] · {diagram}", stage_label(stage))
}

fn task_page(task: &Value, selected: Option<i64>, body_height: u16) -> usize {
    let position = task["records"].as_array().and_then(|records| records.iter().position(|r| r["id"].as_i64() == selected)).unwrap_or(0);
    let page_size = usize::from(body_height.saturating_sub(2)).max(1);
    position / page_size * page_size
}

#[cfg(test)]
mod queue_display_tests {
    use super::*;

    #[test]
    fn deployment_confirmation_stays_visible_in_narrow_queue() {
        let record = json!({"stage_definition":"observed","stage":"requester_confirm","stages":[
            {"id":"local_verify","state":"completed"},
            {"id":"deploy_prepare","state":"completed"},
            {"id":"deploy","state":"completed"},
            {"id":"request_review","state":"completed"},
            {"id":"requester_confirm","state":"blocked"}
        ]});
        assert!(list_stage_diagram(&record, 18).starts_with("[Ⅱ 요청자 확인]"));
        assert!(stage_diagram(&record, false).contains("[✓ 배포 완료]"));
        assert!(stage_diagram(&record, false).contains("[Ⅱ 요청자 확인 대기]"));
    }
}

fn task_list(output: &mut [Vec<u8>], width: u16, height: u16, task: &Value, selected: Option<i64>) -> Result<()> {
    if height == 0 { return Ok(()); }
    let columns = usize::from(width);
    let title = format!("전체 작업 큐{} · 확인 대기 {} · {}건(대기 {}) · 조회 {} · {} · 연결 {} · ↑↓/jk/ㅓㅏ 선택 / Enter 상세{}",
        if task["read_only"] == true { " · 조회 전용(부모 미연결)" }
            else if task["stale"] == true { " · 갱신 실패" } else { "" },
        task["review_count"].as_u64().unwrap_or(0), task["total"], task["queued_count"],
        task["observed_at"].as_str().and_then(|at| at.get(11..19)).unwrap_or("미확인"),
        string(task, "subagent_summary"),
        task["thread"].as_str().unwrap_or("미확인").chars().take(8).collect::<String>(),
        if task["limited"] == true { " · 최근12건" } else { "" });
    write!(output[0], "\x1b[1;36m{}\x1b[0m", plain(&title, columns))?;
    if task["state"] != "observed" || task["records"].as_array().is_none_or(Vec::is_empty) {
        let empty = if task["state"] == "observed" { "진행 중·대기·완료 확인 대기 작업 없음 · 확인된 결과는 큐 이력에 보존" }
            else { "연결/작업 기록 미확인 · t 상세에서 확인" };
        if height > 1 { write!(output[1], "{}", plain(empty, columns))?; }
        return Ok(());
    }
    let goal_width = (columns / 4).min(50);
    let diagram_width = columns.saturating_sub(goal_width + 37);
    let cell = |value: &str, size: usize| {
        let text = plain(value, size);
        format!("{text}{}", " ".repeat(size.saturating_sub(unicode_width::UnicodeWidthStr::width(text.as_str()))))
    };
    let row = |id: &str, goal: &str, status: &str, diagram: &str| {
        let status_color = match status {
            "검증완료·확인대기" | "완료·확인됨" => "92",
            "실패 기록" | "수정 요청" => "91",
            "실행 기록" | "검증 중" | "검증 완료" | "단계 결과 있음" => "96",
            "단계 진행" | "단계 기록" => "94",
            "대기 기록" | "외부 대기" | "의존 대기" | "Question 대기" | "요청자 확인 대기" => "93",
            "검토 보류" => "95",
            _ => "39",
        };
        if columns < 64 {
            let prefix = plain(&format!("{id} "), columns);
            let remaining = columns.saturating_sub(prefix.width());
            let state = plain(status, remaining);
            let rest = plain(&format!(" · {diagram} · {goal}"), remaining.saturating_sub(state.width()));
            return format!("{prefix}\x1b[{status_color}m{state}\x1b[39m{rest}");
        }
        let diagram = cell(diagram, diagram_width)
            .replace("[✓", "\x1b[32m[✓").replace("[●", "\x1b[36m[●").replace("[◇", "\x1b[94m[◇")
            .replace("[○", "\x1b[90m[○").replace("[Ⅱ", "\x1b[33m[Ⅱ")
            .replace("[!", "\x1b[31m[!").replace("[?", "\x1b[90m[?").replace("[—", "\x1b[90m[—")
            .replace(']', "]\x1b[39m");
        format!("│ {} │ {} │ \x1b[{status_color}m{}\x1b[39m │ \x1b[90m{diagram}\x1b[39m │", cell(id, 5), cell(goal, goal_width), cell(status, 19))
    };
    if height > 1 { write!(output[1], "{}", row("요청", "작업 목표", "큐 상태", "단계 흐름"))?; }
    let first = task_page(task, selected, height);
    for (index, record) in task["records"].as_array().into_iter().flatten().skip(first).take(usize::from(height.saturating_sub(2))).enumerate() {
        let output = &mut output[index + 2];
        let status = match record["queue_status"].as_str() {
            Some("done") if record["completion_confirmed"] == true => "완료·확인됨",
            Some("done") if record["review_decision"] == "deferred" => "검토 보류",
            Some("done") if record["review_decision"] == "changes_requested" => "수정 요청",
            Some("done") if record["verify_complete"] == true && record["needs_review"] != true => "완료·검증됨",
            Some("done") if record["needs_review"] != true => "완료·검증 미확인",
            Some("failed") => "실패 기록",
            Some("queued") if record["state"] == "큐 대기" => "대기 기록",
            Some("running" | "queued" | "done") => record["state"].as_str().unwrap_or("미확인"),
            _ => "미확인" };
        let detail = list_stage_diagram(record, if columns < 64 { 0 } else { diagram_width });
        if record["id"].as_i64() == selected { write!(output, "\x1b[7m")?; }
        write!(output, "{}\x1b[0m", row(&format!("#{}", record["id"]), &string(record, "goal"), status, &detail))?;
    }
    Ok(())
}

const COMPLETION_BUTTON: &str = "[c 완료 확인·목록에서 치우기]";

fn completed_selection(task: &Value, selected: Option<i64>) -> Option<&Value> {
    if task["state"] != "observed" || task["stale"] == true || task["read_only"] == true
        || task["binding"].is_null() || task["thread"].as_str().is_none_or(str::is_empty) { return None; }
    task["records"].as_array()?.iter().find(|record| record["id"].as_i64() == selected
        && record["owner_tool"] == "codex" && record["owner_thread"] == task["thread"]
        && record["queue_status"] == "done" && record["completion_confirmed"] != true
        && record["completion_token"].as_str().is_some_and(|v| !v.is_empty()))
}

fn selection_owned(task: &Value, selected: Option<i64>) -> bool {
    if task["stale"] == true || task["read_only"] == true || task["binding"].is_null()
        || task["thread"].as_str().is_none_or(str::is_empty) { return false; }
    task["state"] == "observed" && task["records"].as_array().is_some_and(|records|
        records.iter().any(|record| record["id"].as_i64() == selected
            && record["owner_tool"] == "codex" && record["owner_thread"] == task["thread"]))
}

fn task_overlay(output: &mut [Vec<u8>], width: u16, height: u16, task: &Value, offset: &mut usize, selected: Option<i64>) -> Result<()> {
    let expanded = task["expanded"] == true || task["state"] != "observed";
    let mut lines = Vec::new();
    let mut connection_lines = vec![format!("스레드: {}", string(task, "thread")),
        format!("관측: {} · 확인 {} · {} {}", string(task, "state"), string(task, "observed_at"), string(task, "phase"), string(task, "error_type")),
        format!("연결: {}", task["reason"].as_str().unwrap_or(if task["state"] == "observed" {
            "공식 부모 thread/PID/cwd 검증 · public vibe queue" } else { "검증/조회 미완료" })),
        "에이전트·thread·pane은 별개 · 실행/접수/열람은 완료·승인 근거 아님".into()];
    if task["stale"] == true {
        lines.push(format!("갱신 실패 · 마지막 조회 {}", string(task, "observed_at")));
    }
    if task["state"] != "observed" {
        connection_lines.push(format!("연결 확인 후 Codex 패널에서 실행: {} bar ensure --current --parent-current --relaunch",
            home().join(".config/herdr/vibe-herdr").display()));
    }
    for record in task["records"].as_array().into_iter().flatten().filter(|record| record["id"].as_i64() == selected) {
        lines.extend([format!("요청 #{} 목표: {}", record["id"], string(record, "goal")),
            format!("요청 배정: {} / {}", record["owner_tool"].as_str().unwrap_or("미배정"), record["owner_thread"].as_str().unwrap_or("미배정")),
            format!("단계 흐름: {}", stage_diagram(record, false)),
            format!("현재 단계: {} · 큐 상태: {} · 저장 상태: {}", record["stage"].as_str().map(stage_label).unwrap_or("세부단계 미기록"), string(record, "state"), string(record, "queue_status")),
            format!("대기 사유: {}", record["wait"].as_str().filter(|v| !v.is_empty()).unwrap_or("미기록")),
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
    lines.extend(connection_lines);
    if task["limited"] == true { lines.push("연결 요청 목록 일부만 표시".into()); }
    if let Some(subagents) = task["subagents"].as_str() { lines.push(format!("별도 서브 실행 관측: {subagents}")); }
    if !expanded {
        if let Some(record) = task["records"].as_array().into_iter().flatten().find(|record| record["id"].as_i64() == selected) {
            let result = record["result"].as_str().filter(|v| !v.is_empty()).unwrap_or("기록된 결과 없음 · v로 근거 확인");
            let brief = result.split_once(". ").map(|(sentence, _)| format!("{sentence}. · v 전체 근거"))
                .unwrap_or_else(|| result.to_owned());
            let next = if record["review_decision"] == "deferred" { "문서 검토 보류 · 검토 후 대화에서 확인/수정 요청" }
                else if record["review_decision"] == "changes_requested" { "수정 요청 보완 후 다시 결과 확인" }
                else if record["queue_status"] == "done" { "결과 확인 후 대화 또는 c로 완료 확인" }
                else { record["next_action"].as_str().filter(|v| !v.is_empty()).unwrap_or("미기록") };
            lines = vec![format!("#{} · 큐 상태 {} · {}{}", record["id"], string(record, "state"), string(record, "goal"),
                    if task["stale"] == true { " · 갱신 실패" } else { "" }),
                format!("결과: {brief}"),
                format!("배정: {} / {} · {} · 다음: {next}", record["owner_tool"].as_str().unwrap_or("미배정"),
                    record["owner_thread"].as_str().unwrap_or("미배정"),
                    if selection_owned(task, selected) { "연결 대화 일치" } else { "조회 전용" })];
            if record["waiting"] == true {
                lines.insert(1, format!("대기 사유: {} · v 전체 근거", record["wait"].as_str().filter(|v| !v.is_empty()).unwrap_or("미기록")));
            }
        }
    }
    let columns = usize::from(width).max(1);
    let mut wrapped = Vec::new();
    for line in lines {
        if !expanded { wrapped.push(plain(&line, columns.saturating_sub(1))); continue; }
        for line in line.lines() {
            let mut row = String::new();
            let mut used = 0;
            for c in line.chars().filter(|c| !c.is_control()) {
                let size = c.width().unwrap_or(0);
                if used + size > columns && !row.is_empty() { wrapped.push(row); row = String::new(); used = 0; }
                row.push(c); used += size;
            }
            wrapped.push(row);
        }
    }
    let visible = usize::from(height.saturating_sub(1));
    *offset = (*offset).min(wrapped.len().saturating_sub(visible));
    for (index, line) in wrapped.iter().skip(*offset).take(visible).enumerate() {
        write!(output[index], "{}", plain(line, columns))?;
    }
    if height > 0 {
        let output = &mut output[usize::from(height - 1)];
        if completed_selection(task, selected).is_some() {
            write!(output, "\x1b[32m{}\x1b[0m", plain(&format!("{COMPLETION_BUTTON} · v {} · ↑↓/jk/ㅓㅏ 스크롤 · t/Esc 복귀", if expanded { "요약" } else { "전체 근거" }), columns))?;
        } else {
            write!(output, "{}", plain(&format!("작업 상세 · v {} · ↑↓/jk/ㅓㅏ 스크롤 · s 서브관측 · t/Esc 복귀", if expanded { "요약" } else { "전체 근거" }), columns))?;
        }
    }
    Ok(())
}

#[derive(Default)]
struct ViewFrame {
    width: u16,
    rows: Vec<Vec<u8>>,
}

impl ViewFrame {
    fn paint(&mut self, output: &mut impl Write, width: u16, rows: Vec<Vec<u8>>) -> Result<()> {
        use crossterm::{cursor, queue, terminal};
        let resized = self.width != width || self.rows.len() != rows.len();
        let mut update = Vec::new();
        queue!(update, terminal::BeginSynchronizedUpdate)?;
        let prefix_len = update.len();
        for (line, row) in rows.iter().enumerate() {
            if resized || self.rows.get(line) != Some(row) {
                queue!(update, cursor::MoveTo(0, line as u16), terminal::Clear(terminal::ClearType::CurrentLine))?;
                update.extend_from_slice(row);
            }
        }
        if update.len() > prefix_len {
            queue!(update, terminal::EndSynchronizedUpdate)?;
            output.write_all(&update)?;
            output.flush()?;
        }
        self.width = width;
        self.rows = rows;
        Ok(())
    }
}

#[cfg(test)]
mod frame_tests {
    use super::*;

    #[test]
    fn refresh_only_paints_changed_rows_and_clears_removed_text() -> Result<()> {
        let mut screen = ViewFrame::default();
        let mut output = Vec::new();
        let first = [b"queue".to_vec(), b"task row".to_vec(), b"buttons".to_vec()];
        screen.paint(&mut output, 40, first.to_vec())?;
        assert_eq!(output.windows(4).filter(|bytes| *bytes == b"\x1b[2K").count(), 3);
        assert!(!output.windows(4).any(|bytes| bytes == b"\x1b[2J"));

        output.clear();
        screen.paint(&mut output, 40, first.to_vec())?;
        assert!(output.is_empty());

        let mut refreshed = first;
        refreshed[1].clear();
        screen.paint(&mut output, 40, refreshed.to_vec())?;
        assert_eq!(output, b"\x1b[?2026h\x1b[2;1H\x1b[2K\x1b[?2026l");

        output.clear();
        screen.paint(&mut output, 29, refreshed.to_vec())?;
        assert_eq!(output.windows(4).filter(|bytes| *bytes == b"\x1b[2K").count(), 3);
        Ok(())
    }
}

fn render_view(
    output: &mut impl Write,
    frame: &mut ViewFrame,
    values: &Value,
    notifications: &str,
    date: &str,
    style: &Value,
    task: &Value,
    interaction: (&actions::Actions, usize, Option<(&Value, &mut usize)>, Option<i64>),
) -> Result<Vec<actions::Hit>> {
    use crossterm::{cursor, queue, terminal};
    let (actions, notification_offset, task_detail, selected) = interaction;
    let (width, height) = terminal::size()?;
    let mut rows = vec![Vec::new(); usize::from(height)];
    let summary = task_line(task, style);
    let subagents = task["subagent_summary"].as_str().unwrap_or(summary.as_str());
    let mut action_hits = Vec::new();
    if height >= 3 {
        let columns = usize::from(width);
        let body_height = height - 2;
        if let Some((task, offset)) = task_detail {
            task_overlay(&mut rows, width, body_height, task, offset, selected)?;
        } else if actions.open {
            action_hits.extend(actions.overlay(&mut rows, width, body_height)?);
        } else {
            task_list(&mut rows, width, body_height, task, selected)?;
        }
        let system = format!("{} {} {} · {date}", string(values, "sys_cpu"), string(values, "sys_ram"), string(values, "sys_battery"));
        let system_width = unicode_width::UnicodeWidthStr::width(system.as_str());
        let notice_width = columns.saturating_sub(system_width + 3);
        let output = &mut rows[usize::from(height - 2)];
        if notice_width >= 20 {
            write!(output, "\x1b[{}m{}\x1b[0m", string(style, "notifications"), plain(notifications, notice_width))?;
            queue!(output, cursor::MoveToColumn((columns - system_width) as u16))?;
            let mut system = plain(&system, system_width);
            for (key, style_key) in [("sys_cpu", "cpu"), ("sys_ram", "ram"), ("sys_battery", "battery")] {
                let value = string(values, key);
                if !value.is_empty() { system = system.replace(&value, &format!("\x1b[{}m{value}\x1b[0m", string(style, style_key))); }
            }
            write!(output, "{system}")?;
        } else { write!(output, "\x1b[{}m{}\x1b[0m", string(style, "notifications"), plain(notifications, columns))?; }
        let row = height - 1;
        let output = &mut rows[usize::from(row)];
        write!(output, "\x1b[36m{}\x1b[0m", plain(TASK_DETAIL_BUTTON, columns))?;
        let action_start = (unicode_width::UnicodeWidthStr::width(TASK_DETAIL_BUTTON) + 1) as u16;
        let (_, buttons, hits) = actions.bar(width, row, Some(action_start));
        if !buttons.is_empty() {
            queue!(output, cursor::MoveToColumn(hits.first().map(|hit| hit.start).unwrap_or(0)))?;
            write!(output, "{buttons}")?;
            action_hits.extend(hits);
        }
    } else if let Some((task, offset)) = task_detail {
        task_overlay(&mut rows, width, height, task, offset, selected)?;
    } else if actions.open {
        action_hits.extend(actions.overlay(&mut rows, width, height)?);
    } else {
        let width = usize::from(width).saturating_sub(2);
        let mut compact_rows = style["compact"]["rows"]
            .as_array()
            .ok_or("missing compact rows")?.clone();
        if usize::from(height) > compact_rows.len() {
            let before = style["subagents"]["before"].as_str().unwrap_or("notifications");
            let position = compact_rows.iter().position(|row| row.as_str() == Some(before)).unwrap_or(0);
            compact_rows.insert(position, json!("subagents"));
        }
        let visible = compact_rows.len().min(usize::from(height));
        for (index, row) in compact_rows.iter().skip(compact_rows.len() - visible).enumerate() {
            let y = if style["compact"]["align"] == "bottom" {
                height - visible as u16 + index as u16
            } else if style["compact"]["align"] == "edges" && index + 1 == visible {
                height - 1
            } else {
                index as u16
            };
            let (notification_width, buttons, hits) = if row == "notifications" {
                actions.bar(width as u16, y, None)
            } else { (width as u16, String::new(), Vec::new()) };
            let (text, color) = match row.as_str() {
                Some("subagents") => (subagents.to_owned(), string(&style["subagents"], "color")),
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
            let output = &mut rows[usize::from(y)];
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
                queue!(output, cursor::MoveToColumn(x))?;
                write!(output, "{buttons}")?;
                action_hits.extend(hits);
            }
        }
    }
    frame.paint(output, width, rows)?;
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
    let mut detail_expanded = false;
    let mut task_offset = 0;
    let mut selected_task = None;
    let mut follow_queue_top = true;
    let mut queue = QueueRefresh::new();
    let mut task = json!({"state":"unconnected","reason":"공식 부모 연결 미확인"});
    let mut confirmed = Vec::<(i64, String)>::new();
    let mut subagent_pending: Option<Receiver<String>> = None;
    let mut subagents = "서브 TUI 연결 미확인".to_owned();
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
    let mut frame = ViewFrame::default();
    execute!(output, terminal::EnterAlternateScreen, cursor::Hide, EnableMouseCapture)?;
    let cache = env::var_os("VIBE_CACHE_DIR")
        .map(PathBuf::from)
        .unwrap_or(home().join(".cache/vibe"));
    let mut ace_inbox = ace_inbox::AceInbox::default();
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
        queue.poll(scope.as_mut(), &style, &mut task);
        hide_confirmed(&mut task, &confirmed);
        if !task_open { detail_expanded = false; }
        task["expanded"] = json!(detail_expanded);
        if refresh_selection(&task, follow_queue_top && !task_open, &mut selected_task) {
            task_open = false;
            task_offset = 0;
        }
        if let (None, Some(mut scope)) = (&subagent_pending, scope.clone()) {
            let style = style.clone();
            let (send, receive) = mpsc::channel();
            subagent_pending = Some(receive);
            thread::spawn(move || { let _ = send.send(subagent_line(&mut scope, &style)); });
        }
        task["subagent_summary"] = json!(subagents);
        if show_subagents { task["subagents"] = task["subagent_summary"].clone(); }
        if opted_in && scope.is_none() { task["reason"] = json!("저장된 scope/현재 TUI 검증 실패"); }
        let values = metrics();
        let notifications = dock(&cache);
        let notifications = match (slack_mentions::latest_notice(), ace_inbox.notice(&cache)) {
            (Some(slack), Some(ace)) => format!("{slack} · {ace} · {notifications}"),
            (Some(slack), None) => format!("{slack} · {notifications}"),
            (None, Some(ace)) => format!("{ace} · {notifications}"),
            (None, None) if !notifications.starts_with("알림") => format!("알림 {notifications}"),
            (None, None) => notifications,
        };
        let date = quick("date", &["+%Y-%m-%d %H:%M:%S"]).unwrap_or("시각 미확인".into());
        let notices = if actions.message.is_empty() { notifications.clone() }
            else { format!("{} · {notifications}", actions.message) };
        notification_offset = notification_offset.min(notices.chars().count().saturating_sub(1));
        let mut action_hits = render_view(&mut output, &mut frame, &values, &notices, &date, &style, &task, (&actions, notification_offset, task_open.then_some((&task, &mut task_offset)), selected_task))?;
        let mut rendered_size = terminal::size()?;
        let deadline = Instant::now() + Duration::from_secs(5);
        while Instant::now() < deadline {
            let updated = queue.poll(scope.as_mut(), &style, &mut task);
            let action_updated = actions.poll();
            let subagent_updated = match subagent_pending.as_ref().map(Receiver::try_recv) {
                Some(Ok(summary)) => {
                    subagents = summary;
                    subagent_pending = None;
                    true
                }
                Some(Err(TryRecvError::Disconnected)) => {
                    subagents = "서브 조회 실패".into();
                    subagent_pending = None;
                    true
                }
                _ => false,
            };
            if updated || action_updated || subagent_updated {
                if let Some((id, version)) = actions.take_confirmed_completion() {
                    confirmed.push((id, version));
                }
                hide_confirmed(&mut task, &confirmed);
                if refresh_selection(&task, follow_queue_top && !task_open, &mut selected_task) {
                    task_open = false;
                    task_offset = 0;
                    detail_expanded = false;
                }
                task["expanded"] = json!(detail_expanded);
                task["subagent_summary"] = json!(subagents);
                if show_subagents { task["subagents"] = json!(subagents); }
                let notice = if actions.message.is_empty() { notifications.clone() }
                    else { format!("{} · {notifications}", actions.message) };
                action_hits = render_view(&mut output, &mut frame, &values, &notice, &date, &style, &task, (&actions, notification_offset, task_open.then_some((&task, &mut task_offset)), selected_task))?;
                rendered_size = terminal::size()?;
            }
            let wait = deadline.saturating_duration_since(Instant::now());
            if event::poll(if scope.is_some() || actions.busy() { wait.min(Duration::from_millis(75)) } else { wait })? {
                let was_open = task_open;
                match event::read()? {
                    Event::Key(key) if key.kind == KeyEventKind::Press && key.code == KeyCode::Esc && task_open => {
                        task_open = false;
                    }
                    Event::Key(key) if key.kind == KeyEventKind::Press && key.code == KeyCode::Char('t') => {
                        task_open = !task_open; task_offset = 0; actions.close();
                    }
                    Event::Key(key) if key.kind == KeyEventKind::Press && key.code == KeyCode::Char('c') && !actions.open => {
                        if !selection_owned(&task, selected_task) { actions.message = "선택 요청은 다른 배정 대화의 조회 항목입니다 · 원담당 대화에서 확인하세요".into(); }
                        else if let Some(record) = completed_selection(&task, selected_task) {
                            if task_open { actions.confirm_completion(record, scope.as_ref()); }
                            else {
                                task_open = true; task_offset = 0;
                                actions.message = format!("#{} 완료 결과를 읽은 뒤 c 또는 완료 확인 버튼을 선택하세요 · 아직 확인하지 않음", record["id"]);
                            }
                        } else { actions.message = "선택한 작업은 완료 확인 대상이 아닙니다 · 완료·확인대기 작업을 선택하세요".into(); }
                    }
                    Event::Key(key) if key.kind == KeyEventKind::Press && task_open && key.code == KeyCode::Char('s') => {
                        detail_expanded = true; task["expanded"] = json!(true);
                        show_subagents = !show_subagents;
                        task["subagents"] = json!(if show_subagents {
                            task["subagent_summary"].as_str().unwrap_or("서브 TUI 연결 미확인")
                        } else { "표시 안 함" });
                    }
                    Event::Key(key) if key.kind == KeyEventKind::Press && task_open && key.code == KeyCode::Char('v') => {
                        detail_expanded = !detail_expanded; task["expanded"] = json!(detail_expanded); task_offset = 0;
                    }
                    Event::Key(key) if key.kind == KeyEventKind::Press && task_open && matches!(key.code, KeyCode::Up | KeyCode::Down | KeyCode::Char('j' | 'k' | 'ㅓ' | 'ㅏ')) => {
                        task_offset = if matches!(key.code, KeyCode::Up | KeyCode::Char('k' | 'ㅏ')) { task_offset.saturating_sub(1) } else { task_offset.saturating_add(1) };
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
                    Event::Key(key) if key.kind == KeyEventKind::Press && !actions.open && matches!(key.code, KeyCode::Up | KeyCode::Down | KeyCode::Char('j' | 'k' | 'ㅓ' | 'ㅏ')) => {
                        if let Some(records) = task["records"].as_array().filter(|records| !records.is_empty()) {
                            let position = records.iter().position(|record| record["id"].as_i64() == selected_task).unwrap_or(0);
                            let next = if matches!(key.code, KeyCode::Up | KeyCode::Char('k' | 'ㅏ')) { position.saturating_sub(1) } else { (position + 1).min(records.len() - 1) };
                            selected_task = records[next]["id"].as_i64();
                            follow_queue_top = next == 0;
                        }
                    }
                    Event::Key(key) if key.kind == KeyEventKind::Press && matches!(key.code, KeyCode::Tab | KeyCode::BackTab) =>
                        actions.select(key.code == KeyCode::Tab),
                    Event::Key(key) if key.kind == KeyEventKind::Press && actions.open && matches!(key.code, KeyCode::Left | KeyCode::Right) =>
                        actions.select(key.code == KeyCode::Right),
                    Event::Key(key) if key.kind == KeyEventKind::Press && key.code == KeyCode::Enter => {
                        if !actions.open {
                            task_open = true; task_offset = 0;
                        } else if let Some(index) = actions.selected().filter(|index| action_hits.iter().any(|hit| hit.action == Some(*index))) {
                            if !selection_owned(&task, selected_task) { actions.message = "선택 요청은 조회 전용 · 연결 대화와 배정이 일치할 때 요청 버튼을 사용할 수 있습니다".into(); }
                            else { actions.submit(index, scope.as_ref()); }
                        }
                    }
                    Event::Mouse(mouse) if mouse.kind == MouseEventKind::Down(MouseButton::Left) => {
                        if terminal::size()? == rendered_size {
                            if task_open && rendered_size.1 >= 3 && mouse.row == rendered_size.1 - 3
                                && usize::from(mouse.column) < unicode_width::UnicodeWidthStr::width(COMPLETION_BUTTON) {
                                if let Some(record) = completed_selection(&task, selected_task) { actions.confirm_completion(record, scope.as_ref()); }
                            } else if !task_open && !actions.open && mouse.row >= 2 && mouse.row < rendered_size.1.saturating_sub(2) {
                                let index = task_page(&task, selected_task, rendered_size.1.saturating_sub(2)) + usize::from(mouse.row - 2);
                                if let Some(record) = task["records"].as_array().and_then(|records| records.get(index)) {
                                    selected_task = record["id"].as_i64(); task_open = true; task_offset = 0;
                                }
                            } else if rendered_size.1 >= 3 && mouse.row == rendered_size.1 - 1
                                && usize::from(mouse.column) < unicode_width::UnicodeWidthStr::width(TASK_DETAIL_BUTTON) {
                                task_open = !task_open; task_offset = 0; actions.close();
                            } else if let Some(hit) = action_hits.iter().find(|hit| hit.row == mouse.row && mouse.column >= hit.start && mouse.column < hit.end) {
                                if let Some(index) = hit.action {
                                    if !selection_owned(&task, selected_task) { actions.message = "선택 요청은 조회 전용 · 연결 대화와 배정이 일치할 때 요청 버튼을 사용할 수 있습니다".into(); }
                                    else { actions.submit(index, scope.as_ref()); }
                                }
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
                if was_open && !task_open {
                    follow_queue_top = true;
                    refresh_selection(&task, true, &mut selected_task);
                }
                let notifications = if actions.message.is_empty() { notifications.clone() }
                    else { format!("{} · {notifications}", actions.message) };
                action_hits = render_view(&mut output, &mut frame, &values, &notifications, &date, &style, &task, (&actions, notification_offset, task_open.then_some((&task, &mut task_offset)), selected_task))?;
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
        Some("focus-alert") if args.len() == 2 => completion_alert::focus(&args[1]),
        Some("slack-mentions") => slack_mentions::poll(&args[1..]),
        Some("usage") => usage(),
        Some("view") => view(&args[1..]),
        Some("bar") => bar::entry(&args[1..]),
        _ => Err(
            "usage: vibe-herdr status [--sidebar-only] | notify [--test done|blocked] | slack-mentions <aside> <profile> <team> <user> <state> | usage | view"
                .into(),
        ),
    };
    if let Err(error) = result {
        eprintln!("vibe-herdr: {error}");
        std::process::exit(1);
    }
}
