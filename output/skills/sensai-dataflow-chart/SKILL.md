---
name: sensai-dataflow-chart
description: "검증된 AS-IS 분석 또는 TO-BE 설계를 안정 식별자로 역대조 가능한 Mermaid 데이터플로우차트로 투영하고 렌더를 확인할 때 사용한다."
---

# 데이터플로우차트 투영

## 적용 조건

검증된 원장의 데이터 이동을 `flowchart`로 투영할 때 적용하고 원장에 없는 흐름을 발명하지 마라.

## 입력

- 현재 미션 루트의 validator 통과 `trace.json`과 대상 `kind: asis|tobe`
- AS-IS `BIZ-FLOW-*`·상태·기술 ID 또는 TO-BE `DESIGN-*`·`REQ-EXT-*`·AS-IS 상태
- `fixtures/expected/asis/dataflow.mmd`와 원문 `path:line`

## 작업 순서

1. 원장과 대상 `kind`가 일치하는지 확인하라.
2. 각 노드와 엣지를 원천 ID, `evidence_ids`, 직접 근거에 먼저 연결하라.
3. `DATA-ASIS-<NNN>` 또는 `DATA-TOBE-<NNN>` 안정 ID를 부여하고 `%% DATA`, `%% DESIGN`, 엣지 `[DATA][DESIGN]`을 기록하라.
4. 5모드 `ui`, `mermaid`, `dataflow`, `story`, `test` 중 `dataflow`로 `provenance.jq` 역대조를 실행하라.
5. `mmdc`로 비어 있지 않은 SVG를 렌더하고 종료 코드와 해시를 영수증에 기록하라.

## 출력

- 현재 미션 산출 경로에 `kind`, 안정 `DATA-*` 식별자, 원천 식별자와 근거가 있는 `Mermaid flowchart`를 작성하라.
- `UNKNOWN`, `unresolved`, `ambiguous`, `many_to_many`, `conflict`와 컨벤션 위반을 숨기지 말고 차단 상태로 함께 보고하라.

## 근거 계약

- 근거 계약: 모든 확정 요소에 실제 `path:line`과 하나 이상의 `evidence_ids`를 연결하라.
- 이름 유사성만으로 데이터 흐름을 확정하거나 `AS-IS`와 `TO-BE`를 섞지 마라.

## 허용 도구와 권한

- 허용된 `jq -e`, `rg`, `mmdc`만 읽기·검증·렌더에 사용하라.
- 스킬 로드는 권한을 추가하지 않는다. 현재 미션 루트 밖을 읽거나 쓰지 말고, 쓰기는 주 에이전트의 허용 경로에만 수행하라.

## 입학 상태

- 시작 상태는 `REQUIRED_TO_EVALUATE`다. 실패하면 `NOT_ADMITTED`, 순가치가 없으면 `ADMITTED_NO_VALUE`로 보존하라.
- 입학 고정 입력과 카탈로그 근거 및 사람 승인을 받은 `VALUE_PROVEN` 전에는 에이전트 허용 목록이나 설정에서 자동으로 활성화·승격하지 마라.

## 실패 처리

- 식별자 역대조, 엣지 대응, 근거 추적 또는 렌더가 실패하면 사람 검토 대상으로 차단하고 부분 산출물을 완료로 표시하지 않는다.
