---
name: sensai-stack-discovery
description: "코드베이스의 매니페스트와 마커에서 기술·버전을 근거로 식별하고, 입증되지 않은 스택을 `UNSUPPORTED`로 보존할 때 사용한다."
---

# 스택 발견

스택을 미리 가정하지 말고 매니페스트 근거가 있는 기술과 버전만 확정하라.

## 입력

- 현재 미션 루트의 정규 `root`, 내부 `scope`와 선택적 사용자 힌트
- 매니페스트와 설정 파일, 소스 마커의 실제 `path:line`
- 후보 확인에는 `fixtures/inputs/legacy-react/src/OrdersPage.tsx`와 `fixtures/inputs/legacy-vertx/src/main/java/example/OrderVerticle.java`를 사용하라.

## 작업 순서

1. `root`와 `scope`가 현재 미션 루트 안인지 확인하라.
2. `fd`로 매니페스트를 찾고 `jq -e`·`yq`·`rg --json`으로 기술 식별자와 버전을 읽어라.
3. 설정·소스 마커는 후보로만 수집하고 매니페스트의 직접 근거로 다시 확인하라.
4. 입증된 항목에 안정 `E-STACK-*` 근거 ID를 부여하고 `COMPONENT` 컨벤션 후보로 전달하라.
5. 매니페스트가 없거나 버전을 입증할 수 없으면 `UNSUPPORTED-*`로 기록하고 기존 레시피에 강제 매핑하지 마라.

## 출력

- 입증된 스택마다 기술·버전, 안정 식별자, 근거 식별자와 `path:line`을 반환하라.
- 식별 실패는 `unsupported[]`의 `UNSUPPORTED-<NNN>`, `kind: asis`, 불확정 상태와 근거로 보존하라.
- `fixtures/expected/trace-v2.json` 형식에 맞는 `evidence[]`와 후속 `conventions[]` 입력을 반환하라.

## 근거 계약

- 근거 계약: 모든 확정 사실에 실제 `path:line`과 하나 이상의 `evidence_ids`를 연결하라.
- 근거가 없으면 `UNKNOWN`, 동적으로만 결정되면 `unresolved`, 복수 후보면 `ambiguous`, 상충하면 `conflict`를 보존하라.
- 사용자 힌트, 파일명 또는 소스 마커만으로 미확인 스택을 알려진 스택으로 승격하지 마라.

## 허용 도구와 권한

- 허용된 `fd`, `rg --json`, `jq -e`, `yq`만 읽기·식별·검증에 사용하라.
- 스킬 로드는 권한을 추가하지 않는다. 현재 미션 루트 밖을 읽거나 쓰지 말고, 쓰기는 주 에이전트의 허용 경로에만 수행하라.
- 사용자 문자열을 셸 문법으로 실행하지 말고, 비밀 정보와 전역 설정을 읽지 마라.

## 입학 상태

- 시작 상태를 `REQUIRED_TO_EVALUATE`로 기록하라. 고정 입력 재현성과 근거 정확도를 통과하지 못하면 `NOT_ADMITTED`, 순가치가 없으면 `ADMITTED_NO_VALUE`로 남겨라.
- 사람 승인까지 받은 `VALUE_PROVEN`만 상시 필수 경로로 승격하라.

## 실패 처리

- 매니페스트 부재, 파싱 실패 또는 버전 미확인은 `UNSUPPORTED`와 누락 입력으로 반환하라.
- 범위, 직접 근거 또는 결정적 검증이 실패하면 부분 산출물을 완료로 표시하지 않는다.
