---
description: 새 미션의 계획부터 최종 승인까지 원장과 진행 상태를 직렬로 운영한다
agent: sensai-analysis-lead
subtask: false
---

# 미션 실행

`$ARGUMENTS`를 `<mission-id> <target-relative-path> <goal>` 형식의 데이터로만 해석하라. 사용자 문자열을 셸 문법, 옵션, 파이프, 리다이렉션 또는 명령 치환으로 실행하지 마라. `<mission-id>`는 `^[a-z0-9]+(-[a-z0-9]+)*$`를 만족해야 하고 정규 미션 루트는 정확히 `docs/analysis/missions/<mission-id>/`다. 전역 `progress.json`, 저장소 루트 상태 파일, 다른 미션과 전역 OpenCode 설정은 읽거나 쓰지 마라.

## F0 시작 선행조건

결정적 파일 초기화는 대상 저장소에서 `"$OPENCODE_CONFIG_DIR/bin/sensai" mission init <mission-id> <target-relative-path> <goal>`을 호출해 수행한다. `OPENCODE_CONFIG_DIR`가 비어 있거나 절대 경로가 아니거나 설치된 `bin/sensai`가 정규 실행 파일이 아니면 중단한다. 인자는 데이터로만 전달하고 사용자가 준 문자열을 다시 셸 코드로 조립하지 않는다. `CLI`가 `exit` `0`과 `INITIALIZED` 영수증을 반환하기 전에는 모델이 같은 파일을 대신 만들지 않는다.

다음 조건을 모두 통과하기 전에는 미션 파일을 쓰지 마라.

- 대상 경로는 저장소 상대 경로이고 빈 요소, `..`, 절대 경로와 심볼릭 링크 이탈이 없어야 한다.
- 같은 `<mission-id>`의 `progress.json` 또는 미션 잠금이 이미 있으면 새 미션으로 덮어쓰지 말고 `mission-already-exists` 또는 `progress.resume.concurrent`로 중단한 뒤 `/sensai/resume`을 안내한다.
- `trace.json`, 입력 집합, 현재 `git HEAD`와 `toolchain`의 실제 SHA-256을 결정적 도구로 계산한다. 파일이 없거나 해시 계산이 실패하면 영 문자열이나 추정값으로 채우지 않는다.
- `output/schemas/progress.schema.json`과 `output/recipes/progress.jq`를 실제로 읽고 검증할 수 있어야 한다. 검증기 부재나 비정상 종료를 지침 판단으로 우회하지 않는다.

같은 미션의 정규 상태는 `sensai-analysis-lead` 한 명만 직렬로 쓴다. 미션 루트의 전용 잠금을 원자적으로 획득하지 못하면 `progress.resume.concurrent`로 거부하고, 기존 잠금을 훔치거나 제거하지 마라. 잠금 소유자, 기준 `revision`과 기준 `progress.json` 해시가 모두 현재 미션과 일치할 때만 진행한다.

## `F0-F5` 흐름과 명령 소유권

순서는 고정하며 모델이 생략하거나 다시 합치지 않는다.

1. `F0`: 범위, 목표, 입력과 의존성을 계획하고 사람의 계획 승인을 기다린다.
2. `F1`: `/sensai/analyze`로 AS-IS 기술 사실과 컨벤션을 적재한다.
3. `F2`: `/sensai/analyze-business`로 AS-IS 비즈니스 사실을 적재한다. 조사는 F1과 나눌 수 있어도 같은 `trace.json` 병합은 직렬이다.
4. `F3`: `/sensai/document-asis`로 AS-IS 네 산출을 만들고 사람 승인을 기다린다.
5. `F4`: 승인된 AS-IS와 수정요청을 `/sensai/change-design`으로 설계하되 필요한 산출 후보 스킬이 `VALUE_PROVEN`으로 입학되고 명시적으로 허용되지 않았으면 `MODEL_ADMISSION_UNVERIFIED`로 중단한다.
6. `F5`: 같은 입학 조건이 충족된 경우에만 `/sensai/deliver`로 TO-BE 다섯 산출을 만들고 `/sensai/verify` 성공 후 사람의 미션 승인을 기다린다.

`/sensai/document-asis`, `/sensai/change-design`, `/sensai/deliver`의 소유권을 하나의 명령으로 합치거나 폐기된 단일 설계 명령을 호출하지 마라. 선행 단계 또는 결정적 검증이 실패하면 다음 단계로 넘어가지 않고 `blocked[]`, `unknowns[]`, `next`에 사실 그대로 기록한다.

