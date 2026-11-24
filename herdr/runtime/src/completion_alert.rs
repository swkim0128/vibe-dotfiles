use crate::{quick, rpc_on_socket, Result};
use serde_json::{json, Value};
use std::{
    env, fs,
    os::unix::fs::{FileTypeExt, MetadataExt},
    path::{Path, PathBuf},
    time::Duration,
};

const TIMEOUT: Duration = Duration::from_millis(500);

fn label(value: &Value) -> Option<String> {
    let text = value
        .as_str()?
        .split(|c: char| c.is_whitespace() || c.is_control())
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join(" ");
    (!text.is_empty() && !text.chars().all(|c| c.is_ascii_digit())).then_some(text)
}

fn items<'a>(data: &'a Value, key: &str) -> impl Iterator<Item = &'a Value> {
    data[key].as_array().into_iter().flatten()
}

fn pane_cwd(pane: &Value) -> Option<&str> {
    pane["foreground_cwd"]
        .as_str()
        .filter(|cwd| !cwd.is_empty())
        .or_else(|| pane["cwd"].as_str())
}

fn conversation_title(pane: &Value) -> Option<String> {
    let agent = pane["agent"].as_str()?;
    let title =
        label(&pane["terminal_title_stripped"]).or_else(|| label(&pane["terminal_title"]))?;
    let title = if agent == "codex" && title.contains(" | ") {
        let (_, details) = title.split_once(" | ")?;
        let (first, rest) = details.split_once(" | ")?;
        let (model, task) = if first.to_ascii_lowercase().starts_with("gpt-") {
            (first, rest)
        } else {
            rest.split_once(" | ")?
        };
        if !model.to_ascii_lowercase().starts_with("gpt-") {
            return None;
        }
        task.to_owned()
    } else {
        title
    };
    let cwd_name = pane_cwd(pane)
        .and_then(|cwd| Path::new(cwd).file_name())
        .and_then(|name| name.to_str());
    (!title.is_empty()
        && !title.starts_with(['/', '~'])
        && !title.eq_ignore_ascii_case(agent)
        && !matches!(
            title.as_str(),
            "작업 제목 미확인" | "Untitled" | "New chat" | "New conversation"
        )
        && cwd_name != Some(title.as_str()))
    .then_some(title)
}

fn project(pane: &Value) -> Option<String> {
    label(&pane["tokens"]["project_name"]).filter(|name| name != "프로젝트 미확인")
}

fn git_project(pane: &Value) -> Option<String> {
    let root = quick(
        "git",
        &[
            "-C",
            pane_cwd(pane)?,
            "rev-parse",
            "--path-format=absolute",
            "--git-common-dir",
        ],
    )?;
    let root = Path::new(&root);
    if root.file_name()?.to_str()? != ".git" {
        return None;
    }
    label(&json!(root.parent()?.file_name()?.to_str()?))
}

fn tab<'a>(snapshot: &'a Value, pane: &Value) -> Option<&'a Value> {
    items(snapshot, "tabs").find(|tab| tab["tab_id"] == pane["tab_id"])
}

fn tab_name(snapshot: &Value, pane: &Value) -> Option<String> {
    tab(snapshot, pane).and_then(|tab| label(&tab["label"]))
}

fn workspace_name(snapshot: &Value, pane: &Value) -> Option<String> {
    items(snapshot, "workspaces")
        .find(|workspace| workspace["workspace_id"] == pane["workspace_id"])
        .and_then(|workspace| label(&workspace["label"]))
}

fn pane_detail(pane: &Value) -> Option<String> {
    label(&pane["label"])
        .or_else(|| conversation_title(pane))
        .or_else(|| project(pane))
}

fn duplicate_detail(snapshot: &Value, pane: &Value, subject: &str) -> String {
    let peers: Vec<_> = items(snapshot, "panes")
        .filter(|other| {
            other["pane_id"] != pane["pane_id"]
                && (tab_name(snapshot, other)
                    .or_else(|| project(other))
                    .or_else(|| conversation_title(other))
                    .as_deref()
                    == Some(subject)
                    || (pane["tab_id"] == other["tab_id"] && other["agent"].is_string()))
        })
        .collect();
    if peers.is_empty() {
        return String::new();
    }
    let workspace = workspace_name(snapshot, pane);
    let same_workspace_name = peers
        .iter()
        .any(|other| workspace_name(snapshot, other) == workspace);
    let detail = same_workspace_name
        .then(|| pane_detail(pane))
        .flatten()
        .filter(|detail| detail != subject);
    let ambiguous = peers.iter().any(|other| {
        workspace_name(snapshot, other) == workspace
            && pane_detail(other).filter(|value| value != subject) == detail
    });
    [
        workspace,
        detail,
        ambiguous.then(|| pane["pane_id"].as_str().unwrap_or("").to_owned()),
    ]
    .into_iter()
    .flatten()
    .collect::<Vec<_>>()
    .join(" · ")
}

fn socket_generation(socket: &Path) -> Result<String> {
    let info = fs::metadata(socket)?;
    if !socket.is_absolute() || !info.file_type().is_socket() {
        return Err("invalid Herdr socket".into());
    }
    Ok(format!("{}:{}", info.dev(), info.ino()))
}

fn completion(
    snapshot: &Value,
    pane: &Value,
    context_tab: Option<String>,
    fallback_project: Option<String>,
) -> Value {
    let subject = tab_name(snapshot, pane)
        .or(context_tab)
        .or_else(|| project(pane))
        .or(fallback_project)
        .or_else(|| conversation_title(pane));
    let detail = subject
        .as_deref()
        .map(|name| duplicate_detail(snapshot, pane, name))
        .unwrap_or_default();
    let subject = subject.unwrap_or_default();
    json!({"status":"done", "subject":subject, "text":detail})
}

