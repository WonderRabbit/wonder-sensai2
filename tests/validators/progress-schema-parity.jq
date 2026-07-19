def issue($id; f):
  if (try f catch false) then [] else [$id] end;

def has_keys($required):
  type == "object" and (($required - keys) | length) == 0;

def allowed_keys($allowed):
  type == "object" and ((keys - $allowed) | length) == 0;

def nonempty_string:
  type == "string" and length > 0;

def unique_string_array:
  type == "array" and all(.[]; nonempty_string) and length == (unique | length);

def mission_slug_ok:
  type == "string" and test("^[a-z0-9]+(?:-[a-z0-9]+)*$");

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
    .gate == $gate and .verdict == "accepted" and
    .actor_role == "human" and .source == "elicited" and
    (.reason | nonempty_string) and (.receipt_sha256 | sha256_ok));

def progress_issues:
  . as $doc
  | issue("progress.type"; type == "object")
  + issue("progress.required";
      has_keys([
        "schema_version", "mission_id", "mission_root", "phase", "status",
        "revision", "todo_snapshot", "precondition_fingerprints", "next",
        "blocked", "unknowns", "approvals", "writer", "updated_at", "provenance"
      ]))
  + issue("progress.additional_properties";
      allowed_keys([
        "schema_version", "mission_id", "mission_root", "phase", "status",
        "revision", "todo_snapshot", "precondition_fingerprints", "next",
        "blocked", "unknowns", "approvals", "writer", "updated_at", "provenance"
      ]))
  + issue("progress.schema_version"; .schema_version == "1.0")
  + issue("progress.mission_id"; .mission_id | mission_slug_ok)
  + issue("progress.path";
      (.mission_root | safe_path_ok) and
      .mission_root == ("docs/analysis/missions/" + .mission_id + "/") and
      (.mission_root | test("^docs/analysis/missions/[a-z0-9]+(?:-[a-z0-9]+)*/$")))
  + issue("progress.phase"; .phase | IN("F0", "F1", "F2", "F3", "F4", "F5"))
  + issue("progress.status";
      (.status | IN("planned", "running", "blocked", "awaiting_human_approval", "completed")) and
      (.status != "planned" or .phase == "F0") and
      (.status != "awaiting_human_approval" or (.phase | IN("F0", "F3", "F5"))) and
      (.status != "completed" or .phase == "F5"))
  + issue("progress.revision";
      .revision | type == "number" and floor == . and . >= 1)
  + issue("progress.todo_snapshot";
      (.todo_snapshot | unique_string_array and length > 0))
  + issue("progress.precondition_shape";
      (.precondition_fingerprints |
        has_keys(["trace", "inputs"]) and
        allowed_keys(["trace", "inputs", "previous_progress", "git_head", "toolchain"])))
  + issue("progress.hash";
      (.precondition_fingerprints.trace | sha256_ok) and
      (.precondition_fingerprints.inputs | sha256_ok) and
      ((.precondition_fingerprints | has("previous_progress") | not) or
        (.precondition_fingerprints.previous_progress | sha256_ok)) and
      ((.precondition_fingerprints | has("toolchain") | not) or
        (.precondition_fingerprints.toolchain | sha256_ok)) and
      ((.precondition_fingerprints | has("git_head") | not) or
        (.precondition_fingerprints.git_head | type == "string" and test("^(?:UNBORN|[0-9a-f]{40})$"))))
  + issue("progress.next"; .next | nonempty_string)
  + issue("progress.blocked"; .blocked | unique_string_array)
  + issue("progress.unknowns"; .unknowns | unique_string_array)
  + issue("progress.approval_shape";
      (.approvals | type == "array") and
      all(.approvals[]?;
        has_keys([
          "gate", "verdict", "reason", "actor_role", "source", "receipt_path",
          "receipt_sha256", "recorded_at"
        ]) and
        allowed_keys([
          "gate", "verdict", "reason", "actor_role", "source", "receipt_path",
          "receipt_sha256", "recorded_at"
        ])))
  + issue("progress.approval_provenance";
      all(.approvals[]?;
        (.gate | IN("F0", "F3", "F5")) and
        (.verdict | IN("accepted", "rejected")) and
        (.reason | nonempty_string) and
        .actor_role == "human" and .source == "elicited" and
        (.receipt_sha256 | sha256_ok) and (.recorded_at | timestamp_ok)))
  + issue("progress.approval_path";
      all(.approvals[]?;
        (.receipt_path | safe_path_ok) and
        .receipt_path == ($doc.mission_root + "approvals/" + .gate + "-approval.json")))
  + issue("progress.approval_unique";
      [.approvals[]?.gate] | length == (unique | length))
  + issue("progress.hard_gate";
      .status != "completed" or accepted_human_approval($doc; "F5"))
  + issue("progress.writer"; .writer == "sensai-analysis-lead")
  + issue("progress.timestamp";
      (.updated_at | timestamp_ok) and all(.approvals[]?; .recorded_at <= $doc.updated_at))
  + issue("progress.provenance";
      (.provenance | type == "array" and length > 0) and
      all(.provenance[];
        has_keys(["path", "line", "path_line"]) and
        allowed_keys(["path", "line", "path_line"]) and
        (.path | safe_path_ok) and
        (.line | type == "number" and floor == . and . >= 1) and
        .path_line == (.path + ":" + (.line | tostring))));

def transition_issues:
  . as $env
  | $env.previous as $previous
  | $env.current as $current
  | ($previous.phase | phase_rank) as $previous_rank
  | ($current.phase | phase_rank) as $current_rank
  | issue("progress.transition_envelope";
      $env | has_keys(["previous", "current", "previous_sha256"]) and
      allowed_keys(["previous", "current", "previous_sha256"]) and
      ($env.previous_sha256 | sha256_ok))
  + issue("progress.identity";
      $current.mission_id == $previous.mission_id and
      $current.mission_root == $previous.mission_root and
      $current.writer == $previous.writer)
  + issue("progress.revision"; $current.revision == ($previous.revision + 1))
  + issue("progress.transition";
      ($previous.status != "completed") and
      ($previous_rank | type == "number") and ($current_rank | type == "number") and
      $current_rank >= $previous_rank and $current_rank <= ($previous_rank + 1))
  + issue("progress.precondition";
      ($current.precondition_fingerprints.previous_progress // "") == $env.previous_sha256)
  + issue("progress.approval_history";
      all($previous.approvals[]?; . as $approval | any($current.approvals[]?; . == $approval)))
  + issue("progress.timestamp_transition"; $current.updated_at > $previous.updated_at)
  + issue("progress.hard_gate";
      (($previous.phase != "F0" or $current.phase == "F0") or
        accepted_human_approval($current; "F0")) and
      (($previous.phase != "F3" or $current.phase == "F3") or
        accepted_human_approval($current; "F3")) and
      ($current.status != "completed" or accepted_human_approval($current; "F5")));

if type == "object" and has("previous") and has("current") then
  ((.previous | progress_issues) + (.current | progress_issues) + transition_issues) | unique
else
  progress_issues | unique
end
