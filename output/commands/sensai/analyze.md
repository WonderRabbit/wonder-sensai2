---
description: 기존 코드베이스의 기술 구조와 일곱 범주 컨벤션을 근거 중심으로 분석한다
agent: sensai-analysis-lead
subtask: false
---

# AS-IS 기술 분석

`$ARGUMENTS`를 `<mission-id> [scope]` 형식의 데이터로만 해석하라. 셸 문법으로 실행하지 마라. 명령은 현재 저장소를 대상 루트로 사용하고, 생략한 `scope`는 `.`이다.

## 입력 확인

다음 조건을 모두 통과하기 전에는 파일을 쓰지 마라.

- `<mission-id>`는 `^[a-z0-9]+(-[a-z0-9]+)*$`를 만족해야 한다.
- `scope`는 대상 루트 기준 상대 경로여야 한다. 절대 경로, 빈 경로 요소, `..`, 심볼릭 링크를 통한 대상 루트 이탈을 거부한다.
- 정규 미션 루트는 정확히 `docs/analysis/missions/<mission-id>/`다. 이미 있는 미션의 `mission_id`가 인수와 다르면 중단한다.
- 입력 누락, 경로 모호성 또는 검증기 부재가 있으면 누락 필드와 차단 사유만 보고하고 어떤 파일도 쓰지 않는다.

## CodeGraph 기술 비교 경로

- `sensai-evidence-first`를 `CodeGraph` 운영의 단일 권위로 적용하라. 해당 스킬의 `PRE_QUERY_ADMISSION`, 질의 전 묶음 고정, 정확한 바이트·개수·호출 한도, `MCP` 질의와 `CLI` 대체, 응답 상한, 원문 재확인, 중단 상태를 그대로 따르고 여기서 재정의하거나 완화하지 마라.
- `codegraph status . --json` 입학 판정이 통과한 뒤 사용자에게 별도 `MCP` 실행 권한을 요청하고 허용된 경우에만 `codegraph_explore`를 실행하라. 사용 가능한 응답 전 `timeout`·`deny`·`transport_error`만 `CLI` 대체가 가능하며, `malformed`·`schema-invalid`·응답 상한 초과는 재시도·대체·병합 없이 중단하라. 그 밖의 경로는 `sensai-evidence-first`의 고정 경로만 따른다.
- 질의 전 묶음을 고정한 뒤 그래프 결과로 `query_en`, `scope_prefix`, 검증된 앵커 또는 `route`를 다듬거나 추가하거나 번역하지 마라.
- `F1`은 기술 관계와 영향 후보만 비교한다. 그래프 출력은 후보로 유지하고 주 에이전트가 현재 원문의 직접 `path:line`을 재확인해 `consistent`로 판정한 경우에만 정규 `trace.json` 후보를 직렬 병합하라.
- 이름 유사, 원문 불일치 또는 근거 부족은 `unresolved`, `ambiguous`, `many_to_many`, `conflict`, `unsupported`로 보존하고 병합을 중단하라. 질의 묶음, 경로, 비교 상태 같은 일시 자료를 `trace schema`나 `trace.json` 속성으로 저장하지 마라.

## 스킬 적용 순서

OpenCode에 별도 `skill` 순서 필드가 있다고 가정하지 말고 아래 순서를 본문 계약으로 지켜라.

1. `sensai-evidence-first`를 불러 근거 형식과 미확정 상태를 고정한다.
2. `sensai-stack-discovery`를 불러 매니페스트로 입증된 스택과 버전만 식별한다.
3. 입증된 스택에만 `sensai-react-trace` 또는 `sensai-vertx-trace`를 가속기로 적용하고, 명세가 있으면 `sensai-spec-evidence`를 보조로 적용한다.
4. `sensai-convention-extract`를 불러 후보 원문을 재확인하고 컨벤션을 정규화한다.
5. `trace.jq`와 `trace schema`의 실제 종료 코드로 병합 후보를 검증한다.

앞 단계가 실패하면 뒤 스킬을 실행하지 말고 부분 결과를 완료로 표시하지 마라.

## 위임과 직렬 병합

- 수집 작업은 `sensai-evidence-peer`에 `subtask: true`인 작은 작업으로만 위임한다. 작업 하나는 단일 `scope`, 단일 스킬, 하나의 확인 질문만 가진다.
- 피어는 읽기 전용으로 `path:line`, 관찰값, 후보 `evidence_ids`, 관련 안정 ID, `UNKNOWN`·`unresolved`·`ambiguous`·`many_to_many`·`conflict` 상태와 결정적 명령 종료 코드만 반환한다. 편집, 판정, 재위임과 완료 선언을 맡기지 마라.
- `sensai-analysis-lead`는 반환된 원문과 종료 코드를 직접 재확인한 뒤 `F1` 후보를 직렬로 병합·적재한다. `F2`와 조사를 동시에 할 수 있어도 같은 `trace.json` 병합은 병렬로 쓰지 않는다.
- `sensai-analysis-lead`만 정규 미션 상태를 쓰는 단일 작성자다. 기존 `revision`과 입력 `fingerprint`가 달라졌으면 병합하지 말고 충돌을 보고한다.

## 정규 출력

검증을 통과한 뒤 현재 미션 루트의 `trace.json`에만 `F1`, `kind: asis`, 근거가 있는 기술 사실과 컨벤션을 직렬 병합한다. 컨벤션 범주는 정확히 `COMPONENT`, `STRUCTURE`, `NAMING`, `API`, `STATE`, `ERROR`, `TEST` 일곱 개다. `DATAFLOW`를 컨벤션 범주로 추가하지 마라.

모든 확정 사실에 안정 ID, 실제 `path:line`, 하나 이상의 `evidence_ids`를 연결한다. 근거 없는 값을 채우지 말고 `UNKNOWN`, 동적 연결은 `unresolved`, 복수 후보는 `ambiguous` 또는 `many_to_many`, 상충 근거는 `conflict`, 지원 불가는 `UNSUPPORTED`로 보존한다.

미션 루트 밖에는 쓰지 않는다. 특히 대상 코드, 전역 OpenCode 설정, 저장소 루트의 상태 파일과 다른 미션을 수정하지 않는다. 검증 실패 시 후보 패킷만 반환하고 canonical `trace.json`을 변경하지 않는다.
