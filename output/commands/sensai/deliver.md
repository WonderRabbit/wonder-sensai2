---
description: 검증된 TO-BE 설계를 다섯 산출물로 투영하고 provenance와 렌더 영수증을 만든다
agent: sensai-analysis-lead
subtask: false
---

# TO-BE 산출물 투영

`$ARGUMENTS`를 `<mission-id>` 형식의 데이터로만 해석하라. 사용자 문자열을 셸 문법으로 실행하지 마라. 정규 미션 루트는 정확히 `docs/analysis/missions/<mission-id>/`다.

## 입력 확인과 V0 선행조건

다음 조건을 모두 통과하기 전에는 파일을 쓰지 마라.

- `sensai-dataflow-chart`, `sensai-user-story`, `sensai-test-scenario`가 `VALUE_PROVEN` 입학 영수증에 결합돼 `permission.skill`에서 명시적으로 허용돼야 한다. 현재 정확한 `deny` 상태에서는 `MODEL_ADMISSION_UNVERIFIED`를 보고하고 F5 실시간 실행을 중단한다.
- `<mission-id>`와 정규 미션 루트가 일치하고 경로가 심볼릭 링크나 다른 미션으로 해석되지 않아야 한다.
- 현재 `source fingerprint`에 결합된 `F3` 사람 승인 `accepted` 영수증과 검증된 `kind: tobe` `designs[]`, `extension_requirements[]`, `bindings[]`가 있어야 한다.
- 각 설계의 `follows_convention_ids`, `follows_business_ids`, `requirement_ids`, `evidence_ids`와 `bindings[]` `exact` 연결을 확인한다. `binding` 누락, `dangling ID`, `gate: violation`, 숨긴 `conflict`가 하나라도 있으면 `V0`에서 차단한다.
- `trace schema`와 `trace.jq`의 실제 `exit 0`, 원장 해시와 일치하는 validator 영수증이 없으면 설계를 다시 쓰거나 게이트를 우회하지 말고 `/sensai/change-design`으로 회귀한다.

## 스킬 적용 순서와 다섯 모드

OpenCode에 별도 `skill` 순서 필드가 있다고 가정하지 말고 아래 순서를 본문 계약으로 지켜라.

1. `sensai-evidence-first`로 각 투영 요소의 설계·요구·컨벤션·비즈니스 원천과 `path:line`·`evidence_ids`를 먼저 고정한다.
2. `sensai-ui-definition`으로 `kind: tobe` `UI` 정의와 `Mermaid` 와이어프레임을 투영한다.
3. `sensai-mermaid-sequence`로 검증된 서비스·API 흐름만 `sequenceDiagram`에 투영한다.
4. `sensai-dataflow-chart`로 검증된 설계와 AS-IS 상태만 `flowchart`에 투영한다.
5. `sensai-user-story`로 검증된 역할·행동·가치를 한국어 사용자 스토리로 투영한다.
6. `sensai-test-scenario`로 스토리와 설계에 결합된 `GIVEN`·`WHEN`·`THEN` 시나리오를 투영한다.

각 파일마다 `provenance.jq`의 정확한 `ui`, `mermaid`, `dataflow`, `story`, `test` 모드를 적용한다. 앞 산출 또는 선행 게이트가 실패하면 뒤 산출을 진행하지 않고, 이미 만든 후보를 정규 산출물로 쓰거나 완료로 표시하지 않는다.

## 위임과 단일 작성

- 원장 역대조와 누락 검사는 `sensai-evidence-peer`에 `subtask: true`인 작은 읽기 전용 작업으로만 위임한다. 피어는 산출 하나와 `provenance` 모드 하나에 대한 `path:line`, `evidence_ids`, 원천 `ID`, `UNKNOWN`, `unresolved`, `ambiguous`, `many_to_many`, `conflict`와 결정적 종료 코드만 반환한다.
- `sensai-analysis-lead`는 반환값을 직접 재확인하고 산출을 순서대로 직렬 작성하는 단일 작성자다. 피어에게 작성, 렌더 판정, 게이트 판정, 재위임이나 완료 선언을 맡기지 않는다.

## 정규 출력과 검증 영수증

현재 미션 루트 아래에만 다음 다섯 파일을 작성한다.

1. `tobe/ui.md`
2. `tobe/sequence.mmd`
3. `tobe/dataflow.mmd`
4. `tobe/story.md`
5. `tobe/test.md`

각 산출은 `kind: tobe`, 안정 ID, 실제 `path:line`, 하나 이상의 `evidence_ids`와 원천 `REQ-EXT-*`·`DESIGN-*`를 가져야 한다. 근거가 없으면 `UNKNOWN`, 동적 값은 `unresolved`, 복수 후보는 `ambiguous` 또는 `many_to_many`, 상충은 `conflict`로 보존하고 발명한 요소로 채우지 않는다.

- 다섯 `provenance` 모드와 구조 `validator`의 실제 종료 코드, 입력·출력 해시를 `validator` 영수증에 기록한다.
- `UI` 와이어프레임, 시퀀스와 데이터플로우 `Mermaid`는 `mmdc`가 `exit 0`이고 `SVG`가 비어 있지 않을 때만 렌더 성공이다. 원문·`SVG` 해시와 크기를 `render` 영수증에 기록한다.
- 검증기, provenance 또는 렌더가 실패하면 인덱스에 성공으로 적재하거나 다음 게이트로 우회하지 않는다.

대상 코드, 설계 원장, 전역 OpenCode 설정, 다른 미션 또는 미션 루트 밖에는 쓰지 않는다. 테스트 실행은 능력과 분리하고 명시적인 per-run 사람 트리거 없이는 실행하지 않는다.

## F5 사람 승인

다섯 산출과 `validator`·`render` 영수증이 모두 성공하면 현재 입력 `fingerprint`와 산출 해시에 결합된 `F5` 사람 승인 `accepted` 대기 상태만 보고한다. 사람 승인 전이나 승인이 없으면 미션 완료를 표시하거나 종료를 선언하지 않는다. 모델이 사람 승인을 만들거나 추정해서는 안 된다.
