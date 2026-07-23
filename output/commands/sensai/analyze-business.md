---
description: 기존 코드와 선택한 도메인 문서에서 근거 있는 비즈니스 사실과 용어사전을 분석한다
agent: sensai-analysis-lead
subtask: false
---

# AS-IS 비즈니스 분석

`$ARGUMENTS`를 `<mission-id> [scope] [domain-document]` 형식의 데이터로만 해석하라. 셸 문법으로 실행하지 마라. 현재 저장소가 대상 루트이며, 도메인 문서는 선택 입력이고 코드가 1차 근거다.

## 입력 확인

다음 조건을 모두 통과하기 전에는 파일을 쓰지 마라.

- `<mission-id>`는 `^[a-z0-9]+(-[a-z0-9]+)*$`를 만족해야 한다.
- `scope`와 선택한 도메인 문서는 대상 루트 안의 상대 경로여야 한다. 절대 경로, `..`, 심볼릭 링크 이탈과 비밀 정보 경로를 거부한다.
- 정규 미션 루트는 정확히 `docs/analysis/missions/<mission-id>/`다. 기존 미션 식별자나 `source fingerprint`가 다르면 중단한다.
- 입력 누락이나 경로 모호성이 있으면 누락 필드와 `UNKNOWN`만 보고하고 어떤 파일도 쓰지 않는다.

## CodeGraph 비즈니스 비교 경로

- `sensai-evidence-first`를 `CodeGraph` 운영의 단일 권위로 적용하라. 해당 스킬의 `PRE_QUERY_ADMISSION`, 질의 전 묶음 고정, 정확한 바이트·개수·호출 한도, `MCP` 질의와 `CLI` 대체, 응답 상한, 원문 재확인, 중단 상태를 그대로 따르고 여기서 재정의하거나 완화하지 마라.
- `codegraph status . --json` 입학 판정이 통과한 뒤 사용자에게 별도 `MCP` 실행 권한을 요청하고 허용된 경우에만 `codegraph_explore`를 실행하라. 사용 가능한 응답 전 `timeout`·`deny`·`transport_error`만 `CLI` 대체가 가능하며, `malformed`·`schema-invalid`·응답 상한 초과는 재시도·대체·병합 없이 중단하라. 그 밖의 경로는 `sensai-evidence-first`의 고정 경로만 따른다.
- 질의 전 묶음을 고정한 뒤 그래프 결과로 `query_en`, `scope_prefix`, 검증된 앵커 또는 `route`를 다듬거나 추가하거나 번역하지 마라.
- `F2`는 선택한 도메인 문서와 코드의 비즈니스 흐름을 양방향 직접 근거로 비교한다. 문서와 그래프 출력은 후보로 유지하고 주 에이전트가 현재 원문의 직접 `path:line`을 재확인해 `consistent`로 판정한 경우에만 정규 `trace.json`과 용어집 후보를 직렬 병합하라.
- 이름 유사, 문서↔코드 불일치 또는 근거 부족은 `unresolved`, `ambiguous`, `many_to_many`, `conflict`, `unsupported`로 보존하고 병합을 중단하라. 질의 묶음, 경로, 비교 상태 같은 일시 자료를 `trace schema`나 `trace.json` 속성으로 저장하지 마라.

## 스킬 적용 순서

OpenCode에 별도 `skill` 순서 필드가 있다고 가정하지 말고 아래 순서를 본문 계약으로 지켜라.

1. `sensai-evidence-first`를 불러 직접 근거와 미확정 상태의 형식을 고정한다.
2. `sensai-business-trace`를 불러 엔티티, 규칙, 흐름, 이벤트, 상태, 불변조건과 근거 있는 용어 후보를 수집한다.
3. 선택한 도메인 문서가 있을 때만 `sensai-spec-evidence`를 보조로 적용하고 코드 사실과 정확히 대조한다.
4. `glossary.jq`와 `trace.jq`, `trace schema`의 실제 종료 코드로 `glossary`와 병합 후보를 검증한다.

앞 단계가 실패하면 뒤 스킬을 실행하지 말고 암묵적 규칙이나 발명한 용어를 확정 사실로 승격하지 마라.

## 위임과 직렬 병합

- 근거 수집은 `sensai-evidence-peer`에 `subtask: true`인 작은 작업으로만 위임한다. 작업 하나는 단일 `scope`, 단일 비즈니스 분류 또는 단일 문서만 다룬다.
- 피어는 읽기 전용으로 `path:line`, 관찰값, 후보 `evidence_ids`, 기술 교차 참조, `UNKNOWN`·`unresolved`·`ambiguous`·`many_to_many`·`conflict` 상태와 결정적 명령 종료 코드만 반환한다. 편집, 의미 판정, 재위임과 완료 선언을 맡기지 마라.
- `sensai-analysis-lead`는 반환된 근거를 직접 재확인하고 비즈니스 의미를 판정한 뒤 `F2` 후보를 직렬로 병합·적재한다. `F1`과 조사를 동시에 할 수 있어도 같은 `trace.json`과 `glossary`는 병렬로 쓰지 않는다.
- `sensai-analysis-lead`만 정규 미션 상태를 쓰는 단일 작성자다. 기존 `revision`과 입력 `fingerprint`가 달라졌으면 병합을 거부한다.

## 정규 출력

검증을 통과한 뒤 현재 미션 루트의 `trace.json`에만 `F2`, `kind: asis`인 `business_entities`, `business_rules`, `business_flows`, `business_events`, `business_states`, `business_invariants`를 직렬 병합한다. 별도 파생물은 같은 미션 루트의 `glossary.json`과 `glossary.ko.md`에 둔다.

모든 확정 사실과 용어에 안정 ID, 실제 `path:line`, 하나 이상의 `evidence_ids`를 연결한다. 근거가 없으면 `UNKNOWN`, 기술 대응이 없으면 `unresolved`, 복수 후보는 `ambiguous` 또는 `many_to_many`, 상충 근거는 `conflict`로 보존한다. 이름 유사성으로 기술 사실과 비즈니스 사실을 연결하지 않는다.

미션 루트 밖에는 쓰지 않는다. 특히 대상 코드, 도메인 원문, 전역 OpenCode 설정, 저장소 루트의 상태 파일과 다른 미션을 수정하지 않는다. 검증 실패 시 후보 패킷만 반환하고 정규 `trace.json`과 `glossary`를 변경하지 않는다.
