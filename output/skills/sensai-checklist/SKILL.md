---
name: sensai-checklist
description: "분석·설계 게이트가 근거, 미확정 상태, 검증기, 권한, 안정 식별자와 미션 경계를 빠뜨리지 않았는지 점검할 때 사용한다."
---

# 게이트 체크리스트

게이트 산출을 원장과 결정적 검증 결과에 대조하고 누락을 통과로 간주하지 마라.

## 입력

- 현재 미션 루트의 `trace.json`, `progress.json`, 산출물과 실행 영수증
- 점검할 `A/D/V/W` 게이트, 요구한 검증기와 권한 계약
- `fixtures/expected/trace-v2.json`, `fixtures/adversarial/dangling-reference.json`, `fixtures/adversarial/hidden-conflict.json`

## 작업 순서

1. 게이트의 필수 입력·출력과 현재 미션 산출 경로를 확인하라.
2. 모든 신규 사실·설계가 하나 이상의 `evidence_ids`와 재현 가능한 원문 근거를 갖는지 검사하라.
3. `UNKNOWN`, `unresolved`, `ambiguous`, `many_to_many`, `conflict`, `UNSUPPORTED`가 삭제·축약되지 않았는지 확인하라.
4. `trace.jq`·`provenance.jq`의 실제 종료 코드와 실패 식별자를 영수증에서 확인하라.
5. 안정 식별자, 비밀 정보 차단, `rewrite`·`exec`·`pipe` 금지와 `docs/analysis/missions/<mission-id>/**` 쓰기 경계를 점검하라.

## 출력

- 게이트별 항목을 `pass`, `fail`, `blocked`와 근거 식별자, 영수증 경로, 실패 식별자로 반환하라.
- 누락·반복 실패와 다음 작은 태스크를 할 일 목록에 전달하되 사실 원장은 변경하지 마라.
- 필수 항목이 하나라도 실패하면 게이트 입학을 완료로 표시하지 마라.

## 근거 계약

- 근거 계약: 모든 통과 판정에 실제 `path:line`과 하나 이상의 `evidence_ids`를 연결하라.
- 근거가 없으면 `UNKNOWN`, 동적 값은 `unresolved`, 복수 후보는 `ambiguous` 또는 `many_to_many`, 상충하면 `conflict`를 보존하라.
- 성공 문자열만 보고 통과시키거나 실패·차단 항목을 요약 과정에서 삭제하지 마라.

## 허용 도구와 권한

- 허용된 `jq -e`, `rg`, `mdq`만 원장·산출물·영수증 읽기와 검증에 사용하라.
- 스킬 로드는 권한을 추가하지 않는다. 현재 대상 저장소 안의 명시적으로 선택된 원본은 읽기 전용으로만 읽을 수 있다. 비밀 경로와 대상 저장소 밖은 읽지 말고, 쓰기는 현재 미션 루트 안에서 주 에이전트의 허용 경로에만 수행하라.
- 사용자 문자열을 셸 문법으로 실행하지 말고, 비밀 정보와 전역 설정을 읽지 마라.

## 입학 상태

- 시작 상태를 `REQUIRED_TO_EVALUATE`로 기록하고 누락 탐지 실패는 `NOT_ADMITTED`, 순가치 부재는 `ADMITTED_NO_VALUE`로 남겨라.
- 사람 승인까지 받은 `VALUE_PROVEN`만 상시 필수 경로로 승격하라.

## 실패 처리

- 검증기 영수증, 근거, 권한 기록 또는 게이트 입력이 없으면 `blocked`와 누락 목록을 반환하라.
- 하나라도 필수 점검을 재현하지 못하면 부분 산출물을 완료로 표시하지 않는다.
