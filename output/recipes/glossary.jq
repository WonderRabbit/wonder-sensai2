# `jq -s`로 trace 2.0과 glossary를 차례로 받아 용어의 직접 근거와 매핑을 검사한다.
def issue($id; condition):
  if (try condition catch false) then [] else [$id] end;

def nonempty_string:
  type == "string" and length > 0;

def nonempty_unique_strings:
  type == "array" and length > 0 and all(.[]; nonempty_string)
  and length == (unique | length);

def required_term_shape:
  type == "object"
  and ([
    "term_id", "term_ko", "term_canonical", "identifier_form", "definition_ko",
    "category", "evidence_ids", "maps_to", "status"
  ] - keys | length) == 0
  and (.term_id | test("^GLOSS-[0-9]{3}$"))
  and (.term_ko | nonempty_string)
  and (.term_canonical | nonempty_string)
  and (.definition_ko | nonempty_string)
  and (.category | nonempty_string)
  and (.status | IN("exact", "unresolved", "ambiguous", "many_to_many", "conflict"))
  and (.identifier_form | type == "object")
  and (.identifier_form | ["variable", "function", "class"] - keys | length == 0)
  and (.identifier_form | all(.variable, .function, .class; nonempty_string));

. as $inputs
| ($inputs[0] // null) as $trace
| ($inputs[1] // null) as $glossary
| (
    issue("glossary.input";
      ($inputs | type == "array" and length == 2)
      and ($trace | type == "object" and .schema_version == "2.0")
      and ($glossary | type == "object" and .schema_version == "1.0")
      and ($glossary.terms | type == "array")
      and ($glossary.provenance | type == "array"))
    + issue("glossary.shape";
      all($glossary.terms[]; required_term_shape))
    + issue("glossary.unique_ids";
      [$glossary.terms[].term_id] as $ids | $ids | length == (unique | length))
    + issue("glossary.direct_evidence";
      ($trace.evidence | map(.id)) as $evidence_ids
      | all($glossary.terms[];
          (.evidence_ids | nonempty_unique_strings)
          and all(.evidence_ids[]; IN($evidence_ids[]))))
    + issue("glossary.mapping";
      ([ $trace.business_entities[]?, ($trace.conventions[]? | select(.id | startswith("CONV-NAMING-"))) ] | map(.id)) as $targets
      | all($glossary.terms[];
          (.maps_to | nonempty_unique_strings)
          and all(.maps_to[]; IN($targets[]))))
  )
| unique
| if length == 0 then true else error(join(",")) end
