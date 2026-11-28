//! Fleet tasks a NeoDesk server sends through the sealed heartbeat:
//! fleet.run (scripts and other tasks), fleet.resources (printers, network
//! drives, DNS, VPN and proxy) and fleet.compliance (checks and installed
//! software).
//!
//! The heartbeat loop must not wait for them, so each command runs on a
//! thread of its own. Finished results wait in a queue that the loop sends
//! with its next heartbeat ([`take_results`]). A command id runs once: the
//! ids of running jobs, the last results and, for fleet.run, a ledger that
//! survives a restart of the client answer a command the server sends again.

mod compliance;
mod host;
mod process;
mod resources;
mod run;
#[cfg(windows)]
mod win;

use std::{
    collections::{HashMap, VecDeque},
    sync::{Mutex, MutexGuard},
    time::{Duration, Instant},
};

use hbb_common::log;
use serde_json::{json, Value};

pub const RUN: &str = "fleet.run";
pub const RESOURCES: &str = "fleet.resources";
pub const COMPLIANCE: &str = "fleet.compliance";

/// Final results kept to answer a command the server sends again
const FINISHED_KEPT: usize = 16;
/// fleet.run command ids the ledger remembers across restarts
const LEDGER_KEPT: usize = 64;
const LEDGER_OPTION: &str = "nd-fleet-runs";
/// Results of a heartbeat that did not reach the server wait this long
const RETRY_AFTER: Duration = Duration::from_secs(15);

pub fn is_fleet_command(name: &str) -> bool {
    matches!(name, RUN | RESOURCES | COMPLIANCE)
}

/// What runs on a job thread. A fleet.run job is keyed by its run id, so a
/// second command for the same run waits for the first one's result.
#[derive(Clone, Copy, Debug, Hash, PartialEq, Eq)]
enum Job {
    Run(i64),
    Command(i64),
}

#[derive(Default)]
struct State {
    /// The command ids that wait for each running job
    jobs: HashMap<Job, Vec<i64>>,
    /// The last final results, by command id
    finished: VecDeque<(i64, Value)>,
    /// Final results for the next heartbeat
    queue: VecDeque<Value>,
    /// No results leave before this, after a heartbeat failed
    hold_until: Option<Instant>,
}

impl State {
    fn is_running(&self, id: i64) -> bool {
        self.jobs.values().any(|ids| ids.contains(&id))
    }
}

lazy_static::lazy_static! {
    static ref STATE: Mutex<State> = Mutex::new(State::default());
    static ref LEDGER_LOCK: Mutex<()> = Mutex::new(());
}

fn state() -> MutexGuard<'static, State> {
    STATE.lock().unwrap_or_else(|err| err.into_inner())
}

pub(crate) fn now_rfc3339() -> String {
    chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Secs, true)
}

/// One entry of the heartbeat's results
fn entry(id: i64, status: &str, result: Value) -> Value {
    json!({"id": id, "status": status, "result": result})
}

/// Takes fleet command `id`, which the dedupe set of the telemetry
/// commands has not seen yet. Returns the result to send at once, if any:
/// a refusal, an argument error, "running" for a fleet.run that started,
/// or the result of a command that ran before.
pub fn accept(id: i64, command: &str, args: &Value, refused: bool) -> Option<Value> {
    // The support agent takes no fleet work (fleet-contract.md); the
    // receiver takes it like the full client
    if refused {
        let mut result = json!({"code": "support_agent_restricted"});
        if command == RUN {
            result["run_id"] = json!(run::run_id_of(args));
        }
        return Some(entry(id, "permission_denied", result));
    }
    if !is_fleet_command(command) {
        return Some(entry(
            id,
            "unsupported",
            json!({"code": "command_not_supported"}),
        ));
    }
    {
        let state = state();
        if state.is_running(id) {
            return None;
        }
        if let Some((_, result)) = state.finished.iter().find(|(done, _)| *done == id) {
            return Some(result.clone());
        }
    }
    match command {
        RUN => accept_run(id, args),
        RESOURCES => {
            let args = args.clone();
            start(Job::Command(id), id, move || resources::apply(&args));
            None
        }
        _ => {
            let remediate = compliance::remediate_requested(args);
            start(Job::Command(id), id, move || compliance::collect(remediate));
            None
        }
    }
}