pub fn payload(data: &Value, context: &Value) -> Value {
    let context_matches = context["focused_pane_id"] == data["pane_id"]
        && data["pane_id"].is_string()
        && context["workspace_id"] == data["workspace_id"];
    let context_tab = context_matches
        .then(|| label(&context["tab_label"]))
        .flatten();
    let fallback = || completion(&Value::Null, &Value::Null, context_tab.clone(), None);
    let Some(socket) = env::var_os("HERDR_SOCKET_PATH").map(PathBuf::from) else {
        return fallback();
    };
    let Ok(generation) = socket_generation(&socket) else {
        return fallback();
    };
    let Ok(result) = rpc_on_socket(&socket, "session.snapshot", json!({}), TIMEOUT) else {
        return fallback();
    };
    let snapshot = &result["snapshot"];
    let Some(pane) = items(snapshot, "panes").find(|pane| {
        pane["pane_id"] == data["pane_id"] && pane["workspace_id"] == data["workspace_id"]
    }) else {
        return fallback();
    };
    let context_tab = context_tab.filter(|_| tab(snapshot, pane).is_none());
    let fallback_project =
        if tab_name(snapshot, pane).is_none() && context_tab.is_none() && project(pane).is_none() {
            git_project(pane)
        } else {
            None
        };
    let mut alert = completion(snapshot, pane, context_tab, fallback_project);
    if pane["terminal_id"].is_string()
        && pane["agent"].is_string()
        && socket_generation(&socket).is_ok_and(|current| current == generation)
    {
        if let Ok(executable) = env::current_exe() {
            alert["focus_executable"] = json!(executable);
            alert["focus_target"] = json!({"socket":socket, "generation":generation, "pane":pane["pane_id"],
                "terminal":pane["terminal_id"], "agent":pane["agent"], "session":pane["agent_session"]}).to_string().into();
        }
    }
    alert
}

pub fn focus(target: &str) -> Result<()> {
    let target: Value = serde_json::from_str(target)?;
    let socket = Path::new(target["socket"].as_str().ok_or("missing Herdr socket")?);
    let generation = target["generation"]
        .as_str()
        .ok_or("missing Herdr socket generation")?;
    let pane_id = target["pane"]
        .as_str()
        .filter(|id| !id.is_empty())
        .ok_or("missing Herdr pane")?;
    if socket_generation(socket)? != generation {
        return Err("Herdr session changed".into());
    }
    let result = rpc_on_socket(socket, "pane.get", json!({"pane_id":pane_id}), TIMEOUT)?;
    let pane = &result["pane"];
    if pane["pane_id"] != pane_id
        || !target["terminal"].is_string()
        || pane["terminal_id"] != target["terminal"]
        || !target["agent"].is_string()
        || pane["agent"] != target["agent"]
        || (!target["session"].is_null() && pane["agent_session"] != target["session"])
        || socket_generation(socket)? != generation
    {
        return Err("Herdr alert target changed".into());
    }
    rpc_on_socket(socket, "agent.focus", json!({"target":pane_id}), TIMEOUT)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn completion_prefers_named_tab_then_project_then_native_title() {
        let mut snapshot = json!({"tabs":[{"tab_id":"w1:t1","label":"ashop"}]});
        let mut pane = json!({"pane_id":"w1:p1","tab_id":"w1:t1","workspace_id":"w1","agent":"codex",
            "terminal_title_stripped":"src | feature | GPT-6.2-Sol medium | 상품 검증 | 후속",
            "title":"~/Project/src | GPT-6.2-Sol | 작업 제목 미확인", "tokens":{"project_name":"shopping-danuri"}});
        assert_eq!(completion(&snapshot, &pane, None, None)["subject"], "ashop");
        snapshot["tabs"][0]["label"] = json!("4");
        assert_eq!(
            completion(&snapshot, &pane, None, None)["subject"],
            "shopping-danuri"
        );
        pane["tokens"]["project_name"] = json!("프로젝트 미확인");
        assert_eq!(
            completion(&snapshot, &pane, None, None)["subject"],
            "상품 검증 | 후속"
        );
        pane["terminal_title_stripped"] = json!("src | GPT-6.2-Sol | 작업 제목 미확인");
        assert_eq!(completion(&snapshot, &pane, None, None)["subject"], "");
    }

    #[test]
    fn duplicate_names_use_workspace_then_conversation_metadata() {
        let pane = json!({"pane_id":"w1:p1","tab_id":"w1:t1","workspace_id":"w1","agent":"codex",
            "terminal_title_stripped":"ashop | GPT-6.2-Sol | 공급사 가져오기"});
        let mut snapshot = json!({"tabs":[{"tab_id":"w1:t1","label":"ashop"},{"tab_id":"w2:t1","label":"ashop"}],
            "workspaces":[{"workspace_id":"w1","label":"작업 스레드"},{"workspace_id":"w2","label":"personal"}],
            "panes":[pane,{"pane_id":"w2:p1","tab_id":"w2:t1","workspace_id":"w2"}]});
        assert_eq!(
            completion(&snapshot, &pane, None, None)["text"],
            "작업 스레드"
        );
        snapshot["panes"][1] = json!({"pane_id":"w1:p2","tab_id":"w1:t1","workspace_id":"w1","agent":"codex",
            "terminal_title_stripped":"ashop | GPT-6.2-Sol | 상품 검증"});
        assert_eq!(
            completion(&snapshot, &pane, None, None)["text"],
            "작업 스레드 · 공급사 가져오기"
        );
    }
}
