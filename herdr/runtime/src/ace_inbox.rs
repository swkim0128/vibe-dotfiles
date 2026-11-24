use super::{now, run};
use serde_json::Value;
use std::fs;
use std::path::Path;
use std::sync::mpsc::{self, Receiver, TryRecvError};
use std::thread;
use std::time::{Duration, Instant};

const REFRESH_SECONDS: f64 = 60.0;
const STALE_SECONDS: f64 = 180.0;

pub(super) struct AceInbox {
    pending: Option<Receiver<bool>>,
    next: Instant,
    launcher_failed: bool,
}

impl Default for AceInbox {
    fn default() -> Self {
        Self { pending: None, next: Instant::now(), launcher_failed: false }
    }
}

fn label(state: &Value, age: f64) -> Option<&'static str> {
    match state["state"].as_str() {
        Some("unconfigured") | None => None,
        Some("failed") => Some("Ace 조회 실패"),
        Some("empty" | "unread") if !(0.0..=STALE_SECONDS).contains(&age) => Some("Ace 조회 지연"),
        Some("empty") => Some("Ace 미읽음 없음"),
        Some("unread") => Some("Ace 미읽음 있음"),
        _ => Some("Ace 조회 실패"),
    }
}

impl AceInbox {
    pub(super) fn notice(&mut self, base: &Path) -> Option<&'static str> {
        match self.pending.as_ref().map(Receiver::try_recv) {
            Some(Ok(success)) => {
                self.pending = None;
                self.launcher_failed = !success;
            }
            Some(Err(TryRecvError::Disconnected)) => {
                self.pending = None;
                self.launcher_failed = true;
            }
            _ => {}
        }
        let path = base.join("ace-inbox.json");
        let state: Value = path.metadata().ok().filter(|meta| meta.len() <= 256)
            .and_then(|_| fs::read_to_string(&path).ok())
            .and_then(|raw| serde_json::from_str(&raw).ok()).unwrap_or_default();
        let age = now() - state["at"].as_f64().unwrap_or(0.0);
        if self.pending.is_none() && Instant::now() >= self.next && !(0.0..REFRESH_SECONDS).contains(&age) {
            let (send, receive) = mpsc::channel();
            self.pending = Some(receive);
            self.next = Instant::now() + Duration::from_secs(10);
            thread::spawn(move || {
                let success = path.to_str().is_some_and(|path| run(
                    "python3", &["-I", "-c", include_str!("../ace_inbox.py"), path], Duration::from_secs(12)
                ).is_ok());
                let _ = send.send(success);
            });
        }
        if self.launcher_failed && !(0.0..REFRESH_SECONDS).contains(&age) {
            Some("Ace 조회 실패")
        } else {
            label(&state, age)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn inbox_label_distinguishes_missing_empty_failure_and_recovery() {
        for (state, age, expected) in [
            ("unconfigured", 2.0, None),
            ("empty", 2.0, Some("Ace 미읽음 없음")),
            ("unread", 2.0, Some("Ace 미읽음 있음")),
            ("failed", 2.0, Some("Ace 조회 실패")),
            ("empty", 2.0, Some("Ace 미읽음 없음")),
            ("unread", 200.0, Some("Ace 조회 지연")),
        ] {
            assert_eq!(label(&json!({"state":state}), age), expected);
        }
    }
}
