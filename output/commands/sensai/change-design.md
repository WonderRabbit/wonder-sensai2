---
description: 승인된 기존 상태와 고객 수정요청을 결합해 양쪽 연결이 검증된 변경 설계를 원장에 적재한다
agent: sensai-analysis-lead
subtask: false
---

# TO-BE 변경 설계

`$ARGUMENTS`를 `<mission-id> <change-request-source>` 형식의 데이터로만 해석하라. 사용자 문자열을 셸 문법으로 실행하지 마라. 정규 미션 루트는 정확히 `docs/analysis/missions/<mission-id>/`다.

## 입력 확인과 승인 선행조건

다음 조건을 모두 통과하기 전에는 파일을 쓰지 마라.

- `<mission-id>`는 `^[a-z0-9]+(-[a-z0-9]+)*$`를 만족하고 정규 미션 루트가 심볼릭 링크나 다른 미션으로 해석되지 않아야 한다.
- 현재 `source fingerprint`에 결합된 `F3` 사람 승인 상태가 `accepted`여야 한다. 사람이 남긴 승인과 현재 지문이 없거나 다르면 `tobe-before-asis-accept`로 중단하고 TO-BE를 쓰지 않는다.
- `F1` 기술 컨벤션과 `F2` 비즈니스 사실이 있는 `kind: asis` 원장, AS-IS 4종 산출, `trace schema`와 `trace.jq`의 `exit 0` 영수증을 확인한다.
- 수정요청은 `user`, `elicited`, `inferred` 중 출처와 원문을 가져야 한다. 출처가 없으면 `UNKNOWN`으로 보존하고 설계 입력으로 승격하지 않는다.
- 입력 누락, 해시 불일치, `unresolved`, `ambiguous`, `many_to_many`, `conflict`가 게이트 판정에 영향을 주면 차단 사유만 보고하고 정규 원장을 변경하지 않는다.

## 스킬 적용 순서

OpenCode에 별도 `skill` 순서 필드가 있다고 가정하지 말고 아래 순서를 본문 계약으로 지켜라.

1. `sensai-evidence-first`를 불러 수정요청, AS-IS 제약과 `path:line`·`evidence_ids` 형식을 고정한다.
2. `sensai-requirement-analyze`를 불러 수정요청에 `REQ-EXT-*` 안정 ID와 출처를 부여하고 중복·충돌을 검출한다.
3. `sensai-change-design`을 불러 컨벤션과 비즈니스 사실을 함께 소비하는 `DESIGN-*` 후보와 `bindings[]`를 만든다.
4. `trace.jq`와 `trace schema`의 실제 종료 코드로 전체 원장을 검증하고 입력·출력 해시를 영수증에 기록한다.

앞 단계가 실패하면 뒤 단계를 진행하거나 부분 결과를 완료로 표시하지 마라.

## 위임과 단일 작성

- 충돌과 `binding` 근거 조사는 `sensai-evidence-peer`에 `subtask: true`인 작은 읽기 전용 작업으로만 위임한다. 피어는 한 요구 또는 한 설계에 대한 `path:line`, `evidence_ids`, 원천 `ID`, 미확정 상태와 결정적 종료 코드만 반환하고 편집, 의미 판정, 재위임, 완료 선언을 하지 않는다.
- `sensai-analysis-lead`는 피어 반환값을 직접 재확인하고 후보를 직렬로 병합·적재하는 단일 작성자다. 같은 `trace.json`을 병렬로 쓰지 않으며 기존 `revision`, `source fingerprint` 또는 입력 해시가 달라지면 병합하지 않는다.

## 변경 설계와 binding 게이트

- 각 `designs[]` 항목은 `kind: tobe`, 안정 `DESIGN-PAGE|SERVICE|API|ENTITY-<NNN>` ID, `requirement_ids`, 직접 근거와 하나 이상의 `evidence_ids`를 가져야 한다.
- 각 설계의 `follows_convention_ids`와 `follows_business_ids`를 각각 하나 이상 채우고 `bindings[]`의 `design_id`와 exact 연결한다.
- `binding` 없음, `dangling ID`, 이름 유사성만으로 만든 연결 또는 `gate: violation`은 `D4` 불통과다. 이런 경우 정규 TO-BE를 쓰지 않고 사람에게 수정, 예외 승인 또는 재설계를 요청한다.
- 사람의 예외 승인은 현재 설계·원장 해시와 결합해야 하며 모델이 `accepted` 또는 `pass`를 만들거나 추정하지 않는다.

## 정규 출력과 소유권 경계

검증이 모두 성공한 뒤 현재 미션 루트의 `trace.json` TO-BE 구간에만 `extension_requirements[]`, `designs[]`, `bindings[]`, `unknowns[]`를 직렬 적재한다. 모든 확정 항목은 안정 ID, 실제 `path:line`, 하나 이상의 `evidence_ids`를 가지며 `UNKNOWN`, `unresolved`, `ambiguous`, `many_to_many`, `conflict`를 숨기지 않는다.

UI 정의서, 시퀀스, 데이터플로우, 사용자 스토리, 테스트 시나리오는 이 명령이 직접 작성하지 않는다. 최종 표현은 검증된 설계를 입력으로 받는 `/sensai/deliver`가 소유한다. 대상 코드, 최종 산출물, 전역 OpenCode 설정, 다른 미션 또는 미션 루트 밖에는 쓰지 않는다.
