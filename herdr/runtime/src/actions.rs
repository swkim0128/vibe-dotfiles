use super::{home, plain, rpc_timeout, run, string, subagent_scope, Result};
use regex::Regex;
use serde_json::{json, Value};
use std::env;
use std::fs;
use std::io::{Read, Write};
use std::os::unix::fs::MetadataExt;
use std::path::Path;
use std::process::{Child, Command, Stdio};
use std::sync::mpsc::{self, Receiver};
use std::thread;
use std::time::{Duration, Instant};
use unicode_width::UnicodeWidthStr;

pub struct Hit {
    pub start: u16,
    pub end: u16,
    pub row: u16,
    pub action: Option<usize>,
}

struct Action {
    label: String,
    prompt: String,
}

struct Pending {
    child: Child,
    output: Receiver<std::io::Result<Vec<u8>>>,
    errors: Option<Receiver<std::io::Result<Vec<u8>>>>,
    started: Instant,
    label: String,
    completion: Option<(i64, String)>,
}

pub struct Actions {
    items: Vec<Action>,
    selected: usize,
    pub open: bool,
    keyboard: bool,
    pub message: String,
    pending: Option<Pending>,
    submitted_at: Option<Instant>,
    confirmed_completion: Option<(i64, String)>,
}

impl Actions {
    pub fn new(settings: &Value) -> Result<Self> {
        let items = settings["buttons"].as_array().ok_or("missing action buttons")?
            .iter().map(|item| {
                let label = string(item, "label");
                let prompt = string(item, "prompt");
                if label.is_empty() || prompt.is_empty() || label.chars().any(char::is_control) {
                    return Err("invalid action button".into());
                }
                Ok(Action { label, prompt })
            }).collect::<Result<Vec<_>>>()?;
        if items.is_empty() { return Err("missing action buttons".into()); }
        Ok(Self { items, selected: 0, open: false, keyboard: false,
            message: String::new(), pending: None, submitted_at: None, confirmed_completion: None })
    }

    pub fn select(&mut self, forward: bool) {
        self.open = true;
        if !self.keyboard {
            self.keyboard = true;
            return;
        }
        self.keyboard = true;
        self.selected = if forward { (self.selected + 1) % self.items.len() }
            else { (self.selected + self.items.len() - 1) % self.items.len() };
    }

    pub fn toggle(&mut self) {
        self.open = !self.open;
        self.keyboard = self.open;
    }

    pub fn close(&mut self) {
        self.open = false;
        self.keyboard = false;
    }

    pub fn selected(&self) -> Option<usize> {
        self.keyboard.then_some(self.selected)
    }

    pub fn busy(&self) -> bool { self.pending.is_some() }

    pub fn bar(&self, width: u16, row: u16, start: u16) -> (u16, String, Vec<Hit>) {
        let available = width.saturating_sub(start);
        let total = self.items.iter().map(|item| UnicodeWidthStr::width(item.label.as_str()) + 2)
            .sum::<usize>() + self.items.len().saturating_sub(1);
        if total > usize::from(available) {
            let label = "[a 더보기]";
            let size = UnicodeWidthStr::width(label) as u16;
            if available < size { return (width, String::new(), vec![]); }
            return (start.saturating_sub(1), label.into(), vec![Hit { start, end: start + size, row, action: None }]);
        }
        let (text, hits) = self.buttons(start, row, 0, self.items.len());
        (start.saturating_sub(1), text, hits)
    }

    fn buttons(&self, start: u16, row: u16, first: usize, end: usize) -> (String, Vec<Hit>) {
        let mut text = String::new();
        let mut hits = Vec::new();
        let mut column = start;
        for index in first..end {
            if index > first { text.push(' '); column += 1; }
            let label = format!("[{}]", self.items[index].label);
            let size = UnicodeWidthStr::width(label.as_str()) as u16;
            if self.keyboard && index == self.selected { text.push_str("\x1b[7m"); }
            text.push_str(&label);
            text.push_str("\x1b[0m");
            hits.push(Hit { start: column, end: column + size, row, action: Some(index) });
            column += size;
        }
        (text, hits)
    }

