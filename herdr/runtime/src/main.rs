//! Local display transport. Semantic agent state belongs to Herdr.
use regex::Regex;
use serde_json::{json, Value};
use std::env;
use std::fs::{self, File, OpenOptions};
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
    let path = cache.join("dock-badges.raw");
    let read = || -> Result<String> {
        let modified = path.metadata()?.modified()?;
        if SystemTime::now()
            .duration_since(modified)
            .unwrap_or_default()
            .as_secs()
            > 30
        {
            return Ok("알림?오래됨".into());
        }
        let mut value = String::new();
        File::open(path)?.take(4096).read_to_string(&mut value)?;
        if value.trim().is_empty() {
            return Ok("알림?".into());
        }
        Ok(plain(
            &value.trim().replace('\n', " ").replace('=', ":"),
            20,
        ))
    };
    read().unwrap_or_else(|_| "알림?".into())
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
    let mut client = UnixStream::connect(env::var("HERDR_SOCKET_PATH")?)?;
    client.set_read_timeout(Some(Duration::from_millis(300)))?;
    client.set_write_timeout(Some(Duration::from_millis(300)))?;
    writeln!(
        client,
        "{}",
        json!({"id":"vibe-display","method":method,"params":params})
    )?;
    let mut response = String::new();
    BufReader::new(client.take(1_048_576)).read_line(&mut response)?;
    let value: Value = serde_json::from_str(&response)?;
    if value.get("error").is_some() {
        return Err("Herdr rejected display request".into());
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

fn render_view(
    output: &mut impl Write,
    values: &Value,
    notifications: &str,
    date: &str,
    style: &Value,
) -> Result<()> {
    use crossterm::{cursor, execute, terminal};
    let (width, height) = terminal::size()?;
    execute!(
        output,
        cursor::MoveTo(0, 0),
        terminal::Clear(terminal::ClearType::All)
    )?;
    if height <= 8 {
        let width = usize::from(width).saturating_sub(2);
        let summary = plain(
            &format!(
                "{date} · {} {} {}",
                string(values, "sys_cpu"),
                string(values, "sys_ram"),
                string(values, "sys_battery")
            ),
            width,
        );
        if height > 0 {
            write!(output, "\x1b[{}m{summary}\x1b[0m", string(style, "heading"))?;
        }
        if height > 1 {
            write!(
                output,
                "\r\n\x1b[{}m{}\x1b[0m",
                string(style, "notifications"),
                plain(notifications, width)
            )?;
        }
        if height > 2 {
            write!(
                output,
                "\r\n\x1b[{}m{}\x1b[0m",
                string(style, "hint"),
                plain("5초 갱신 · q/Esc 닫기", width)
            )?;
        }
    } else {
        write!(output, "\x1b[{heading}m  현재 상태\x1b[0m\r\n\r\n  {date}\r\n\r\n\x1b[{notifications_style}m  {notifications}\x1b[0m\r\n\r\n\x1b[{cpu}m  {}\x1b[0m    \x1b[{ram}m{}\x1b[0m\r\n\r\n\x1b[{battery}m  {}\x1b[0m\r\n\r\n\x1b[{hint}m  실제 시스템 값 · 5초 갱신\r\n  q 또는 Esc: 닫기 · 직접 닫을 때까지 유지\x1b[0m\r\n",
            string(values,"sys_cpu"),string(values,"sys_ram"),string(values,"sys_battery"),
            heading=string(style,"heading"),notifications_style=string(style,"notifications"),
            cpu=string(style,"cpu"),ram=string(style,"ram"),battery=string(style,"battery"),hint=string(style,"hint"))?;
    }
    output.flush()?;
    Ok(())
}

fn view() -> Result<()> {
    use crossterm::event::{Event, KeyCode, KeyEventKind};
    use crossterm::{cursor, event, execute, terminal};
    let style: Value = serde_json::from_str(include_str!("../view.json"))?;
    struct Screen;
    impl Drop for Screen {
        fn drop(&mut self) {
            let _ = terminal::disable_raw_mode();
            let _ = execute!(io::stdout(), cursor::Show, terminal::LeaveAlternateScreen);
        }
    }
    terminal::enable_raw_mode()?;
    let _screen = Screen;
    let mut output = io::stdout();
    execute!(output, terminal::EnterAlternateScreen, cursor::Hide)?;
    let cache = env::var_os("VIBE_CACHE_DIR")
        .map(PathBuf::from)
        .unwrap_or(home().join(".cache/vibe"));
    loop {
        let values = metrics();
        let notifications = dock(&cache);
        let notifications = if notifications.starts_with("알림") {
            notifications
        } else {
            format!("알림 {notifications}")
        };
        let date = quick("date", &["+%Y-%m-%d %H:%M:%S"]).unwrap_or("시각 미확인".into());
        render_view(&mut output, &values, &notifications, &date, &style)?;
        let deadline = Instant::now() + Duration::from_secs(5);
        while Instant::now() < deadline {
            if event::poll(deadline.saturating_duration_since(Instant::now()))? {
                match event::read()? {
                    Event::Key(key)
                        if key.kind == KeyEventKind::Press
                            && matches!(key.code, KeyCode::Char('q' | 'Q') | KeyCode::Esc) =>
                    {
                        return Ok(())
                    }
                    Event::Resize(_, _) => {
                        render_view(&mut output, &values, &notifications, &date, &style)?
                    }
                    _ => (),
                }
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
        Some("view") => view(),
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
