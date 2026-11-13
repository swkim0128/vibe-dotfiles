//! Backend-local one-shot Dock observation. No tmux calls or resident collector.
use super::{home, now, plain, run, string, Result};
use fs2::FileExt;
use serde_json::{json, Value};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::path::Path;
use std::time::Duration;

fn state(path: &Path) -> Value {
    if path.metadata().is_ok_and(|meta| meta.len() <= 65536) {
        fs::read_to_string(path).ok().and_then(|raw| serde_json::from_str(&raw).ok()).unwrap_or(Value::Null)
    } else { Value::Null }
}

fn refresh(cache: &Path, config: &Value) -> Result<Value> {
    fs::create_dir_all(cache)?;
    let path = cache.join(string(&config["files"], "status"));
    let lock = OpenOptions::new().create(true).truncate(false).write(true).mode(0o600)
        .open(cache.join(string(&config["files"], "lock")))?;
    let mut saved = state(&path);
    if lock.try_lock_exclusive().is_ok() {
        // Re-read under the lock: another TUI may have just completed this tick.
        saved = state(&path);
        let age = now() - saved["attempted_at"].as_f64().unwrap_or(0.0);
        if age < 0.0 || age >= config["refresh_seconds"].as_f64().unwrap_or(5.0) {
            let script = home().join(string(config, "collector_relative_path"));
            let timeout = config["collector_timeout_seconds"].as_u64().unwrap_or(2) + 1;
            if run("bash", &[script.to_str().ok_or("invalid Dock collector path")?, "--backend", "herdr"], Duration::from_secs(timeout)).is_err() {
                let current = state(&path);
                if current["ok"] != false || current["attempted_at"] == saved["attempted_at"] {
                    let failed = json!({"ok":false,"attempted_at":now(),"error":"collector_failed",
                        "last_success_at":saved["last_success_at"],"badges":saved["badges"],"display":saved["display"]});
                    let temporary = path.with_extension(format!("{}.tmp", std::process::id()));
                    let mut file = OpenOptions::new().write(true).create_new(true).mode(0o600).open(&temporary)?;
                    write!(file, "{failed}")?;
                    fs::rename(temporary, &path)?;
                }
            }
            saved = state(&path);
        }
    }
    Ok(saved)
}

pub(super) fn read(base: &Path) -> String {
    let Ok(config) = serde_json::from_str::<Value>(include_str!("../../../vibe-tools/dock-badges.json")) else {
        return "알림?설정오류".into();
    };
    let saved = refresh(&base.join(string(&config["backends"], "herdr")), &config);
    let labels = &config["labels"];
    let Ok(saved) = saved else { return string(labels, "failed"); };
    if saved["ok"] == false { return string(labels, "failed"); }
    if saved["ok"] != true { return string(labels, "unknown"); }
    if saved["badges"].as_str().is_none() {
        return string(labels, "failed");
    }
    let age = now() - saved["last_success_at"].as_f64().unwrap_or(0.0);
    if age < 0.0 || age > config["stale_seconds"].as_f64().unwrap_or(30.0) {
        return string(labels, "stale");
    }
    if saved["badges"].as_str() == Some("") { return string(labels, "empty"); }
    let badges = string(&saved, "badges").lines()
        .filter_map(|line| line.split_once('='))
        .map(|(name, count)| format!("{name}:{count}"))
        .collect::<Vec<_>>().join(" ");
    plain(&badges, usize::MAX)
}
