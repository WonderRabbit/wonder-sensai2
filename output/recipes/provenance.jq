# trace 2.0과 산출 파일을 exact ID, 근거, source, kind로 역대조한다.
# 호출 계약: jq -e --arg mode <mode> --arg kind <asis|tobe>
#   --rawfile artifact <산출> --rawfile upstream <상위 산출 또는 빈 파일>
#   -f provenance.jq <trace.json>
def issue($id; condition):
  if (try condition catch false) then [] else [$id] end;

def canonical_entities($doc):
  $doc.conventions[]?,
  $doc.requirements[]?,
  $doc.frontends[]?,
  $doc.backends[]?,
  $doc.joins[]?,
  $doc.business_entities[]?,
  $doc.business_rules[]?,
  $doc.business_flows[]?,
  $doc.business_events[]?,
  $doc.business_states[]?,
  $doc.business_invariants[]?,
  $doc.extension_requirements[]?,
  $doc.designs[]?;

def all_ids($text):
  [
    $text
    | scan("(?:E-[A-Z0-9]+(?:-[A-Z0-9]+)*(?:-[0-9]{3})?|CONV-(?:COMPONENT|STRUCTURE|NAMING|API|STATE|ERROR|TEST)-[0-9]{3}|REQ-(?:EXT-[0-9]{4}|[0-9]{3,4})|FE-[0-9]{3}|BE-[0-9]{3}|J-[A-Z0-9]+-[0-9]{3}|BIZ-(?:ENT|RULE|FLOW|EVT|EVENT|STATE|INV|INVARIANT)-[0-9]{3}|DESIGN-(?:PAGE|SERVICE|API|ENTITY)-[0-9]{3}|STORY-(?:ASIS|TOBE)-[0-9]{3}|TEST-(?:ASIS|TOBE)-[0-9]{3}|DATA-(?:ASIS|TOBE)-[0-9]{3})")
  ];

def declared_sources($text):
  [
    $text
    | scan("(?m)^[[:space:]]*(?:%%[[:space:]]*)?provenance:[[:space:]]*`?([^`[:space:]\\n]+:[0-9]+)`?")
    | .[0]
  ];

def declared_kinds($text):
  [
    $text
    | scan("(?m)^[[:space:]]*(?:%%[[:space:]]*)?kind:[[:space:]]*(asis|tobe)[[:space:]]*$")
    | .[0]
  ];

def arrow_lines($text):
  [
    $text | split("\n")[]
    | gsub("^[[:space:]]+|[[:space:]]+$"; "")
    | select(test("(?:-->|->>|-->>|-.->)"))
  ];

def canonical_refs($text):
  [all_ids($text)[] | select(test("^(?:E-|STORY-|TEST-|DATA-)") | not)];

def evidence_refs($text):
  [all_ids($text)[] | select(startswith("E-"))];

def owned_refs($text):
  [all_ids($text)[] | select(test("^(?:STORY|TEST|DATA)-"))];

def allowed_ref($mode; $id):
  if $mode == "ui" then
    $id | test("^(?:CONV-|REQ-|DESIGN-)")
  elif $mode == "mermaid" then
    $id | test("^(?:BIZ-FLOW-|REQ-|DESIGN-)")
  elif $mode == "dataflow" then
    $id | test("^(?:BIZ-(?:FLOW|STATE|INVARIANT)-|DESIGN-)")
  elif $mode == "story" then
    $id | test("^(?:REQ-|BIZ-FLOW-|DESIGN-)")
  elif $mode == "test" then
    $id | test("^DESIGN-")
  else false
  end;

def expected_owned_prefix($mode; $kind):
  if $mode == "story" then "STORY-" + ($kind | ascii_upcase) + "-"
  elif $mode == "test" then "TEST-" + ($kind | ascii_upcase) + "-"
  else ""
  end;

def mermaid_header_ok($mode; $text):
  if $mode == "mermaid" then
    ([ $text | scan("(?m)^[[:space:]]*sequenceDiagram[[:space:]]*$") ] | length) == 1
  elif ($mode == "ui" or $mode == "dataflow") then
    ([ $text | scan("(?m)^[[:space:]]*flowchart[[:space:]]+(?:TB|TD|BT|RL|LR)[[:space:]]*$") ] | length) == 1
  else true
  end;

def related_evidence_ids($doc; $refs):
  [
    canonical_entities($doc) as $entity
    | select($refs | index($entity.id) != null)
    | $entity.evidence_ids[]?,
      ($entity.technical_ids[]? as $technical_id
        | canonical_entities($doc)
        | select(.id == $technical_id)
        | .evidence_ids[]?)
  ] | unique;

