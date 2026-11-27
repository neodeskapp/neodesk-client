//! Feedback after quick support: the questions the console's admins set up,
//! shown on the end screen, and the person's answers sent back.
//!
//! After a session took place the app asks `GET /api/support/session/feedback`
//! with the session's token, which the console still takes for these two
//! routes after the end. `404 feedback_off`, any other answer or none means no
//! form: the end screen shows without one. The answers go to
//! `POST /api/support/session/feedback` as `{"answers": {"<id>": value}}`;
//! the console checks them against its form (PROTOCOL.md in the server repo).

use std::sync::Mutex;

use serde_json::{json, Map, Value};

use super::{http::Answer, link::Console};

/// The console's route.
pub const PATH: &str = "/api/support/session/feedback";
/// The most questions shown.
const MAX_QUESTIONS: usize = 10;
/// The longest question or option shown, in characters.
const MAX_LABEL_CHARS: usize = 200;
/// The longest answer sent, in characters.
pub const MAX_TEXT_CHARS: usize = 2000;
const KINDS: [&str; 4] = ["rating", "text", "choice", "yesno"];

/// Where the answers go: the console of the session that ended and its
/// token.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Channel {
    pub console: Console,
    pub token: String,
    pub questions: Vec<Value>,
}

static CHANNEL: Mutex<Option<Channel>> = Mutex::new(None);

pub fn open(channel: Channel) {
    *CHANNEL.lock().unwrap() = Some(channel);
}

pub fn current() -> Option<Channel> {
    CHANNEL.lock().unwrap().clone()
}

/// Text from the console as it is shown: no control characters, at most
/// `max` characters, trimmed.
fn shown(text: &str, max: usize) -> String {
    let text: String = text.chars().filter(|c| !c.is_control()).take(max).collect();
    text.trim().to_owned()
}

/// One question as the end screen takes it, or None for one it can't show.
fn question(value: &Value) -> Option<Value> {
    let id = value.get("id")?.as_str()?;
    if id.is_empty() || id.len() > 64 || id.chars().any(char::is_control) {
        return None;
    }
    let kind = value.get("kind")?.as_str()?;
    if !KINDS.contains(&kind) {
        return None;
    }
    let label = shown(value.get("label")?.as_str()?, MAX_LABEL_CHARS);
    if label.is_empty() {
        return None;
    }
    let flag = |name: &str| value.get(name).and_then(Value::as_bool).unwrap_or(false);
    let mut out = json!({
        "id": id,
        "kind": kind,
        "label": label,
        "required": flag("required"),
    });
    match kind {
        "text" => out["long"] = Value::Bool(flag("long")),
        "choice" => {
            let options: Vec<String> = value
                .get("options")?
                .as_array()?
                .iter()
                .filter_map(Value::as_str)
                .map(|o| shown(o, MAX_LABEL_CHARS))
                .filter(|o| !o.is_empty())
                .collect();
            if !(2..=8).contains(&options.len()) {
                return None;
            }
            out["options"] = json!(options);
        }
        _ => {}
    }
    Some(out)
}

/// The questions of the console's answer to the GET: none when feedback is
/// off, the session already has an answer, or the answer is anything else.
/// Questions the end screen can't show are left out.
pub fn questions(answer: &Answer) -> Vec<Value> {
    let body = &answer.body;
    if answer.status != 200
        || body.get("success").and_then(Value::as_bool) != Some(true)
        || body.get("given").and_then(Value::as_bool) == Some(true)
    {
        return Vec::new();
    }
    let Some(list) = body.pointer("/form/questions").and_then(Value::as_array) else {
        return Vec::new();
    };
    let mut seen = std::collections::HashSet::new();
    list.iter()
        .filter_map(question)
        .filter(|q| seen.insert(q["id"].as_str().unwrap_or_default().to_owned()))
        .take(MAX_QUESTIONS)
        .collect()
}

/// One answer as it is sent, or None when it doesn't fit its question.
fn answer_for(question: &Value, value: &Value) -> Option<Value> {
    match question["kind"].as_str()? {
        "rating" => {
            let stars = value.as_i64()?;
            (1..=5).contains(&stars).then(|| json!(stars))
        }
        "text" => {
            let text: String = value.as_str()?.chars().take(MAX_TEXT_CHARS).collect();
            let text = text.trim();
            (!text.is_empty()).then(|| json!(text))
        }
        "choice" => {
            let pick = value.as_str()?;
            question["options"]
                .as_array()?
                .iter()
                .any(|o| o.as_str() == Some(pick))
                .then(|| json!(pick))
        }
        "yesno" => value.as_bool().map(Value::Bool),
        _ => None,
    }
}

/// The body of the POST: the answers to `questions` that fit them, by id.
/// None when a required question has no answer.
pub fn body(questions: &[Value], answers: &Value) -> Option<Value> {
    let mut out = Map::new();
    for question in questions {
        let id = question["id"].as_str().unwrap_or_default();
        match answers.get(id).and_then(|value| answer_for(question, value)) {
            Some(value) => {
                out.insert(id.to_owned(), value);
            }
            None if question["required"] == true => return None,
            None => {}
        }
    }
    (!out.is_empty()).then(|| json!({ "answers": out }))
}

/// What the end screen says after the POST: "sent" when the console took the
/// answers (or already had them), else "failed" and the person may try again.
pub fn sent_state(answer: &Answer) -> &'static str {
    let already = answer.status == 409
        && answer.body.get("error").and_then(Value::as_str) == Some("already_given");
    if (200..300).contains(&answer.status) || already {
        "sent"
    } else {
        "failed"
    }
}