fn accept_run(id: i64, args: &Value) -> Option<Value> {
    let task = match run::parse(args) {
        Ok(task) => task,
        Err(refusal) => {
            return Some(entry(
                id,
                refusal.status,
                run::refusal_result(run::run_id_of(args), &refusal),
            ))
        }
    };
    if let Some(status) = ledger_status(id) {
        return Some(entry_from_ledger(id, task.run_id, &status));
    }
    let job = Job::Run(task.run_id);
    let running = entry(
        id,
        "running",
        json!({"run_id": task.run_id, "started_at": now_rfc3339()}),
    );
    {
        let mut state = state();
        if let Some(waiting) = state.jobs.get_mut(&job) {
            // The same run under another command id: it gets the result
            // of the one that runs
            waiting.push(id);
            drop(state);
            ledger_put(id, "running");
            return Some(running);
        }
        state.jobs.insert(job, vec![id]);
    }
    ledger_put(id, "running");
    spawn(job, move || run::execute(&task));
    Some(running)
}

/// Registers `id` as the one waiting for `job` and starts it
fn start(job: Job, id: i64, work: impl FnOnce() -> (String, Value) + Send + 'static) {
    state().jobs.insert(job, vec![id]);
    spawn(job, work);
}

fn spawn(job: Job, work: impl FnOnce() -> (String, Value) + Send + 'static) {
    let spawned = std::thread::Builder::new()
        .name("fleet-task".to_owned())
        .spawn(move || {
            let (status, result) = std::panic::catch_unwind(std::panic::AssertUnwindSafe(work))
                .unwrap_or_else(|_| ("error".to_owned(), json!({"code": "client_error"})));
            finish(job, &status, result);
        });
    if let Err(err) = spawned {
        log::error!("fleet task thread did not start: {err}");
        finish(
            job,
            "error",
            json!({"code": "client_error", "output": "The client could not start the task."}),
        );
    }
}

fn finish(job: Job, status: &str, result: Value) {
    let ids = {
        let mut state = state();
        let ids = state.jobs.remove(&job).unwrap_or_default();
        for id in &ids {
            let done = entry(*id, status, result.clone());
            state.queue.push_back(done.clone());
            state.finished.push_back((*id, done));
            while state.finished.len() > FINISHED_KEPT {
                state.finished.pop_front();
            }
        }
        ids
    };
    if let Job::Run(_) = job {
        for id in &ids {
            ledger_put(*id, status);
        }
    }
    log::info!("fleet task {job:?} finished: {status}");
}

/// The finished results for the next heartbeat, oldest first, as many as
/// fit into `budget` bytes of JSON. With `at_least_one`, the first result
/// leaves even when it alone is bigger.
pub fn take_results(budget: usize, at_least_one: bool) -> Vec<Value> {
    take_from(&mut state(), budget, at_least_one, Instant::now())
}

fn take_from(state: &mut State, budget: usize, at_least_one: bool, now: Instant) -> Vec<Value> {
    if let Some(until) = state.hold_until {
        if now < until {
            return Vec::new();
        }
        state.hold_until = None;
    }
    let mut taken = Vec::new();
    let mut used = 0;
    while let Some(next) = state.queue.front() {
        let size = serde_json::to_string(next)
            .map(|text| text.len())
            .unwrap_or(0);
        if used + size > budget && !(taken.is_empty() && at_least_one) {
            break;
        }
        used += size;
        if let Some(next) = state.queue.pop_front() {
            taken.push(next);
        }
    }
    taken
}

/// Puts back the results of a heartbeat that did not reach the server.
/// They leave again with a heartbeat after [`RETRY_AFTER`].
pub fn requeue(results: Vec<Value>) {
    requeue_into(&mut state(), results, Instant::now());
}

fn requeue_into(state: &mut State, results: Vec<Value>, now: Instant) {
    if results.is_empty() {
        return;
    }
    for result in results.into_iter().rev() {
        state.queue.push_front(result);
    }
    state.hold_until = Some(now + RETRY_AFTER);
}

// The ledger: "id:status;id:status", the last LEDGER_KEPT fleet.run
// command ids with the status they had. "running" means the client stopped
// while it ran: the task may have restarted or updated the computer or the
// client, so it does not run again.

fn ledger_parse(text: &str) -> Vec<(i64, String)> {
    text.split(';')
        .filter_map(|item| {
            let (id, status) = item.split_once(':')?;
            Some((id.trim().parse().ok()?, status.trim().to_owned()))
        })
        .filter(|(id, status): &(i64, String)| *id > 0 && !status.is_empty())
        .collect()
}

fn ledger_format(entries: &[(i64, String)]) -> String {
    entries
        .iter()
        .map(|(id, status)| format!("{id}:{status}"))
        .collect::<Vec<_>>()
        .join(";")
}

fn ledger_with(text: &str, id: i64, status: &str, keep: usize) -> String {
    let mut entries = ledger_parse(text);
    entries.retain(|(known, _)| *known != id);
    entries.push((id, status.to_owned()));
    let excess = entries.len().saturating_sub(keep);
    entries.drain(..excess);
    ledger_format(&entries)
}

