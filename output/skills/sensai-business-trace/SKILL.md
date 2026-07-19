---
name: sensai-business-trace
description: "코드와 도메인 문서에서 6개 비즈니스 사실 분류와 근거 있는 용어를 추출하고 암묵적 규칙·충돌을 보존할 때 사용한다."
---

# 비즈니스 사실 추적

코드 근거를 우선하고 도메인 문서를 보조 근거로 사용해 AS-IS 비즈니스 사실을 적재하라.

## 입력

- 현재 미션 루트의 코드, 선택적 도메인 문서와 기술 분석 `trace.json`
- `fixtures/inputs/business/order-rules.md`, `fixtures/inputs/business/order-state.json`과 `fixtures/expected/trace-v2.json`
- 용어사전이 있으면 `glossary.json`과 연결된 근거 ID

## 작업 순서

1. 구조·문서 후보를 수집하고 각 문장의 원문 `path:line`을 다시 확인하라.
2. 사실을 `business_entity`, `business_rule`, `business_flow`, `business_event`, `business_state`, `business_invariant` 중 하나로 분류하라.
3. 각각 `BIZ-ENT-*`, `BIZ-RULE-*`, `BIZ-FLOW-*`, `BIZ-EVT-*`, `BIZ-STATE-*`, `BIZ-INV-*` 안정 ID와 `kind: asis`를 부여하라.
4. 흐름의 각 단계는 기술 식별자와 교차 확인하고 대응하지 않으면 `unresolved`로 남겨라.
5. 용어는 `GLOSS-*` 식별자, 식별자 형태, `maps_to`, 근거 식별자를 가진 별도 `glossary`에 기록하고 원장과 충돌하면 원장을 따르라.

## 출력

- 6개 `business_*[]`, 연결된 `evidence[]`와 근거 기반 glossary 후보를 반환하라.
- 각 사실에 안정 식별자, 분류, `kind: asis`, 한국어 진술, 상태와 하나 이상의 `evidence_ids`를 포함하라.
- `fixtures/adversarial/hidden-conflict.json`처럼 양쪽 근거가 있는 충돌은 삭제하거나 단일 규칙으로 합치지 마라.

## 근거 계약

- 근거 계약: 모든 확정 사실에 실제 `path:line`과 하나 이상의 `evidence_ids`를 연결하라.
- 근거가 없으면 `UNKNOWN`, 기술 대응이 없으면 `unresolved`, 복수 후보면 `ambiguous`, 상충하면 `conflict`를 보존하라.
- 암묵적 규칙, 발명한 용어 또는 이름 유사성을 원장 사실과 glossary에 승격하지 마라.

## 허용 도구와 권한

- 허용된 `rg --json`, `sg --json`, `jq -e`, `yq`, `mdq`만 읽기·구조 검색·검증에 사용하라.
- 스킬 로드는 권한을 추가하지 않는다. 현재 미션 루트 밖을 읽거나 쓰지 말고, 쓰기는 주 에이전트의 허용 경로에만 수행하라.
- 사용자 문자열을 셸 문법으로 실행하지 말고, 비밀 정보와 전역 설정을 읽지 마라.

## 입학 상태

- 시작 상태를 `REQUIRED_TO_EVALUATE`로 기록하고 근거 없는 주장 발생 시 `NOT_ADMITTED`, 순가치 부재 시 `ADMITTED_NO_VALUE`로 남겨라.
- 사람 승인까지 받은 `VALUE_PROVEN`만 상시 필수 경로로 승격하라.

## 실패 처리

- class가 불명확하거나 기술 대응·근거가 없으면 해당 상태와 다음 확인 대상을 기록하라.
- 안정 식별자, 직접 근거, `glossary` 역참조 또는 검증기가 실패하면 부분 산출물을 완료로 표시하지 않는다.
