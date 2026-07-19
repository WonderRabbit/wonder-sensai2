---
name: sensai-convention-extract
description: "구조 후보와 원문 근거에서 고정된 7개 범주의 AS-IS 컨벤션을 추출하고 미확정·충돌 상태를 보존할 때 사용한다."
---

# 컨벤션 추출

도구 후보를 원문에서 재확인하고 근거 있는 규칙만 AS-IS 표준으로 적재하라.

## 입력

- 현재 미션 루트의 검증기 통과 또는 작성 중인 `trace.json`
- 구조 검색 후보와 원문 파일의 실제 `path:line`
- 7개 범주가 모두 있는 `fixtures/expected/trace-v2.json`과 근거 원문인 `fixtures/inputs/**`

## 작업 순서

1. 스택 발견 결과와 허용 `scope`를 확인하고 입증된 언어에만 구조 검색을 적용하라.
2. 후보의 선언·사용 원문을 다시 읽고 반복 가능한 규칙인지 확인하라.
3. 범주를 정확히 `COMPONENT`, `STRUCTURE`, `NAMING`, `API`, `STATE`, `ERROR`, `TEST` 중 하나로 분류하라.
4. `CONV-<CATEGORY>-<NNN>` 안정 식별자와 `kind: asis`, 예시, 추출기, 상태, 근거 식별자를 부여하라.
5. `trace.jq`로 중복 식별자, `category`, 직접 근거와 참조 무결성을 검증하라.

## 출력

- 스키마와 같은 `conventions[]` 및 연결된 `evidence[]` 후보를 반환하라.
- 모든 규칙에 실제 예시 하나 이상과 하나 이상의 `evidence_ids`를 포함하라.
- `DATAFLOW`는 컨벤션 범주가 아닌 산출물로 취급하고 7개 `category`에 추가하지 마라.

## 근거 계약

- 근거 계약: 모든 확정 사실에 실제 `path:line`과 하나 이상의 `evidence_ids`를 연결하라.
- 근거가 없으면 `UNKNOWN`, 동적으로만 결정되면 `unresolved`, 복수 후보면 `ambiguous`, 상충하면 `conflict`를 보존하라.
- 충돌 규칙을 하나로 축약하거나 이름 유사성만으로 범주·연결을 확정하지 마라.

## 허용 도구와 권한

- 허용된 `fd`, `rg --json`, `sg --json`, `jq -e`, `yq`만 읽기·구조 검색·검증에 사용하라.
- 스킬 로드는 권한을 추가하지 않는다. 현재 미션 루트 밖을 읽거나 쓰지 말고, 쓰기는 주 에이전트의 허용 경로에만 수행하라.
- 사용자 문자열을 셸 문법으로 실행하지 말고, 비밀 정보와 전역 설정을 읽지 마라.

## 입학 상태

- 시작 상태를 `REQUIRED_TO_EVALUATE`로 기록하고 정확성 고정 입력 실패는 `NOT_ADMITTED`, 순가치 부재는 `ADMITTED_NO_VALUE`로 보존하라.
- 사람 승인까지 받은 `VALUE_PROVEN`만 상시 필수 경로로 승격하라.

## 실패 처리

- 구조 도구가 언어를 지원하지 않으면 해당 범위를 `UNSUPPORTED`로 기록하라.
- `category`, 안정 식별자, 직접 근거 또는 검증기가 실패하면 부분 산출물을 완료로 표시하지 않는다.