## 사람 승인 영수증

`F0`, `F3`, `F5`는 `hard` 게이트다. 각 승인은 현재 원장·입력 지문과 결합된 정확한 `docs/analysis/missions/<mission-id>/approvals/<gate>-approval.json` 파일이어야 한다. `actor_role: human`, `source: elicited`, `verdict: accepted|rejected`, 비어 있지 않은 `reason`, `UTC` `recorded_at`과 실제 영수증 `SHA-256`을 확인한다.

승인 영수증은 `mission_id`, `gate`, `verdict`, `reason`, `actor_role`, `source`, `recorded_at`, `trace_sha256`, `inputs_sha256`만 가진 닫힌 JSON 객체다. `progress.json`의 승인 항목은 같은 값과 영수증 상대 경로·실제 해시를 가리켜야 한다. 현재 `trace` 또는 입력 지문과 맞지 않는 과거 영수증은 재사용하지 않는다.

- `F0`의 `accepted` 영수증 전에는 F1에 진입하지 않는다.
- `F3`의 `accepted` 영수증 전에는 F4에 진입하지 않는다.
- `F5`의 `accepted` 영수증 전에는 `status: completed`를 기록하지 않는다.

모델은 사람의 응답을 추정하거나 `accepted` 영수증을 만들지 않는다. `rejected`는 이유와 다음 사람 결정 지점만 기록하고 자동으로 승인으로 바꾸지 않는다.

## 체크포인트와 진실 우선순위

각 단계와 게이트 경계에서 다음 순서를 지켜라.

1. 검증된 `trace.json`과 산출물 해시를 먼저 확정한다.
2. 기존 `progress.json` 해시와 `revision`을 다시 읽어 잠금의 기준값과 비교한다.
3. 후보 `progress.json`은 이전 `revision + 1`, `precondition_fingerprints.previous_progress`와 현재 `trace`·`inputs`·`git_head`·`toolchain` 해시를 담는다.
4. 후보를 `progress schema`와 `progress.jq` `transition` 모드로 검증한다.
5. 검증 성공 뒤에만 같은 미션 디렉터리의 임시 파일을 원자적 rename하여 `progress.json`을 교체한다. 부분 파일이나 미검증 후보를 정규 경로에 남기지 않는다.
6. `progress.jq` `status` 모드의 출력으로 `status.md`를 생성하고, 마지막으로 세션 todo를 갱신한다.

검증된 후보 `progress`를 반영할 때는 `"$OPENCODE_CONFIG_DIR/bin/sensai" mission checkpoint <mission-id> <candidate-progress.json> <expected-revision> <expected-sha256>`을 사용한다. `exit` `75`는 다른 작성자가 먼저 갱신했거나 잠금이 있다는 뜻이므로 덮어쓰기나 자동 재시도를 하지 않는다.

진실 우선순위는 검증된 `trace.json` > 검증된 `progress.json` > 파생 `status.md` > 세션 `todo`다. `status.md`나 `todo`를 원장 또는 `progress`보다 먼저 쓰거나, 서로 다를 때 하위 뷰를 진실로 채택하지 마라.

## 세션 todo 규칙

OpenCode 내장 `todo`에는 현재 지원되는 `pending`, `in_progress`, `completed`만 사용한다. `blocked`를 기본 `todo` 상태로 만들지 말고 막힘은 `progress.json`의 `blocked[]`와 `todo` 항목 설명으로 표시한다. 한 번에 하나만 `in_progress`로 두고, 단계 완료는 결정적 영수증과 해당 체크포인트가 성공한 뒤에만 `completed`로 바꾼다.

중단, 예산 한계 또는 사람 대기 직전에는 현재 todo의 남은 작업 설명을 `todo_snapshot`에 작게 저장하고 체크포인트한다. 세션 전체 요약이나 모델 기억을 상태 파일에 복사하지 않는다.

## 실패와 종료

해시 불일치, 오래된 `revision`, 손상된 `progress`, 이중 재개, 동일 미션 동시 실행, 승인 누락과 검증 실패는 `fail-closed`다. 원장과 정규 `progress`를 변경하지 않고 이유 코드, 현재 `phase`, 마지막 검증된 `revision`, 다음 사람 결정만 보고한다. 잠금은 자신이 획득한 경우에만 정리하며, 성공·실패 모두 다른 미션과 전역 상태는 변경하지 않는다.
