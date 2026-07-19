# trace 2.0의 스키마 외 참조·근거·결합 무결성을 검사한다.
def issue($id; condition):
  if (try condition catch false) then [] else [$id] end;

def nonempty_unique_strings:
  type == "array" and length > 0 and all(.[]; type == "string" and length > 0)
  and length == (unique | length);

def facts_with_evidence($doc):
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
  $doc.designs[]?,
  $doc.unsupported[]?;

def entities_with_ids($doc):
  $doc.evidence[]?,
  facts_with_evidence($doc),
  $doc.bindings[]?,
  $doc.unknowns[]?;

def stable_ids($doc):
  all($doc.evidence[]?; .id | test("^E-[A-Z0-9]+(?:-[A-Z0-9]+)*(?:-[0-9]{3})?$"))
  and all($doc.conventions[]?; .id | test("^CONV-(?:COMPONENT|STRUCTURE|NAMING|API|STATE|ERROR|TEST)-[0-9]{3}$"))
  and all($doc.requirements[]?; .id | test("^REQ-[0-9]{3,4}$"))
  and all($doc.frontends[]?; .id | test("^FE-[0-9]{3}$"))
  and all($doc.backends[]?; .id | test("^BE-[0-9]{3}$"))
  and all($doc.joins[]?; .id | test("^J-[A-Z0-9]+-[0-9]{3}$"))
  and all([
    $doc.business_entities[]?, $doc.business_rules[]?, $doc.business_flows[]?,
    $doc.business_events[]?, $doc.business_states[]?, $doc.business_invariants[]?
  ][]; .id | test("^BIZ-(?:ENT|RULE|FLOW|EVT|EVENT|STATE|INV|INVARIANT)-[0-9]{3}$"))
  and all($doc.extension_requirements[]?; .id | test("^REQ-EXT-[0-9]{4}$"))
  and all($doc.designs[]?; .id | test("^DESIGN-(?:PAGE|SERVICE|API|ENTITY)-[0-9]{3}$"))
  and all($doc.bindings[]?; .id | test("^BIND-[0-9]{3}$"))
  and all($doc.unknowns[]?; .id | test("^UNKNOWN-[0-9]{3}$"))
  and all($doc.unsupported[]?; .id | test("^UNSUPPORTED-[0-9]{3}$"));

def referenced_evidence_ids($doc):
  [facts_with_evidence($doc) | .evidence_ids[]?];

def business_facts($doc):
  [
    $doc.business_entities[]?, $doc.business_rules[]?, $doc.business_flows[]?,
    $doc.business_events[]?, $doc.business_states[]?, $doc.business_invariants[]?
  ];

. as $doc
| (
    issue("trace.recipe.schema_version";
      $doc | type == "object" and .schema_version == "2.0")
    + issue("trace.recipe.global_ids";
      [entities_with_ids($doc) | .id] as $ids
      | ($ids | all(.[]; type == "string" and length > 0))
        and ($ids | length == (unique | length))
        and stable_ids($doc))
    + issue("trace.recipe.direct_evidence";
      ($doc.evidence | type == "array")
      and ($doc.provenance | type == "array")
      and all(facts_with_evidence($doc); .evidence_ids | nonempty_unique_strings)
      and all($doc.evidence[]; . as $evidence
        | $evidence.path_line == ($evidence.path + ":" + ($evidence.line | tostring))
          and any($doc.provenance[]; .path_line == $evidence.path_line)))
    + issue("trace.recipe.reference_integrity";
      ($doc.evidence | map(.id)) as $evidence_ids
      | ($doc.frontends | map(.id)) as $frontend_ids
      | ($doc.backends | map(.id)) as $backend_ids
      | ($doc.conventions | map(.id)) as $convention_ids
      | (business_facts($doc) | map(.id)) as $business_ids
      | ($doc.extension_requirements | map(.id)) as $requirement_ids
      | ($doc.designs | map(.id)) as $design_ids
      | all(referenced_evidence_ids($doc)[]; IN($evidence_ids[]))
        and all($doc.joins[]?;
          (.frontend_id | IN($frontend_ids[])) and (.backend_id | IN($backend_ids[])))
        and all($doc.designs[]?;
          all(.requirement_ids[]; IN($requirement_ids[]))
          and all(.follows_convention_ids[]; IN($convention_ids[]))
          and all(.follows_business_ids[]; IN($business_ids[])))
        and all($doc.bindings[]?;
          (.design_id | IN($design_ids[]))
          and ((.convention_id? // null) as $id | $id == null or ($id | IN($convention_ids[])))
          and ((.business_id? // null) as $id | $id == null or ($id | IN($business_ids[])))))
    + issue("trace.recipe.exact_join";
      all($doc.joins[]? | select(.status == "exact"); . as $join
        | ($doc.frontends[] | select(.id == $join.frontend_id) | .evidence_ids) as $frontend_evidence
        | ($doc.backends[] | select(.id == $join.backend_id) | .evidence_ids) as $backend_evidence
        | ($join.evidence_ids - ($join.evidence_ids - $frontend_evidence) | length) > 0
          and ($join.evidence_ids - ($join.evidence_ids - $backend_evidence) | length) > 0))
    + issue("trace.recipe.mapping";
      ([ $doc.conventions[]?, $doc.frontends[]?, $doc.backends[]? ]) as $technical
      | all($doc.business_flows[]?;
          all(.technical_ids[]; . as $id | any($technical[]; .id == $id))
          and (.evidence_ids | nonempty_unique_strings)
          and all(.technical_ids[]; . as $id
            | any($technical[]; .id == $id and (.evidence_ids | nonempty_unique_strings)))))
    + issue("trace.recipe.binding";
      all($doc.bindings[]?; . as $binding
        | any($doc.designs[]; .id == $binding.design_id
          and ((($binding.convention_id? // null) == null)
            or (.follows_convention_ids | index($binding.convention_id) != null))
          and ((($binding.business_id? // null) == null)
            or (.follows_business_ids | index($binding.business_id) != null)))))
  )
| unique
| if length == 0 then true else error(join(",")) end
