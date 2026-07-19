---
name: sensai-user-story
description: "검증된 요구사항과 AS-IS 비즈니스 사실 또는 TO-BE 설계를 한국어 역할·행동·가치 사용자 스토리로 투영할 때 사용한다."
---

# 사용자 스토리 투영

## 적용 조건

현재 동작 또는 변경 후 요구를 사람이 검토할 사용자 스토리로 투영할 때 적용하고 새 요구를 만들지 마라.

## 입력

- 현재 미션 루트의 validator 통과 `trace.json`과 대상 `kind: asis|tobe`
- AS-IS `REQ-*`·`BIZ-*` 또는 TO-BE `REQ-EXT-*`·`DESIGN-*`
- TO-BE 기준 예시 `fixtures/expected/tobe/story.md`와 연결된 원문 `path:line`

## 작업 순서

1. 입력 원장, 대상 `kind`, 요구·설계·비즈니스 상태를 확인하라.
2. 스토리마다 역할, 행동, 가치를 한국어로 적고 원천 ID와 직접 근거를 먼저 매핑하라.
3. `STORY-ASIS-<NNN>` 또는 `STORY-TOBE-<NNN>` 안정 식별자와 관련 `REQ-*`, `DESIGN-*`, `BIZ-*` 식별자를 기록하라.
4. 5모드 `ui`, `mermaid`, `dataflow`, `story`, `test` 중 `story`로 `provenance.jq` 역대조를 실행하라.
5. `mdq`로 구조와 필수 ID를 검사하고 검증 영수증을 남겨라.

## 출력

- 현재 미션 산출 경로에 `kind`, `STORY-*`, 역할·행동·가치와 원천 식별자가 있는 한국어 마크다운을 작성하라.
- `UNKNOWN`, `unresolved`, `ambiguous`, `many_to_many`, `conflict`와 위반을 삭제하거나 정상 스토리로 합치지 마라.

## 근거 계약

- 근거 계약: 모든 확정 스토리에 실제 `path:line`과 하나 이상의 `evidence_ids`를 연결하라.
- `REQ-*`, `DESIGN-*`, `BIZ-*`가 원장에 없거나 상태가 상충하면 이름 유사성으로 채우지 마라.

## 허용 도구와 권한

- 허용된 `jq -e`, `rg`, `mdq`만 읽기·검증에 사용하라.
- 스킬 로드는 권한을 추가하지 않는다. 현재 미션 루트 밖을 읽거나 쓰지 말고, 쓰기는 주 에이전트의 허용 경로에만 수행하라.

## 입학 상태

- 시작 상태는 `REQUIRED_TO_EVALUATE`다. 실패하면 `NOT_ADMITTED`, 순가치가 없으면 `ADMITTED_NO_VALUE`로 보존하라.
- 입학 고정 입력과 카탈로그 근거 및 사람 승인을 받은 `VALUE_PROVEN` 전에는 에이전트 허용 목록이나 설정에서 자동으로 활성화·승격하지 마라.

## 실패 처리

- 역할·행동·가치, 식별자 결합, 근거 추적 또는 문서 구조가 실패하면 사람 검토 대상으로 차단하고 부분 산출물을 완료로 표시하지 않는다.