. as $doc
| declared_sources($artifact) as $sources
| declared_kinds($artifact) as $kinds
| canonical_refs($artifact) as $refs
| evidence_refs($artifact) as $evidence_ids
| owned_refs($artifact) as $owned_ids
| arrow_lines($artifact) as $arrows
| [canonical_entities($doc)] as $registry
| [$doc.evidence[]?] as $evidence_registry
| [$doc.provenance[]?] as $provenance_registry
| [all_ids($upstream)[] | select(startswith("STORY-"))] as $upstream_story_ids
| declared_kinds($upstream) as $upstream_kinds
| related_evidence_ids($doc; ($refs | unique)) as $related_evidence
| (
    issue("provenance.mode";
      $mode | IN("ui", "mermaid", "dataflow", "story", "test"))
    + issue("provenance.kind_mismatch";
      ($kind | IN("asis", "tobe"))
      and ($kinds == [$kind])
      and (if $mode == "test" then $upstream_kinds == [$kind] else true end))
    + issue("provenance.source_missing";
      ($sources | length) > 0
      and all($sources[]; . as $source | any($provenance_registry[]; .path_line == $source)))
    + issue("provenance.source_duplicate";
      ($sources | length) == 1
      and ($provenance_registry | map(select(.path_line == $sources[0])) | length) == 1)
    + issue("provenance.source_mismatch";
      ($sources | length) == 1
      and ($evidence_registry | map(select(.path_line == $sources[0] and .kind == $kind)) | length) == 1
      and (if $mode == "mermaid" then
        ($evidence_registry | map(select(.path_line == $sources[0]) | .id)[0]) as $source_evidence
        | $related_evidence | index($source_evidence) != null
      else true end))
    + issue("provenance.evidence_missing";
      all(($evidence_ids | unique)[]; . as $id | any($evidence_registry[]; .id == $id)))
    + issue("provenance.evidence_duplicate";
      ($evidence_ids | length) == ($evidence_ids | unique | length)
      and all(($evidence_ids | unique)[]; . as $id | ($evidence_registry | map(select(.id == $id)) | length) == 1))
    + issue("provenance.evidence_mismatch";
      all(($evidence_ids | unique)[]; . as $id
        | any($evidence_registry[]; . as $evidence
            | $evidence.id == $id and $evidence.kind == $kind
            and ($sources | index($evidence.path_line) != null))))
    + issue("provenance.id_missing";
      ($refs | length) > 0
      and (if ($mode == "story" or $mode == "test") then ($owned_ids | length) > 0 else true end)
      and (if $mode == "test" then
        ([all_ids($artifact)[] | select(startswith("STORY-"))] | length) > 0
      else true end))
    + issue("provenance.id_duplicate";
      all(($refs | unique)[]; . as $id | ($registry | map(select(.id == $id)) | length) == 1)
      and ($owned_ids | length) == ($owned_ids | unique | length)
      and (if $mode == "test" then
        ($upstream_story_ids | length) == ($upstream_story_ids | unique | length)
      else true end))
    + issue("provenance.id_mismatch";
      all(($refs | unique)[]; . as $id
        | allowed_ref($mode; $id)
        and any($registry[]; .id == $id))
      and (if $kind == "asis" then
        all(($refs | unique)[]; . as $id | any($registry[]; .id == $id and .kind == "asis"))
      else
        any(($refs | unique)[]; . as $id | any($registry[]; .id == $id and .kind == "tobe"))
        and all(($refs | unique)[]; . as $id | any($registry[]; .id == $id and (.kind | IN("asis", "tobe"))))
      end)
      and (if $mode == "story" then
        expected_owned_prefix($mode; $kind) as $prefix
        | ($owned_ids | length) > 0
        and all($owned_ids[]; startswith($prefix))
      elif $mode == "test" then
        expected_owned_prefix($mode; $kind) as $prefix
        | [all_ids($artifact)[] | select(startswith("TEST-"))] as $test_ids
        | ($test_ids | length) > 0
        and all($test_ids[]; startswith($prefix))
        and ([all_ids($artifact)[] | select(startswith("DATA-"))] | length) == 0
      else ($owned_ids | length) == 0 end)
      and (if $mode == "test" then
        [all_ids($artifact)[] | select(startswith("STORY-"))] as $story_refs
        | ($story_refs | unique | sort) == ($upstream_story_ids | unique | sort)
      else true end))
    + issue("provenance.mermaid_duplicate";
      mermaid_header_ok($mode; $artifact))
    + issue("provenance.arrow_missing";
      if ($mode | IN("ui", "mermaid", "dataflow")) then ($arrows | length) > 0 else true end)
    + issue("provenance.arrow_duplicate";
      if ($mode | IN("ui", "mermaid", "dataflow")) then
        ($arrows | length) == ($arrows | unique | length)
      else true end)
    + issue("provenance.arrow_mismatch";
      if ($mode | IN("mermaid", "dataflow")) then
        all($arrows[]; . as $arrow
          | [canonical_refs($arrow)[] | select(allowed_ref($mode; .))] | length > 0)
      else true end)
  )
| unique
| if length == 0 then true else error(join(",")) end