    pub fn overlay(&self, output: &mut impl Write, width: u16, height: u16) -> Result<Vec<Hit>> {
        use crossterm::{cursor, execute};
        if height == 0 || width == 0 { return Ok(vec![]); }
        let row = if height > 1 { 1 } else { 0 };
        if height > 1 {
            write!(output, "{}", plain("Codex 동작 · Tab/←/→ 선택 · Enter 접수 · Esc 복귀", usize::from(width)))?;
        }
        let mut first = self.selected;
        let selected_width = UnicodeWidthStr::width(self.items[first].label.as_str()) + 2;
        if selected_width > usize::from(width) {
            execute!(output, cursor::MoveTo(0, row))?;
            write!(output, "{}", plain("버튼 표시 공간 부족 · 창을 넓히세요", usize::from(width)))?;
            output.flush()?;
            return Ok(vec![]);
        }
        let mut used = selected_width;
        while first > 0 {
            let size = UnicodeWidthStr::width(self.items[first - 1].label.as_str()) + 3;
            if used + size > usize::from(width) { break; }
            used += size;
            first -= 1;
        }
        let mut end = self.selected + 1;
        while end < self.items.len() {
            let size = UnicodeWidthStr::width(self.items[end].label.as_str()) + 3;
            if used + size > usize::from(width) { break; }
            used += size;
            end += 1;
        }
        let (text, hits) = self.buttons(0, row, first, end);
        execute!(output, cursor::MoveTo(0, row))?;
        write!(output, "{text}")?;
        if height > 2 {
            execute!(output, cursor::MoveTo(0, height - 1))?;
            let message = if self.message.is_empty() { "클릭하면 연결된 대화에 요청 1건을 접수합니다" } else { &self.message };
            write!(output, "{}", plain(message, usize::from(width)))?;
        }
        output.flush()?;
        Ok(hits)
    }

    pub fn submit(&mut self, index: usize, scope: Option<&Value>) {
        if self.pending.is_some() || self.submitted_at.is_some_and(|at| at.elapsed() < Duration::from_millis(800)) {
            return;
        }
        let Some(item) = self.items.get(index) else { return; };
        let request = checked_target(scope).and_then(|(native, cwd)| {
            let mut child = Command::new("codex")
                .args(["queue", "--thread", &native, "--message", &item.prompt, "-C", &cwd])
                .stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn()?;
            let output = child.stdout.take().ok_or("missing queue output")?;
            let (sender, receiver) = mpsc::channel();
            thread::spawn(move || {
                let mut bytes = Vec::new();
                let result = output.take(1_048_576).read_to_end(&mut bytes).map(|_| bytes);
                let _ = sender.send(result);
            });
            Ok(Pending { child, output: receiver, errors: None, started: Instant::now(), label: item.label.clone(), completion: None })
        });
        match request {
            Ok(pending) => {
                self.selected = index;
                self.message = format!("접수 중 · {}", item.label);
                self.pending = Some(pending);
                self.submitted_at = Some(Instant::now());
            }
            Err(error) => {
                self.message = format!("발신하지 않음 · {error}");
                if !self.message.contains("Codex 패널에서 실행:") {
                    self.message.push_str(&format!(" · Codex 패널에서 실행: {} bar ensure --current --parent-current --relaunch", home().join(".config/herdr/vibe-herdr").display()));
                }
            }
        }
    }

