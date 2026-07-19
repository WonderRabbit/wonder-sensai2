---
name: sensai-change-design
description: "검증된 확장 요구와 AS-IS 컨벤션·비즈니스 사실을 결합해 TO-BE 설계를 만들고 binding과 위반의 사람 승인 게이트를 판정할 때 사용한다."
---

# 변경 설계와 일관성 게이트

## 적용 조건

검증된 수정요청을 brownfield 변경 설계로 변환할 때 적용하고 AS-IS 기술 또는 비즈니스 제약이 없으면 시작하지 마라.

## 입력

- 현재 미션 루트의 validator 통과 AS-IS `trace.json`
- 출처와 근거가 검증된 `REQ-EXT-*` 및 고객 승인 범위
- 컨벤션 `CONV-*`, 비즈니스 `BIZ-*`, 충돌과 미확정 상태

## 작업 순서

1. 기술 컨벤션과 비즈니스 사실이 모두 존재하고 검증됐는지 확인하라.
2. 각 변경에 `DESIGN-PAGE|SERVICE|API|ENTITY-<NNN>` 안정 ID와 관련 `REQ-EXT-*`, `evidence_ids`를 부여하라.
3. 각 설계의 `follows_convention_ids`와 `follows_business_ids`를 하나 이상 채우고 `bindings[]`로 직접 근거를 연결하라.
4. 불일치는 `gate: violation`과 `conflict`로 기록하고 `D4/F3`에서 사람이 수용·수정·재설계를 승인하기 전 통과시키지 마라.
5. 이후 5모드 `ui`, `mermaid`, `dataflow`, `story`, `test` 투영이 같은 `DESIGN-*`와 `REQ-EXT-*`를 역대조하도록 `trace.jq`로 검증하라.

## 출력

- `kind: tobe`인 `designs[]`, `bindings[]`, 갱신된 `unknowns[]`와 사람 판정 대기 항목을 반환하라.
- `UNKNOWN`, `unresolved`, `ambiguous`, `many_to_many`, `conflict`와 컨벤션 위반을 숨기거나 `pass`로 바꾸지 마라.

## 근거 계약

- 근거 계약: 모든 확정 설계와 binding에 실제 `path:line`과 하나 이상의 `evidence_ids`를 연결하라.
- 이름 유사성으로 `REQ-*`, `CONV-*`, `BIZ-*`, `DESIGN-*` 결합을 만들지 마라.

## 허용 도구와 권한

- 허용된 `jq -e`, `rg`, `sg --json`만 읽기·구조 검색·검증에 사용하라.
- 스킬 로드는 권한을 추가하지 않는다. 현재 미션 루트 밖을 읽거나 쓰지 말고, 쓰기는 주 에이전트의 허용 경로에만 수행하라.

## 입학 상태

- 시작 상태는 `REQUIRED_TO_EVALUATE`다. 실패하면 `NOT_ADMITTED`, 순가치가 없으면 `ADMITTED_NO_VALUE`로 보존하라.
- 입학 고정 입력과 카탈로그 근거 및 사람 승인을 받은 `VALUE_PROVEN` 전에는 에이전트 허용 목록이나 설정에서 자동으로 활성화·승격하지 마라.

## 실패 처리

- 요구·컨벤션·비즈니스 결합, `D4/F3` 사람 승인 또는 검증기가 실패하면 설계를 차단하고 부분 산출물을 완료로 표시하지 않는다.
