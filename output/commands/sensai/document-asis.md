---
description: 검증된 기술·비즈니스 원장을 현재 시스템의 네 가지 AS-IS 산출물로 투영한다
agent: sensai-analysis-lead
subtask: false
---

# AS-IS 산출 문서화

`$ARGUMENTS`를 `<mission-id>` 형식의 데이터로만 해석하라. 셸 문법으로 실행하지 마라.

## 입력 확인과 F3 선행조건

다음 조건을 모두 통과하기 전에는 파일을 쓰지 마라.

- `<mission-id>`는 `^[a-z0-9]+(-[a-z0-9]+)*$`를 만족해야 한다.
- 정규 미션 루트는 정확히 `docs/analysis/missions/<mission-id>/`이고 심볼릭 링크나 다른 미션으로 해석되지 않아야 한다.
- `F1`과 `F2`의 검증이 끝난 `trace.json`이 있어야 한다. 기술 사실과 일곱 컨벤션 범주, 여섯 `business_*` 분류 중 요구된 항목, 직접 근거와 검증 성공 영수증을 확인한다.
- `trace.jq`와 `trace schema`가 실제로 `exit 0`을 반환하지 않거나 입력 `hash`가 영수증과 다르면 `document-before-analysis`로 차단하고 어떤 산출물도 쓰지 않는다.

## 스킬 적용 순서

OpenCode에 별도 `skill` 순서 필드가 있다고 가정하지 말고 아래 순서를 본문 계약으로 지켜라.

1. `sensai-evidence-first`를 불러 모든 투영 요소의 원천 ID와 직접 근거를 먼저 고정한다.
2. `sensai-ui-definition`으로 `kind: asis` `UI` 정의를 투영하고 `ui provenance`와 구조를 검증한다.
3. `sensai-mermaid-sequence`로 `exact join`과 비즈니스 흐름만 `sequenceDiagram`에 투영하고 `mermaid provenance`와 렌더를 검증한다.
4. `sensai-dataflow-chart`로 검증된 데이터 이동만 `flowchart`에 투영하고 `dataflow` provenance와 렌더를 검증한다.
5. `sensai-user-story`로 검증된 역할·행동·가치만 한국어 스토리로 투영하고 `story` provenance와 구조를 검증한다.
6. 네 산출의 `validator` 종료 코드, 비어 있지 않은 렌더 `hash`와 원장 역참조를 함께 검사한다.

앞 산출 또는 검증이 실패하면 뒤 단계를 완료로 표시하지 말고 F3를 차단한다.

`F3`에서는 CodeGraph 후보를 재탐색하거나 새 그래프 호출을 실행하지 않는다. 검증된 `F1`·`F2` 원장만 투영하며 `unresolved`, `ambiguous`, `conflict`가 대상 요소에 남아 있으면 문서화를 중단한다.

## 위임과 정규 작성

- 원장 역대조와 누락 탐지는 `sensai-evidence-peer`에 `subtask: true`인 작은 작업으로만 위임한다. 한 작업은 산출 하나와 provenance 모드 하나만 다룬다.
- 피어는 읽기 전용으로 `path:line`, 원천 ID, `evidence_ids`, 누락과 `UNKNOWN`·`unresolved`·`ambiguous`·`many_to_many`·`conflict` 상태, 결정적 검증 종료 코드만 반환한다. 산출 작성, 렌더 판정, 게이트 판정, 재위임과 완료 선언을 맡기지 마라.
- `sensai-analysis-lead`는 반환값을 원장과 직접 재확인한 뒤 네 산출을 순서대로 직렬 병합·적재한다. 같은 산출을 병렬 작성하지 않는다.
- `sensai-analysis-lead`만 정규 미션 상태와 산출을 쓰는 단일 작성자다. 기존 `revision`이나 입력 `hash`가 바뀌면 부분 병합 없이 중단한다.

## 정규 출력

현재 미션 루트 아래에만 다음 네 파일을 작성한다.

1. `asis/ui.md`
2. `asis/sequence.mmd`
3. `asis/dataflow.mmd`
4. `asis/story.md`

모든 확정 요소에 `kind: asis`, 안정 ID, 실제 `path:line`, 하나 이상의 `evidence_ids`를 연결한다. 원장에 없는 화면·호출·데이터 흐름·가치를 발명하지 마라. 근거가 없으면 `UNKNOWN`, 동적 값은 `unresolved`, 복수 후보는 `ambiguous` 또는 `many_to_many`, 상충 근거는 `conflict`로 보존한다.

미션 루트 밖에는 쓰지 않는다. 대상 코드, 전역 OpenCode 설정, 저장소 루트의 상태 파일, 다른 미션과 TO-BE 산출을 수정하지 않는다.

## `F3` 하드 게이트

네 산출과 `provenance`·구조·렌더 검증이 모두 성공하면 `F3` 하드 게이트의 사람 승인 대기 상태만 보고한다. 사람이 현재 입력 `fingerprint`에 결합된 `accepted` 승인을 남기기 전에는 `F4` 또는 TO-BE로 진입하지 말고, 승인 `verdict`를 모델이 만들거나 재사용하지 마라.
