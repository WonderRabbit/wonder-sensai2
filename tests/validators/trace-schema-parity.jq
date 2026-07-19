def issue($id; f):
  if (try f catch false) then [] else [$id] end;

def has_keys($required):
  type == "object" and (($required - keys) | length) == 0;

def allowed_keys($allowed):
  type == "object" and ((keys - $allowed) | length) == 0;

def nonempty_string:
  type == "string" and length > 0;

def nonempty_unique_strings:
  type == "array" and length > 0 and all(.[]; nonempty_string) and length == (unique | length);

def array_all($name; f):
  .[$name] | type == "array" and all(.[]; f);

def optional_array_all($name; f):
  (has($name) | not) or (.[$name] | type == "array" and all(.[]; f));

def shape($name; $required; $allowed):
  (.[$name] | type != "array") or array_all($name; allowed_keys($allowed));

def optional_shape($name; $required; $allowed):
  (has($name) | not) or (.[$name] | type != "array") or
  array_all($name; allowed_keys($allowed));

def required_shape($name; $required):
  (.[$name] | type != "array") or array_all($name; has_keys($required));

def optional_required_shape($name; $required):
  (has($name) | not) or (.[$name] | type != "array") or
  array_all($name; has_keys($required));

def path_ok:
  nonempty_string and startswith("/") == false and test("(^|/)\\.\\.(/|$)") == false;

def status_ok:
  type == "string" and IN("exact", "unresolved", "ambiguous", "many_to_many", "conflict");

def uncertain_status_ok:
  type == "string" and IN("unresolved", "ambiguous", "many_to_many", "conflict");

def evidence_id_ok:
  type == "string" and test("^E-[A-Z0-9]+(?:-[A-Z0-9]+)*(?:-[0-9]{3})?$");

def evidence_ids_ok:
  nonempty_unique_strings and all(.[]; evidence_id_ok);