    pub fn confirm_completion(&mut self, record: &Value, scope: Option<&Value>) {
        if self.pending.is_some() {
            self.message = "이전 요청 처리 중 · 결과를 기다린 뒤 이 작업을 다시 확인하세요".into();
            return;
        }
        let request = (|| -> Result<Pending> {
            let id = record["id"].as_i64().ok_or("작업 ID 미확인")?;
            let version = record["completion_token"].as_str().filter(|v| !v.is_empty()).ok_or("완료 판본 미확인 · 목록을 새로 확인하세요")?;
            if record["queue_status"] != "done" { return Err("완료한 작업만 확인할 수 있습니다".into()); }
            let (native, cwd) = checked_target(scope)?;
            if record["owner_tool"] != "codex" || record["owner_thread"].as_str() != Some(native.as_str()) {
                return Err("선택 요청은 다른 배정 대화의 조회 항목입니다 · 원담당 대화에서 확인하세요".into());
            }
            let mut child = Command::new("vibe").current_dir(&cwd)
                .args(["queue", "completion-confirm", &id.to_string(), "--tool", "codex",
                    "--conversation-id", &native, "--version", version,
                    "--evidence", "TUI 상세에서 사용자가 완료 확인·목록에서 치우기를 선택", "--json"])
                .stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn()?;
            let output = child.stdout.take().ok_or("확인 결과 출력 미확인")?;
            let errors = child.stderr.take().ok_or("확인 오류 출력 미확인")?;
            let (error_sender, error_receiver) = mpsc::channel();
            thread::spawn(move || {
                let mut bytes = Vec::new();
                let result = errors.take(65_536).read_to_end(&mut bytes).map(|_| bytes);
                let _ = error_sender.send(result);
            });
            let (sender, receiver) = mpsc::channel();
            thread::spawn(move || {
                let mut bytes = Vec::new();
                let result = output.take(1_048_576).read_to_end(&mut bytes).map(|_| bytes);
                let _ = sender.send(result);
            });
            Ok(Pending { child, output: receiver, errors: Some(error_receiver), started: Instant::now(),
                label: format!("완료 확인 #{id}"), completion: Some((id, version.to_owned())) })
        })();
        match request {
            Ok(pending) => { self.message = format!("저장 중 · {}", pending.label); self.pending = Some(pending); }
            Err(error) => { self.message = format!("완료 확인하지 않음 · {error}"); }
        }
    }

    pub fn poll(&mut self) -> bool {
        let Some(pending) = self.pending.as_mut() else { return false; };
        let result = match pending.child.try_wait() {
            Ok(Some(status)) => Some(if status.success() {
                match pending.output.recv_timeout(Duration::from_millis(100)) {
                    Ok(Ok(bytes)) => if let Some((id, version)) = &pending.completion {
                        match serde_json::from_slice::<Value>(&bytes) {
                            Ok(value) if value["id"].as_i64() == Some(*id) && value["completion_confirmed"] == true
                                && value["completion_token"].as_str() == Some(version.as_str()) => {
                                self.confirmed_completion = Some((*id, version.clone()));
                                format!("완료 확인 저장됨 · #{id} 목록에서 치움 · 큐 이력 보존")
                            },
                            _ => "완료 확인 결과 미확인 · 자동 재전송하지 않음".into(),
                        }
                    } else { format!("접수됨 · {} · 작업 완료는 별도 확인", pending.label) },
                    _ => "접수 결과 미확인 · 자동 재전송하지 않음".into(),
                }
            } else if pending.completion.is_some() {
                let reason = pending.errors.as_ref()
                    .and_then(|errors| errors.recv_timeout(Duration::from_millis(100)).ok())
                    .and_then(std::result::Result::ok)
                    .and_then(|bytes| serde_json::from_slice::<Value>(&bytes).ok())
                    .and_then(|value| value["error"].as_str().map(|text|
                        text.chars().filter(|c| !c.is_control()).take(240).collect::<String>()))
                    .filter(|text| !text.is_empty()).unwrap_or_else(|| "구조화된 오류 사유 미확보".into());
                format!("{} 실패 · {status} · {reason} · 상세를 새로 확인하세요 · 자동 재전송하지 않음", pending.label)
            } else {
                format!("접수 실패 · {} · 자동 재전송하지 않음", status)
            }),
            Ok(None) if pending.started.elapsed() < Duration::from_secs(20) => None,
            Ok(None) | Err(_) => {
                let _ = pending.child.kill();
                let _ = pending.child.wait();
                Some(if pending.completion.is_some() { "완료 확인 결과 미확인 · 상세를 새로 확인하세요 · 자동 재전송하지 않음".into() }
                    else { "접수 결과 미확인 · 자동 재전송하지 않음".into() })
            }
        };
        if let Some(message) = result {
            self.message = message;
            self.pending = None;
            true
        } else { false }
    }

