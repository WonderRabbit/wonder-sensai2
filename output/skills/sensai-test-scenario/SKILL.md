---
name: sensai-test-scenario
description: "검증된 사용자 스토리와 TO-BE 설계를 안정 ID가 있는 조건·행동·결과 테스트 시나리오로 투영하고 실행 여부를 사람이 결정할 때 사용한다."
---

# 테스트 시나리오 투영

## 적용 조건

검증된 스토리를 인수 시나리오로 변환할 때 적용하고 테스트 실행은 per-run 사람 트리거가 있을 때만 요청하라.

## 입력

- 현재 미션 루트의 validator 통과 `trace.json`과 검증된 사용자 스토리 문서
- TO-BE `STORY-TOBE-*`, `DESIGN-*`, `REQ-EXT-*`와 선택적 AS-IS 기준선
- 기준 예시 `fixtures/expected/tobe/test.md`와 연결된 원문 `path:line`

## 작업 순서

1. 상위 스토리와 원장의 `kind`, 요구·설계·위반 상태를 확인하라.
2. 시나리오마다 `GIVEN`, `WHEN`, `THEN`을 분리하고 원천 스토리·설계·근거를 연결하라.
3. `TEST-ASIS-<NNN>` 또는 `TEST-TOBE-<NNN>` 안정 식별자와 `STORY-*`, `DESIGN-*`, `REQ-*` 식별자를 기록하라.
4. 5모드 `ui`, `mermaid`, `dataflow`, `story`, `test` 중 `test`로 `provenance.jq`와 상위 스토리를 역대조하라.
5. `mdq`로 문서 구조를 검사하고 실행은 자동 파이프라인 능력과 분리해 사람의 per-run 승인 후에만 트리거하라.

## 출력

- 현재 미션 산출 경로에 `kind`, `TEST-*`, `GIVEN`·`WHEN`·`THEN`, 상위 식별자와 근거가 있는 마크다운을 작성하라.
- `UNKNOWN`, `unresolved`, `ambiguous`, `many_to_many`, `conflict`와 컨벤션 위반을 성공 기대값으로 바꾸지 마라.

## 근거 계약

- 근거 계약: 모든 확정 시나리오에 실제 `path:line`과 하나 이상의 `evidence_ids`를 연결하라.
- 스토리와 설계 결합이 없거나 상위 provenance가 실패하면 추정 시나리오를 만들지 마라.

## 허용 도구와 권한

- 허용된 `jq -e`, `rg`, `mdq`만 읽기·검증에 사용하라.
- 스킬 로드는 권한을 추가하지 않는다. 현재 미션 루트 밖을 읽거나 쓰지 말고, 쓰기는 주 에이전트의 허용 경로에만 수행하라.

## 입학 상태

- 시작 상태는 `REQUIRED_TO_EVALUATE`다. 실패하면 `NOT_ADMITTED`, 순가치가 없으면 `ADMITTED_NO_VALUE`로 보존하라.
- 입학 고정 입력과 카탈로그 근거 및 사람 승인을 받은 `VALUE_PROVEN` 전에는 에이전트 허용 목록이나 설정에서 자동으로 활성화·승격하지 마라.

## 실패 처리

- 상위 결합, provenance, 문서 구조 또는 사람 실행 승인이 없으면 실행을 차단하고 부분 산출물을 완료로 표시하지 않는다.
