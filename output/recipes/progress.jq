# progress 1.0의 문서, 전이, 재개 선행조건과 파생 상태를 검증한다.
# 입력 계약은 mode가 validate, transition, resume, status 중 하나인 객체다.
def issue($id; condition):
  if (try condition catch false) then [] else [$id] end;

def nonempty_string:
  type == "string" and length > 0;

def unique_string_array:
  type == "array" and all(.[]; nonempty_string) and length == (unique | length);

def exact_keys($required):
  type == "object" and keys == ($required | sort);

def sha256_ok:
  type == "string" and test("^[0-9a-f]{64}$");

def timestamp_ok:
  type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");

def safe_path_ok:
  nonempty_string and startswith("/") == false and test("(^|/)\\.\\.(/|$)") == false;

def phase_rank:
  {F0: 0, F1: 1, F2: 2, F3: 3, F4: 4, F5: 5}[.];

def accepted_human_approval($doc; $gate):
  any($doc.approvals[]?;
    .gate == $gate and .verdict == "accepted"
    and .actor_role == "human" and .source == "elicited"
    and (.reason | nonempty_string) and (.receipt_sha256 | sha256_ok));

def progress_issues($doc):
  issue("progress.type"; $doc | type == "object")
  + issue("progress.shape";
      $doc | exact_keys([
        "schema_version", "mission_id", "mission_root", "phase", "status",
        "revision", "todo_snapshot", "precondition_fingerprints", "next",
        "blocked", "unknowns", "approvals", "writer", "updated_at", "provenance"
      ]))
  + issue("progress.schema_version"; $doc.schema_version == "1.0")
  + issue("progress.mission_id";
      $doc.mission_id | type == "string" and test("^[a-z0-9]+(?:-[a-z0-9]+)*$"))
  + issue("progress.path";
      ($doc.mission_root | safe_path_ok)
      and $doc.mission_root == ("docs/analysis/missions/" + $doc.mission_id + "/"))
  + issue("progress.phase"; $doc.phase | IN("F0", "F1", "F2", "F3", "F4", "F5"))
  + issue("progress.status";
      ($doc.status | IN("planned", "running", "blocked", "awaiting_human_approval", "completed"))
      and ($doc.status != "planned" or $doc.phase == "F0")
      and ($doc.status != "awaiting_human_approval" or ($doc.phase | IN("F0", "F3", "F5")))
      and ($doc.status != "completed" or $doc.phase == "F5"))
  + issue("progress.revision";
      $doc.revision | type == "number" and floor == . and . >= 1)
  + issue("progress.todo_snapshot";
      $doc.todo_snapshot | unique_string_array and length > 0)
  + issue("progress.precondition_shape";
      ($doc.precondition_fingerprints | type == "object")
      and ($doc.precondition_fingerprints | keys - ["git_head", "inputs", "previous_progress", "toolchain", "trace"] | length) == 0
      and ($doc.precondition_fingerprints | has("trace") and has("inputs")))
  + issue("progress.hash";
      ($doc.precondition_fingerprints.trace | sha256_ok)
      and ($doc.precondition_fingerprints.inputs | sha256_ok)
      and (($doc.precondition_fingerprints.previous_progress? // null) == null
        or ($doc.precondition_fingerprints.previous_progress | sha256_ok))
      and (($doc.precondition_fingerprints.toolchain? // null) == null
        or ($doc.precondition_fingerprints.toolchain | sha256_ok))
      and (($doc.precondition_fingerprints.git_head? // null) == null
        or ($doc.precondition_fingerprints.git_head | type == "string" and test("^(?:UNBORN|[0-9a-f]{40})$"))))
  + issue("progress.next"; $doc.next | nonempty_string)
  + issue("progress.blocked"; $doc.blocked | unique_string_array)
  + issue("progress.unknowns"; $doc.unknowns | unique_string_array)
  + issue("progress.approval_shape";
      ($doc.approvals | type == "array")
      and all($doc.approvals[]?;
        exact_keys([
          "gate", "verdict", "reason", "actor_role", "source", "receipt_path",
          "receipt_sha256", "recorded_at"
        ])))
  + issue("progress.approval";
      all($doc.approvals[]?;
        (.gate | IN("F0", "F3", "F5"))
        and (.verdict | IN("accepted", "rejected"))
        and (.reason | nonempty_string)
        and .actor_role == "human" and .source == "elicited"
        and (.receipt_path | safe_path_ok)
        and .receipt_path == ($doc.mission_root + "approvals/" + .gate + "-approval.json")
        and (.receipt_sha256 | sha256_ok) and (.recorded_at | timestamp_ok)))
  + issue("progress.approval_unique";
      [$doc.approvals[]?.gate] | length == (unique | length))
  + issue("progress.hard_gate";
      $doc.status != "completed" or accepted_human_approval($doc; "F5"))
  + issue("progress.writer"; $doc.writer == "sensai-analysis-lead")
  + issue("progress.timestamp";
      ($doc.updated_at | timestamp_ok)
      and all($doc.approvals[]?; .recorded_at <= $doc.updated_at))
  + issue("progress.provenance";
      ($doc.provenance | type == "array" and length > 0)
      and all($doc.provenance[]?;
        exact_keys(["path", "line", "path_line"])
        and (.path | safe_path_ok)
        and (.line | type == "number" and floor == . and . >= 1)
        and .path_line == (.path + ":" + (.line | tostring))));

def observed_shape_ok($observed):
  ($observed | type == "object")
  and ($observed | keys - ["git_head", "inputs", "toolchain", "trace"] | length) == 0
  and ($observed | has("trace") and has("inputs"))
  and ($observed.trace | sha256_ok)
  and ($observed.inputs | sha256_ok)
  and (($observed.toolchain? // null) == null or ($observed.toolchain | sha256_ok))
  and (($observed.git_head? // null) == null
    or ($observed.git_head | type == "string" and test("^(?:UNBORN|[0-9a-f]{40})$")));

def fingerprint_matches($progress; $observed; $name):
  if ($progress.precondition_fingerprints | has($name))
  then ($observed | has($name)) and $observed[$name] == $progress.precondition_fingerprints[$name]
  else ($observed | has($name) | not)
  end;

def transition_issues($envelope):
  ($envelope.previous.phase | phase_rank) as $previous_rank
  | ($envelope.current.phase | phase_rank) as $current_rank
  | progress_issues($envelope.previous)
  + progress_issues($envelope.current)
  + issue("progress.transition.shape";
      $envelope | exact_keys([
        "mode", "previous", "current", "previous_sha256",
        "active_progress_sha256", "observed_fingerprints"
      ]))
  + issue("progress.transition.previous_hash"; $envelope.previous_sha256 | sha256_ok)
  + issue("progress.transition.stale_hash";
      $envelope.active_progress_sha256 == $envelope.previous_sha256)
  + issue("progress.identity";
      $envelope.current.mission_id == $envelope.previous.mission_id
      and $envelope.current.mission_root == $envelope.previous.mission_root
      and $envelope.current.writer == $envelope.previous.writer)
  + issue("progress.transition.revision";
      $envelope.current.revision == ($envelope.previous.revision + 1))
  + issue("progress.transition.phase";
      $envelope.previous.status != "completed"
      and ($previous_rank | type == "number") and ($current_rank | type == "number")
      and $current_rank >= $previous_rank and $current_rank <= ($previous_rank + 1))
  + issue("progress.transition.precondition";
      ($envelope.current.precondition_fingerprints.previous_progress // "") == $envelope.previous_sha256)
  + issue("progress.transition.observed_shape";
      observed_shape_ok($envelope.observed_fingerprints))
  + issue("progress.transition.precondition_trace";
      fingerprint_matches($envelope.current; $envelope.observed_fingerprints; "trace"))
  + issue("progress.transition.precondition_inputs";
      fingerprint_matches($envelope.current; $envelope.observed_fingerprints; "inputs"))
  + issue("progress.transition.precondition_git_head";
      fingerprint_matches($envelope.current; $envelope.observed_fingerprints; "git_head"))
  + issue("progress.transition.precondition_toolchain";
      fingerprint_matches($envelope.current; $envelope.observed_fingerprints; "toolchain"))
  + issue("progress.transition.approval_history";
      all($envelope.previous.approvals[]?; . as $approval
        | any($envelope.current.approvals[]?; . == $approval)))
  + issue("progress.transition.timestamp";
      $envelope.current.updated_at > $envelope.previous.updated_at)
  + issue("progress.transition.hard_gate";
      (($envelope.previous.phase != "F0" or $envelope.current.phase == "F0")
        or accepted_human_approval($envelope.current; "F0"))
      and (($envelope.previous.phase != "F3" or $envelope.current.phase == "F3")
        or accepted_human_approval($envelope.current; "F3"))
      and ($envelope.current.status != "completed"
        or accepted_human_approval($envelope.current; "F5")));

def resume_issues($envelope):
  progress_issues($envelope.progress)
  + issue("progress.resume.shape";
      $envelope | exact_keys([
        "mode", "progress", "progress_sha256", "active_progress_sha256",
        "expected_revision", "observed_fingerprints", "lock"
      ]))
  + issue("progress.resume.hash_shape"; $envelope.progress_sha256 | sha256_ok)
  + issue("progress.resume.stale_hash";
      $envelope.active_progress_sha256 == $envelope.progress_sha256)
  + issue("progress.resume.stale_revision";
      $envelope.expected_revision == $envelope.progress.revision)
  + issue("progress.resume.observed_shape";
      observed_shape_ok($envelope.observed_fingerprints))
  + issue("progress.resume.precondition_trace";
      fingerprint_matches($envelope.progress; $envelope.observed_fingerprints; "trace"))
  + issue("progress.resume.precondition_inputs";
      fingerprint_matches($envelope.progress; $envelope.observed_fingerprints; "inputs"))
  + issue("progress.resume.precondition_git_head";
      fingerprint_matches($envelope.progress; $envelope.observed_fingerprints; "git_head"))
  + issue("progress.resume.precondition_toolchain";
      fingerprint_matches($envelope.progress; $envelope.observed_fingerprints; "toolchain"))
  + issue("progress.resume.lock_shape";
      $envelope.lock | exact_keys([
        "mission_id", "owner", "base_revision", "base_progress_sha256", "exclusive"
      ]))
  + issue("progress.resume.concurrent";
      $envelope.lock.exclusive == true and ($envelope.lock.owner | nonempty_string))
  + issue("progress.resume.lock_identity";
      $envelope.lock.mission_id == $envelope.progress.mission_id)
  + issue("progress.resume.double_resume";
      $envelope.lock.base_revision == $envelope.progress.revision
      and $envelope.lock.base_progress_sha256 == $envelope.progress_sha256)
  + issue("progress.resume.terminal"; $envelope.progress.status != "completed");

def clean_text:
  tostring | gsub("[\\r\\n\\t]"; " ") | gsub("`"; "'");

def bullet_lines($items):
  if ($items | length) == 0 then "- 없음"
  else ($items | map("- " + (clean_text)) | join("\n"))
  end;

def progress_percent($doc):
  if $doc.status == "completed" then 100
  else {F0: 0, F1: 20, F2: 40, F3: 60, F4: 80, F5: 90}[$doc.phase]
  end;

def render_status($doc):
  "# 미션 상태: " + ($doc.mission_id | clean_text) + "\n\n"
  + "- phase: `" + $doc.phase + "`\n"
  + "- status: `" + $doc.status + "`\n"
  + "- progress: `" + (progress_percent($doc) | tostring) + "%`\n"
  + "- revision: `" + ($doc.revision | tostring) + "`\n"
  + "- trace: `" + $doc.mission_root + "trace.json`\n"
  + "- progress: `" + $doc.mission_root + "progress.json`\n\n"
  + "## 차단 항목\n\n" + bullet_lines($doc.blocked) + "\n\n"
  + "## 미확인 항목\n\n" + bullet_lines($doc.unknowns) + "\n\n"
  + "## 다음 작업\n\n- " + ($doc.next | clean_text) + "\n\n"
  + "## todo snapshot\n\n" + bullet_lines($doc.todo_snapshot) + "\n";

def resume_projection($doc):
  {
    mission_id: $doc.mission_id,
    mission_root: $doc.mission_root,
    phase: $doc.phase,
    status: $doc.status,
    revision: $doc.revision,
    next: $doc.next,
    blocked: $doc.blocked,
    unknowns: $doc.unknowns,
    todo_snapshot: $doc.todo_snapshot,
    todo: [
      range(0; $doc.todo_snapshot | length) as $index
      | {
          content: $doc.todo_snapshot[$index],
          status: (if $index == 0 then "in_progress" else "pending" end),
          priority: "high"
        }
    ],
    pointers: {
      trace: ($doc.mission_root + "trace.json"),
      progress: ($doc.mission_root + "progress.json"),
      status: ($doc.mission_root + "status.md")
    }
  };

. as $envelope
| if $envelope.mode == "validate" then
    progress_issues($envelope.progress) as $issues
    | if ($issues | length) == 0 then true else error($issues | unique | join(",")) end
  elif $envelope.mode == "transition" then
    transition_issues($envelope) as $issues
    | if ($issues | length) == 0 then true else error($issues | unique | join(",")) end
  elif $envelope.mode == "resume" then
    resume_issues($envelope) as $issues
    | if ($issues | length) == 0 then resume_projection($envelope.progress)
      else error($issues | unique | join(",")) end
  elif $envelope.mode == "status" then
    progress_issues($envelope.progress) as $issues
    | if ($issues | length) == 0 then render_status($envelope.progress)
      else error($issues | unique | join(",")) end
  else error("progress.mode")
  end