def all_entity_ids($doc):
  [
    $doc.evidence[],
    $doc.conventions[],
    $doc.requirements[],
    $doc.frontends[],
    $doc.backends[],
    ($doc.joins // [])[],
    $doc.business_entities[],
    $doc.business_rules[],
    $doc.business_flows[],
    $doc.business_events[],
    $doc.business_states[],
    $doc.business_invariants[],
    $doc.extension_requirements[],
    $doc.designs[],
    $doc.bindings[],
    $doc.unknowns[],
    $doc.unsupported[]
    | .id
  ];

def all_evidence_references($doc):
  [
    $doc.conventions[],
    $doc.requirements[],
    $doc.frontends[],
    $doc.backends[],
    ($doc.joins // [])[],
    $doc.business_entities[],
    $doc.business_rules[],
    $doc.business_flows[],
    $doc.business_events[],
    $doc.business_states[],
    $doc.business_invariants[],
    $doc.extension_requirements[],
    $doc.designs[],
    $doc.unsupported[]
    | .evidence_ids[]
  ];

. as $doc
| issue("trace.type"; type == "object")
+ issue("trace.required";
    has_keys([
      "schema_version", "mission_id", "evidence", "conventions", "requirements",
      "frontends", "backends", "business_entities", "business_rules", "business_flows",
      "business_events", "business_states", "business_invariants", "extension_requirements",
      "designs", "bindings", "unknowns", "unsupported", "provenance"
    ])
    and required_shape("evidence"; ["id", "kind", "path", "line", "path_line"])
    and required_shape("conventions";
      ["id", "kind", "category", "statement_ko", "examples", "evidence_ids", "status", "extractor"])
    and required_shape("requirements";
      ["id", "kind", "statement_ko", "keyword", "evidence_ids", "status"])
    and required_shape("frontends"; ["id", "kind", "route", "evidence_ids", "status"])
    and required_shape("backends"; ["id", "kind", "method", "route", "evidence_ids", "status"])
    and optional_required_shape("joins";
      ["id", "kind", "frontend_id", "backend_id", "evidence_ids", "status"])
    and required_shape("business_entities";
      ["id", "kind", "category", "statement_ko", "identifiers", "evidence_ids", "status"])
    and required_shape("business_rules";
      ["id", "kind", "category", "statement_ko", "evidence_ids", "status"])
    and required_shape("business_flows";
      ["id", "kind", "category", "statement_ko", "evidence_ids", "technical_ids", "status"])
    and required_shape("business_events";
      ["id", "kind", "category", "statement_ko", "evidence_ids", "status"])
    and required_shape("business_states";
      ["id", "kind", "category", "statement_ko", "evidence_ids", "status"])
    and required_shape("business_invariants";
      ["id", "kind", "category", "statement_ko", "evidence_ids", "status"])
    and required_shape("extension_requirements";
      ["id", "kind", "source", "keyword", "statement_ko", "evidence_ids", "status"])
    and required_shape("designs";
      ["id", "kind", "type", "statement_ko", "requirement_ids", "follows_convention_ids", "follows_business_ids", "evidence_ids", "status"])
    and required_shape("bindings"; ["id", "design_id", "gate"])
    and required_shape("unknowns"; ["id", "statement_ko", "status"])
    and required_shape("unsupported"; ["id", "kind", "statement_ko", "evidence_ids", "status"])
    and required_shape("provenance"; ["path", "line", "path_line"])
    and ((has("glossary_ref") | not) or (.glossary_ref | has_keys(["path", "sha256"]))))
+ issue("trace.additional_properties";
    allowed_keys([
      "schema_version", "mission_id", "glossary_ref", "evidence", "conventions",
      "requirements", "frontends", "backends", "joins", "business_entities",
      "business_rules", "business_flows", "business_events", "business_states",
      "business_invariants", "extension_requirements", "designs", "bindings",
      "unknowns", "unsupported", "provenance"
    ])
    and shape("evidence"; ["id", "kind", "path", "line", "path_line"];
      ["id", "kind", "path", "line", "path_line"])
    and shape("conventions";
      ["id", "kind", "category", "statement_ko", "examples", "evidence_ids", "status", "extractor"];
      ["id", "kind", "category", "statement_ko", "examples", "evidence_ids", "status", "extractor"])
    and shape("requirements"; ["id", "kind", "statement_ko", "keyword", "evidence_ids", "status"];
      ["id", "kind", "statement", "statement_ko", "keyword", "evidence", "evidence_ids", "status"])
    and shape("frontends"; ["id", "kind", "route", "evidence_ids", "status"];
      ["id", "kind", "route", "evidence", "evidence_ids", "status"])
    and shape("backends"; ["id", "kind", "method", "route", "evidence_ids", "status"];
      ["id", "kind", "method", "route", "evidence", "evidence_ids", "status"])
    and optional_shape("joins"; ["id", "kind", "frontend_id", "backend_id", "evidence_ids", "status"];
      ["id", "kind", "frontend_id", "backend_id", "evidence_ids", "status"])
    and shape("business_entities";
      ["id", "kind", "category", "statement_ko", "identifiers", "evidence_ids", "status"];
      ["id", "kind", "category", "statement_ko", "identifiers", "evidence_ids", "status"])
    and shape("business_rules"; ["id", "kind", "category", "statement_ko", "evidence_ids", "status"];
      ["id", "kind", "category", "statement_ko", "evidence_ids", "status"])
    and shape("business_flows";
      ["id", "kind", "category", "statement_ko", "evidence_ids", "technical_ids", "status"];
      ["id", "kind", "category", "statement_ko", "evidence_ids", "technical_ids", "status"])
    and shape("business_events"; ["id", "kind", "category", "statement_ko", "evidence_ids", "status"];
      ["id", "kind", "category", "statement_ko", "evidence_ids", "status"])
    and shape("business_states"; ["id", "kind", "category", "statement_ko", "evidence_ids", "status"];
      ["id", "kind", "category", "statement_ko", "evidence_ids", "status"])
    and shape("business_invariants"; ["id", "kind", "category", "statement_ko", "evidence_ids", "status"];
      ["id", "kind", "category", "statement_ko", "evidence_ids", "status"])
    and shape("extension_requirements";
      ["id", "kind", "source", "keyword", "statement_ko", "evidence_ids", "status"];
      ["id", "kind", "source", "keyword", "statement_ko", "evidence_ids", "status"])
    and shape("designs";
      ["id", "kind", "type", "statement_ko", "requirement_ids", "follows_convention_ids", "follows_business_ids", "evidence_ids", "status"];
      ["id", "kind", "type", "statement_ko", "requirement_ids", "follows_convention_ids", "follows_business_ids", "evidence_ids", "status"])
    and shape("bindings"; ["id", "design_id", "gate"];
      ["id", "design_id", "convention_id", "business_id", "gate"])
    and shape("unknowns"; ["id", "statement_ko", "status"];
      ["id", "statement_ko", "status"])
    and shape("unsupported"; ["id", "kind", "statement_ko", "evidence_ids", "status"];
      ["id", "kind", "statement_ko", "evidence_ids", "status"])
    and shape("provenance"; ["path", "line", "path_line"];
      ["path", "line", "path_line"])
    and ((has("glossary_ref") | not) or
      (.glossary_ref | has_keys(["path", "sha256"]) and allowed_keys(["path", "sha256"]))))
+ issue("trace.schema_version"; .schema_version == "2.0")
+ issue("trace.mission_id";
    .mission_id | nonempty_string and test("^[a-z0-9]+(?:-[a-z0-9]+)*$"))
+ issue("trace.array_type";
    all([
      "evidence", "conventions", "requirements", "frontends", "backends",
      "business_entities", "business_rules", "business_flows", "business_events",
      "business_states", "business_invariants", "extension_requirements", "designs",
      "bindings", "unknowns", "unsupported", "provenance"
    ][]; $doc[.] | type == "array")
    and (($doc | has("joins") | not) or ($doc.joins | type == "array")))
+ issue("trace.nonempty";
    array_all("conventions"; .statement_ko | nonempty_string)
    and array_all("requirements"; .statement_ko | nonempty_string)
    and array_all("frontends"; .route | nonempty_string)
    and array_all("backends"; .route | nonempty_string)
    and array_all("business_entities"; .statement_ko | nonempty_string)
    and array_all("business_rules"; .statement_ko | nonempty_string)
    and array_all("business_flows"; .statement_ko | nonempty_string)
    and array_all("business_events"; .statement_ko | nonempty_string)
    and array_all("business_states"; .statement_ko | nonempty_string)
    and array_all("business_invariants"; .statement_ko | nonempty_string)
    and array_all("extension_requirements"; .statement_ko | nonempty_string)
    and array_all("designs"; .statement_ko | nonempty_string)
    and array_all("unknowns"; .statement_ko | nonempty_string)
    and array_all("conventions"; .examples | nonempty_unique_strings)
    and array_all("business_entities"; .identifiers | nonempty_unique_strings)
    and array_all("business_flows"; .technical_ids | nonempty_unique_strings)
    and array_all("designs";
      (.requirement_ids | nonempty_unique_strings)
      and (.follows_convention_ids | nonempty_unique_strings)
      and (.follows_business_ids | nonempty_unique_strings))
    and all([
      "conventions", "requirements", "frontends", "backends", "business_entities",
      "business_rules", "business_flows", "business_events", "business_states",
      "business_invariants", "extension_requirements", "designs", "unsupported"
    ][]; . as $name | $doc | array_all($name; .evidence_ids | evidence_ids_ok))
    and optional_array_all("joins"; .evidence_ids | evidence_ids_ok))
+ issue("trace.kind";
    array_all("evidence"; .kind | IN("asis", "tobe"))
    and all([
      "conventions", "requirements", "frontends", "backends", "business_entities",
      "business_rules", "business_flows", "business_events", "business_states",
      "business_invariants", "unsupported"
    ][]; . as $name | $doc | array_all($name; .kind == "asis"))
    and optional_array_all("joins"; .kind == "asis")
    and all(["extension_requirements", "designs"][];
      . as $name | $doc | array_all($name; .kind == "tobe")))
+ issue("trace.status";
    all([
      "conventions", "requirements", "frontends", "backends", "business_entities",
      "business_rules", "business_flows", "business_events", "business_states",
      "business_invariants", "extension_requirements", "designs"
    ][]; . as $name | $doc | array_all($name; .status | status_ok))
    and optional_array_all("joins"; .status | status_ok)
    and array_all("unknowns"; .status | uncertain_status_ok)
    and array_all("unsupported"; .status | uncertain_status_ok))
+ issue("trace.convention_category";
    array_all("conventions";
      .category | IN("COMPONENT", "STRUCTURE", "NAMING", "API", "STATE", "ERROR", "TEST")))
+ issue("trace.business_category";
    array_all("business_entities"; .category == "business_entity")
    and array_all("business_rules"; .category == "business_rule")
    and array_all("business_flows"; .category == "business_flow")
    and array_all("business_events"; .category == "business_event")
    and array_all("business_states"; .category == "business_state")
    and array_all("business_invariants"; .category == "business_invariant"))
+ issue("trace.id_pattern";
    array_all("evidence"; .id | evidence_id_ok)
    and array_all("conventions"; .id | test("^CONV-(?:COMPONENT|STRUCTURE|NAMING|API|STATE|ERROR|TEST)-[0-9]{3}$"))
    and array_all("requirements"; .id | test("^REQ-[0-9]{3,4}$"))
    and array_all("frontends"; .id | test("^FE-[0-9]{3}$"))
    and array_all("backends"; .id | test("^BE-[0-9]{3}$"))
    and optional_array_all("joins"; .id | test("^J-[A-Z0-9]+-[0-9]{3}$"))
    and array_all("business_entities"; .id | test("^BIZ-ENT-[0-9]{3}$"))
    and array_all("business_rules"; .id | test("^BIZ-RULE-[0-9]{3}$"))
    and array_all("business_flows"; .id | test("^BIZ-FLOW-[0-9]{3}$"))
    and array_all("business_events"; .id | test("^BIZ-(?:EVT|EVENT)-[0-9]{3}$"))
    and array_all("business_states"; .id | test("^BIZ-STATE-[0-9]{3}$"))
    and array_all("business_invariants"; .id | test("^BIZ-(?:INV|INVARIANT)-[0-9]{3}$"))
    and array_all("extension_requirements"; .id | test("^REQ-EXT-[0-9]{4}$"))
    and array_all("designs"; .id | test("^DESIGN-(?:PAGE|SERVICE|API|ENTITY)-[0-9]{3}$"))
    and array_all("bindings"; .id | test("^BIND-[0-9]{3}$"))
    and array_all("unknowns"; .id | test("^UNKNOWN-[0-9]{3}$"))
    and array_all("unsupported"; .id | test("^UNSUPPORTED-[0-9]{3}$")))
+ issue("trace.enum";
    array_all("requirements"; .keyword | IN("MUST", "SHOULD", "MAY"))
    and array_all("extension_requirements";
      (.keyword | IN("MUST", "SHOULD", "MAY"))
      and (.source | IN("user", "elicited", "inferred")))
    and array_all("backends"; .method | IN("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"))
    and array_all("designs"; .type | IN("page", "service", "api", "entity"))
    and array_all("bindings"; .gate | IN("pass", "violation")))
+ issue("trace.binding";
    array_all("bindings";
      ((has("convention_id") and (has("business_id") | not)) or
       (has("business_id") and (has("convention_id") | not))))
    and all($doc.designs[]; .id as $design_id | any($doc.bindings[]; .design_id == $design_id)))
+ issue("trace.path_line";
    array_all("evidence";
      (.path | path_ok) and (.line | type == "number" and floor == . and . >= 1)
      and .path_line == (.path + ":" + (.line | tostring)))
    and array_all("provenance";
      (.path | path_ok) and (.line | type == "number" and floor == . and . >= 1)
      and .path_line == (.path + ":" + (.line | tostring))))
+ issue("trace.glossary_ref";
    (has("glossary_ref") | not) or
    (.glossary_ref.path | path_ok) and
    (.glossary_ref.sha256 | type == "string" and test("^[0-9a-f]{64}$")))
+ issue("trace.unique_ids";
    all_entity_ids($doc) | length == (unique | length))
+ issue("trace.reference_integrity";
    ($doc.evidence | map(.id)) as $evidence_ids
    | ($doc.frontends | map(.id)) as $frontend_ids
    | ($doc.backends | map(.id)) as $backend_ids
    | ($doc.conventions | map(.id)) as $convention_ids
    | ([
        $doc.business_entities[], $doc.business_rules[], $doc.business_flows[],
        $doc.business_events[], $doc.business_states[], $doc.business_invariants[]
      ] | map(.id)) as $business_ids
    | ($doc.extension_requirements | map(.id)) as $requirement_ids
    | ($doc.designs | map(.id)) as $design_ids
    | all(all_evidence_references($doc)[]; IN($evidence_ids[]))
      and all(($doc.joins // [])[];
        (.frontend_id | IN($frontend_ids[])) and (.backend_id | IN($backend_ids[])))
      and all($doc.designs[];
        all(.requirement_ids[]; IN($requirement_ids[]))
        and all(.follows_convention_ids[]; IN($convention_ids[]))
        and all(.follows_business_ids[]; IN($business_ids[])))
      and all($doc.bindings[];
        (.design_id | IN($design_ids[]))
        and ((.convention_id? // null) as $id | $id == null or ($id | IN($convention_ids[])))
        and ((.business_id? // null) as $id | $id == null or ($id | IN($business_ids[])))))
| unique
