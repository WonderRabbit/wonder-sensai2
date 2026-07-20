---
name: sensai-requirement-analyze
description: "고객 수정요청을 출처와 RFC 키워드가 보존된 확장 요구사항으로 분석하고 중복·충돌·미확정 항목을 분리할 때 사용한다."
---

# 수정요청 분석

## 적용 조건

고객 수정요청을 TO-BE 설계 입력으로 정규화할 때 적용하고 출처 없는 요청을 확정 요구로 승격하지 마라.

## 입력

- 현재 대상 저장소 안에서 명시적으로 선택된 읽기 전용 고객 문서 또는 현재 미션 입력과 실제 `path:line`
- 사용자 응답 기록과 검증된 AS-IS `trace.json`
- 기준 예시 `fixtures/inputs/change/valid.md`와 `fixtures/expected/trace-v2.json`

## 작업 순서

1. 요청 문장을 항목화하고 원문 `MUST`, `SHOULD`, `MAY`를 보존하라.
2. 출처를 정확히 `user`, `elicited`, `inferred` 중 하나로 기록하고 출처 부재는 `UNKNOWN`으로 남겨라.
3. `REQ-EXT-<NNNN>` 안정 ID, `kind: tobe`, `evidence_ids`와 상태를 부여하라.
4. 중복·충돌·누락을 분리하고 사람 질문으로 받은 답만 `elicited`로 갱신하라.
5. 이후 5모드 `ui`, `mermaid`, `dataflow`, `story`, `test` 투영이 같은 `REQ-EXT-*`를 역대조하도록 `trace.jq`로 검증하라.

## 출력

- 검증 가능한 `extension_requirements[]` 후보와 중복·충돌·질문 목록을 반환하라.
- `UNKNOWN`, `unresolved`, `ambiguous`, `many_to_many`, `conflict`와 컨벤션 위반 가능성을 숨기지 마라.

## 근거 계약

- 근거 계약: 모든 확정 요구에 실제 `path:line`과 하나 이상의 `evidence_ids`를 연결하라.
- `inferred`를 `user`로 승격하거나 RFC 키워드를 약화하지 마라.

## 허용 도구와 권한

- 허용된 `jq -e`, `rg`, `mdq`만 읽기·파싱·검증에 사용하라.
- 스킬 로드는 권한을 추가하지 않는다. 현재 대상 저장소 안의 명시적으로 선택된 원본은 읽기 전용으로만 읽을 수 있다. 비밀 경로와 대상 저장소 밖은 읽지 말고, 쓰기는 현재 미션 루트 안에서 주 에이전트의 허용 경로에만 수행하라.

## 입학 상태

- 시작 상태는 `REQUIRED_TO_EVALUATE`다. 실패하면 `NOT_ADMITTED`, 순가치가 없으면 `ADMITTED_NO_VALUE`로 보존하라.
- 입학 고정 입력과 카탈로그 근거 및 사람 승인을 받은 `VALUE_PROVEN` 전에는 에이전트 허용 목록이나 설정에서 자동으로 활성화·승격하지 마라.

## 실패 처리

- 출처, 안정 ID, 키워드, 직접 근거 또는 검증기가 실패하면 사람에게 누락 입력을 요청하고 부분 산출물을 완료로 표시하지 않는다.