    pub fn take_confirmed_completion(&mut self) -> Option<(i64, String)> {
        self.confirmed_completion.take()
    }
}

impl Drop for Actions {
    fn drop(&mut self) {
        if let Some(pending) = self.pending.as_mut() {
            let _ = pending.child.kill();
            let _ = pending.child.wait();
        }
    }
}

fn checked_target(scope: Option<&Value>) -> Result<(String, String)> {
    let reconnect = format!("Codex 패널에서 실행: {} bar ensure --current --parent-current --relaunch", home().join(".config/herdr/vibe-herdr").display());
    let scope = scope.ok_or_else(|| format!("부모 대화 미연결 · {reconnect}"))?;
    let parent_id = scope["parent_pane"].as_str().ok_or("missing parent pane")?;
    let view_id = scope["view_pane"].as_str().ok_or("missing view pane")?;
    let current = subagent_scope(parent_id, view_id, "")?;
    for key in ["view_pane", "view_terminal", "parent_terminal", "parent_session", "parent_cli_pids", "parent_stamp", "socket_generation", "view_pid"] {
        if current[key] != scope[key] { return Err(format!("대화 연결 변경 · {reconnect}").into()); }
    }
    if current["view_pid"].as_u64() != Some(u64::from(std::process::id())) {
        return Err(format!("현재 TUI 연결 아님 · {reconnect}").into());
    }
    let reference = &current["parent_session"];
    let native = reference["value"].as_str().unwrap_or("");
    if reference["agent"] != "codex" || reference["kind"] != "id" || reference["source"] != "herdr:codex"
        || !Regex::new(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")?.is_match(native) {
        return Err(format!("공식 Codex 대화 미연결 · {reconnect}").into());
    }
    let info = rpc_timeout("pane.process_info", json!({"pane_id":parent_id}), Duration::from_millis(500))?;
    let shell_pid = info["process_info"]["shell_pid"].as_u64().ok_or("missing pane shell")?;
    let pid = current["parent_cli_pids"][0].as_u64().ok_or("missing parent process")?;
    let mut cursor = pid;
    for _ in 0..32 {
        if cursor == shell_pid { break; }
        cursor = run("ps", &["-p", &cursor.to_string(), "-o", "ppid="], Duration::from_millis(300))?.parse()?;
        if cursor <= 1 { return Err("Codex process outside parent pane".into()); }
    }
    if cursor != shell_pid { return Err("Codex process ancestry not confirmed".into()); }
    let parent = rpc_timeout("pane.get", json!({"pane_id":parent_id}), Duration::from_millis(500))?["pane"].clone();
    let cwd = parent["cwd"].as_str().filter(|value| !value.is_empty()).ok_or("missing parent cwd")?;
    let processes = info["process_info"]["foreground_processes"].as_array().ok_or("missing parent process list")?;
    let process = processes.iter().find(|process| process["pid"].as_u64() == Some(pid)).ok_or("parent process changed")?;
    if process["cwd"].as_str() != Some(cwd) || !Path::new(cwd).is_absolute() || !Path::new(cwd).is_dir() {
        return Err("parent pane and Codex cwd do not match".into());
    }
    if parent["agent_session"] != *reference || parent["terminal_id"] != current["parent_terminal"]
        || fs::metadata(env::var("HERDR_SOCKET_PATH")?)?.ino() != current["socket_generation"].as_u64().unwrap_or(0)
        || run("ps", &["-p", &pid.to_string(), "-o", "lstart=", "-o", "comm="], Duration::from_millis(300))? != current["parent_stamp"].as_str().unwrap_or("") {
        return Err(format!("발신 전 대화 연결 변경 · {reconnect}").into());
    }
    Ok((native.to_owned(), cwd.to_owned()))
}
