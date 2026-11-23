use crate::{home, now, run, show_alert, Result};
use fs2::FileExt;
use regex::Regex;
use serde_json::{json, Value};
use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::path::Path;
use std::time::Duration;

const MENTION_NOTICE: &str = "Slack 멘션 있음";

const SEARCH: &str = r#"
const workspace = (await slack.listWorkspaces()).find(
    item => item.teamId === options.team && item.userId === options.user
        && item.status === 'joined'
);
if (!workspace) throw Error('Slack work account is unavailable');
const client = await slack.getClient(workspace.teamId);
const date = new Date((options.since - 86400) * 1000).toISOString().slice(0, 10);
const mention = '<@' + workspace.userId + '>';
const matches = [];
for (let page = 1; ; page++) {
    const result = await client.search.messages({query: mention + ' after:' + date,
        count: 100, page, sort: 'timestamp', sort_dir: 'asc'});
    const messages = result.messages;
    for (const message of messages.matches) {
        const text = message.text || '';
        const timestamp = Number(message.ts);
        if (!message.channel?.id || !text.includes(mention)
            || message.user === workspace.userId || !Number.isFinite(timestamp)
            || timestamp < options.since || timestamp > options.until) continue;
        matches.push({id: message.channel.id + ':' + message.ts, timestamp});
    }
    if (page >= messages.pagination.page_count) break;
}
console.log(JSON.stringify({matches}));
"#;

pub fn poll(args: &[String]) -> Result<()> {
    let [aside, profile, team, user, state] = args else {
        return Err("usage: vibe-herdr slack-mentions <aside> <profile> <team> <user> <state>".into());
    };
    let path = Path::new(state);
    if let Some(parent) = path.parent().filter(|parent| !parent.as_os_str().is_empty()) {
        fs::create_dir_all(parent)?;
    }

    let lock = OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .mode(0o600)
        .open(path.with_extension("lock"))?;
    if let Err(error) = FileExt::try_lock_exclusive(&lock) {
        return if error.kind() == fs2::lock_contended_error().kind() {
            Ok(())
        } else {
            Err(error.into())
        };
    }

    let until = now();
    let state: Value = match fs::read_to_string(path) {
        Ok(raw) => serde_json::from_str(&raw)?,
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            write_state(path, &json!({"start": until, "scanned": until, "seen": {}, "latest": false}))?;
            println!("Slack mention baseline saved");
            return Ok(());
        }
        Err(error) => return Err(error.into()),
    };
    let start = state["start"].as_f64().ok_or("invalid Slack start timestamp")?;
    let scanned = state["scanned"].as_f64().ok_or("invalid Slack scan timestamp")?;
    let since = start.max(scanned - 900.0);
    let mut seen = state["seen"].as_object().ok_or("invalid Slack seen IDs")?.clone();
    seen.retain(|_, timestamp| timestamp.as_f64().is_some_and(|timestamp| timestamp >= since));

    let options = json!({"team": team, "user": user, "since": since, "until": until});
    let command = format!("const options = {options};\n{SEARCH}");
    let result = run(aside, &["repl", "--profile", profile, &command], Duration::from_secs(90))?;
    let ansi = Regex::new(r"\x1b\[[0-?]*[ -/]*[@-~]")?;
    let output = ansi.replace_all(&result, "");
    let line = output.lines().find(|line| line.starts_with(r#"{"matches":"#))
        .ok_or("Slack search returned no result")?;
    let payload: Value = serde_json::from_str(line)?;
    let matches = payload["matches"].as_array().ok_or("invalid Slack matches")?;

    let mut has_new_mention = false;
    for mention in matches {
        let id = mention["id"].as_str().ok_or("invalid Slack message ID")?;
        if seen.contains_key(id) {
            continue;
        }
        let timestamp = mention["timestamp"].as_f64().ok_or("invalid Slack message timestamp")?;
        seen.insert(id.to_owned(), json!(timestamp));
        has_new_mention = true;
    }

    if has_new_mention {
        show_alert(&json!({"status": "mention", "text": MENTION_NOTICE}))?;
    }

    let latest = !seen.is_empty();
    write_state(path, &json!({"start": start, "scanned": until, "seen": seen, "latest": latest}))?;
    println!("Slack mention check complete");
    Ok(())
}

pub(super) fn latest_notice() -> Option<&'static str> {
    let path = home().join(".local/state/vibe/slack-mentions-cowavecc.json");
    let metadata = path.symlink_metadata().ok()?;
    if !metadata.is_file() || metadata.len() > 1_048_576 {
        return None;
    }
    let raw = fs::read_to_string(path).ok()?;
    let state: Value = serde_json::from_str(&raw).ok()?;
    match &state["latest"] {
        Value::Bool(true) => Some(MENTION_NOTICE),
        Value::Bool(false) => Some("Slack 멘션 없음"),
        Value::String(text) if !text.is_empty() => Some(MENTION_NOTICE),
        _ => None,
    }
}

fn write_state(path: &Path, state: &Value) -> Result<()> {
    let temporary = path.with_extension("tmp");
    let mut file = OpenOptions::new()
        .create(true)
        .truncate(true)
        .write(true)
        .mode(0o600)
        .open(&temporary)?;
    serde_json::to_writer(&mut file, state)?;
    writeln!(file)?;
    fs::rename(temporary, path)?;
    Ok(())
}
