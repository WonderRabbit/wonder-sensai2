# 1.0 원장의 기존 값을 보존하면서 추론 가능한 버전과 kind만 추가한다.
def nonempty_string:
  type == "string" and length > 0;

def path_line:
  type == "string" and test("^(?!/)(?!.*(?:^|/)\\.\\.(?:/|$)).+:[1-9][0-9]*$");

def valid_v1:
  type == "object"
  and .schema_version == "1.0"
  and ((keys - ["schema_version", "requirements", "frontends", "backends", "provenance"]) | length == 0)
  and (.requirements | type == "array")
  and (.frontends | type == "array")
  and (.backends | type == "array")
  and (.provenance | type == "array")
  and all(.requirements[];
    ((keys - ["id", "statement", "evidence"]) | length == 0)
    and (.id | test("^REQ-[0-9]{3,4}$")) and (.statement | nonempty_string) and (.evidence | path_line))
  and all(.frontends[];
    ((keys - ["id", "route", "evidence"]) | length == 0)
    and (.id | test("^FE-[0-9]{3}$")) and (.route | nonempty_string) and (.evidence | path_line))
  and all(.backends[];
    ((keys - ["id", "method", "route", "evidence"]) | length == 0)
    and (.id | test("^BE-[0-9]{3}$")) and (.method | IN("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"))
    and (.route | nonempty_string) and (.evidence | path_line))
  and all(.provenance[];
    ((keys - ["path", "line", "path_line"]) | length == 0)
    and (.path | nonempty_string) and (.line | type == "number" and floor == . and . >= 1)
    and .path_line == (.path + ":" + (.line | tostring)))
  and ([.requirements[].id, .frontends[].id, .backends[].id] as $ids
    | $ids | length == (unique | length));

def add_asis_kind:
  map(. + {kind: "asis"});

if .schema_version == "2.0" then
  .
elif valid_v1 then
  .schema_version = "2.0"
  | .requirements |= add_asis_kind
  | .frontends |= add_asis_kind
  | .backends |= add_asis_kind
  | . + {
      evidence: (.evidence // []),
      conventions: (.conventions // []),
      joins: (.joins // []),
      business_entities: (.business_entities // []),
      business_rules: (.business_rules // []),
      business_flows: (.business_flows // []),
      business_events: (.business_events // []),
      business_states: (.business_states // []),
      business_invariants: (.business_invariants // []),
      extension_requirements: (.extension_requirements // []),
      designs: (.designs // []),
      bindings: (.bindings // []),
      unknowns: (.unknowns // []),
      unsupported: (.unsupported // [])
    }
else
  error("migration.invalid_v1")
end