fn ledger_put(id: i64, status: &str) {
    let _lock = LEDGER_LOCK.lock().unwrap_or_else(|err| err.into_inner());
    let text = host::load(LEDGER_OPTION);
    host::store(LEDGER_OPTION, ledger_with(&text, id, status, LEDGER_KEPT));
}

fn ledger_status(id: i64) -> Option<String> {
    let _lock = LEDGER_LOCK.lock().unwrap_or_else(|err| err.into_inner());
    ledger_parse(&host::load(LEDGER_OPTION))
        .into_iter()
        .find(|(known, _)| *known == id)
        .map(|(_, status)| status)
}

/// The answer to a fleet.run the ledger knows but this process did not run
fn entry_from_ledger(id: i64, run_id: i64, status: &str) -> Value {
    if status == "running" {
        return entry(
            id,
            "error",
            json!({
                "run_id": run_id,
                "exit_code": null,
                "code": "interrupted",
                "output": "The NeoDesk client stopped while this task ran. It was not started again.",
            }),
        );
    }
    entry(
        id,
        status,
        json!({
            "run_id": run_id,
            "exit_code": null,
            "code": "result_lost",
            "output": "This task ran before the NeoDesk client restarted. Its output is gone.",
        }),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Waits until the result of command `id` is in the queue and takes it
    /// out, leaving the others.
    pub(crate) fn wait_result(id: i64, within: Duration) -> Option<Value> {
        let deadline = Instant::now() + within;
        while Instant::now() < deadline {
            {
                let mut state = state();
                if let Some(at) = state.queue.iter().position(|item| item["id"] == id) {
                    return state.queue.remove(at);
                }
            }
            std::thread::sleep(Duration::from_millis(20));
        }
        None
    }

    #[cfg(unix)]
    fn script_args(run_id: i64, script: &str) -> Value {
        json!({"run_id": run_id, "task_id": 1, "type": "script", "script": script, "timeout": 30})
    }

    #[cfg(windows)]
    fn script_args(run_id: i64, script: &str) -> Value {
        json!({"run_id": run_id, "task_id": 1, "type": "script", "script": script, "shell": "cmd", "timeout": 30})
    }

    /// A script that adds a line to `file` and takes a moment
    #[cfg(unix)]
    fn counting_script(file: &std::path::Path) -> String {
        format!("echo run >> '{}'; sleep 1", file.display())
    }

    #[cfg(windows)]
    fn counting_script(file: &std::path::Path) -> String {
        format!(
            "@echo run>> \"{}\"\r\n@ping -n 2 127.0.0.1 >nul",
            file.display()
        )
    }

    fn scratch_file(name: &str) -> std::path::PathBuf {
        let path = std::env::temp_dir().join(format!(
            "neodesk-fleet-test-{name}-{}",
            uuid::Uuid::new_v4()
        ));
        let _ = std::fs::remove_file(&path);
        path
    }

    fn lines(path: &std::path::Path) -> usize {
        std::fs::read_to_string(path)
            .map(|text| text.lines().filter(|line| !line.trim().is_empty()).count())
            .unwrap_or(0)
    }

    #[test]
    fn the_support_agent_refuses_every_fleet_command() {
        let file = scratch_file("refused");
        for (id, command) in [(700_001, RUN), (700_002, RESOURCES), (700_003, COMPLIANCE)] {
            let args = script_args(41, &counting_script(&file));
            let answer = accept(id, command, &args, true).expect("an answer");
            assert_eq!(answer["status"], "permission_denied", "{command}");
            assert_eq!(answer["result"]["code"], "support_agent_restricted");
            assert!(!state().is_running(id), "{command} started");
        }
        let answer = accept(700_001, RUN, &script_args(41, "true"), true).unwrap();
        assert_eq!(answer["result"]["run_id"], 41);
        std::thread::sleep(Duration::from_millis(1500));
        assert_eq!(lines(&file), 0, "a refused script ran");
        assert!(wait_result(700_001, Duration::from_millis(50)).is_none());
    }

    #[test]
    fn a_command_runs_once_however_often_it_comes() {
        let file = scratch_file("once");
        let args = script_args(42, &counting_script(&file));
        let first = accept(700_010, RUN, &args, false).expect("running");
        assert_eq!(first["status"], "running");
        assert_eq!(first["result"]["run_id"], 42);
        // Sent again while it runs: nothing new to say, nothing runs
        assert!(accept(700_010, RUN, &args, false).is_none());
        // Another command for the same run waits for the same result
        let second = accept(700_011, RUN, &args, false).expect("running");
        assert_eq!(second["status"], "running");

        let done = wait_result(700_010, Duration::from_secs(30)).expect("a result");
        assert_eq!(done["status"], "ok", "{done}");
        let other = wait_result(700_011, Duration::from_secs(5)).expect("a result");
        assert_eq!(other["result"], done["result"]);

        // Sent again after it finished: the same result, not a second run
        let again = accept(700_010, RUN, &args, false).expect("the result");
        assert_eq!(again["result"], done["result"]);
        std::thread::sleep(Duration::from_millis(300));
        assert_eq!(lines(&file), 1);
        let _ = std::fs::remove_file(&file);
    }

    #[test]
    fn a_run_the_ledger_knows_does_not_run_again() {
        let file = scratch_file("ledger");
        let args = script_args(43, &counting_script(&file));
        // As after a restart of the client in the middle of the task
        ledger_put(700_020, "running");
        let answer = accept(700_020, RUN, &args, false).expect("an answer");
        assert_eq!(answer["status"], "error");
        assert_eq!(answer["result"]["code"], "interrupted");
        assert_eq!(answer["result"]["run_id"], 43);

        ledger_put(700_021, "ok");
        let answer = accept(700_021, RUN, &args, false).expect("an answer");
        assert_eq!(answer["status"], "ok");
        assert_eq!(answer["result"]["code"], "result_lost");

        std::thread::sleep(Duration::from_millis(1500));
        assert_eq!(lines(&file), 0);
    }

    #[test]
    fn invalid_run_arguments_are_answered_at_once() {
        let answer = accept(
            700_030,
            RUN,
            &json!({"run_id": 44, "type": "teleport"}),
            false,
        )
        .unwrap();
        assert_eq!(answer["status"], "unsupported");
        assert_eq!(answer["result"]["run_id"], 44);
        assert_eq!(answer["result"]["code"], "unsupported_type");
        let answer = accept(
            700_031,
            RUN,
            &json!({"type": "script", "script": "true"}),
            false,
        )
        .unwrap();
        assert_eq!(answer["status"], "error");
        assert_eq!(answer["result"]["code"], "run_id_required");
        assert!(!state().is_running(700_030));
        assert!(ledger_status(700_030).is_none());
    }

    #[test]
    fn the_ledger_keeps_the_last_runs_with_their_status() {
        let mut text = String::new();
        for id in 1..=70 {
            text = ledger_with(&text, id, "running", LEDGER_KEPT);
        }
        let entries = ledger_parse(&text);
        assert_eq!(entries.len(), LEDGER_KEPT);
        assert_eq!(entries[0].0, 7);
        assert_eq!(entries.last().unwrap().0, 70);
        let text = ledger_with(&text, 30, "timeout", LEDGER_KEPT);
        let entries = ledger_parse(&text);
        assert_eq!(entries.len(), LEDGER_KEPT);
        assert_eq!(entries.last().unwrap(), &(30, "timeout".to_owned()));
        assert_eq!(entries.iter().filter(|(id, _)| *id == 30).count(), 1);
        assert!(ledger_parse("x:ok;-1:ok;5:;6:ok").len() == 1);
    }

    #[test]
    fn results_leave_within_the_budget_and_wait_after_a_failed_heartbeat() {
        let mut local = State::default();
        let body = "x".repeat(1000);
        for id in 1..=5 {
            local
                .queue
                .push_back(entry(id, "ok", json!({"output": body})));
        }
        let size = serde_json::to_string(&local.queue[0]).unwrap().len();
        let now = Instant::now();
        assert!(take_from(&mut local, 10, false, now).is_empty());
        let one = take_from(&mut local, 10, true, now);
        assert_eq!(one.len(), 1, "one result goes even over the budget");
        let two = take_from(&mut local, size * 2 + 10, false, now);
        assert_eq!(
            two.iter()
                .map(|r| r["id"].as_i64().unwrap())
                .collect::<Vec<_>>(),
            vec![2, 3]
        );

        // The heartbeat failed: they wait, then go first and in order
        requeue_into(&mut local, two, now);
        assert!(take_from(&mut local, usize::MAX, true, now).is_empty());
        assert!(take_from(&mut local, usize::MAX, true, now + RETRY_AFTER / 2).is_empty());
        let all = take_from(&mut local, usize::MAX, false, now + RETRY_AFTER);
        assert_eq!(
            all.iter()
                .map(|r| r["id"].as_i64().unwrap())
                .collect::<Vec<_>>(),
            vec![2, 3, 4, 5]
        );
        assert!(local.queue.is_empty());
    }
}
