---
description: 미션의 원장과 진행 지문을 검증하고 정확한 다음 작업과 세션 todo를 복원한다
agent: sensai-analysis-lead
subtask: false
---

# 미션 재개

`$ARGUMENTS`를 `<mission-id>` 형식의 데이터로만 해석하라. 사용자 문자열을 셸 문법으로 실행하지 마라. `<mission-id>`는 `^[a-z0-9]+(-[a-z0-9]+)*$`를 만족해야 하고 정규 미션 루트는 정확히 `docs/analysis/missions/<mission-id>/`다. 전역 progress, 다른 미션과 전역 OpenCode 설정은 읽거나 쓰지 마라.

파일 기반 `CAS`와 원자적 `revision` 증가는 `./bin/sensai mission resume <mission-id> [<expected-revision> <expected-sha256>]`으로 수행한다. `CLI`의 `JSON projection`만 `todo` 복원 입력으로 사용하며 `exit` `65`, `69`, `75`를 모델 판단으로 성공 처리하지 않는다.

## 읽기와 검증 순서

재개 전에 아래 순서를 바꾸지 마라.

1. 물리 파일인 `trace.json`과 `progress.json`을 읽고 각각의 `SHA-256`, `progress` `revision`, 현재 `git HEAD`, `inputs`와 `toolchain` 지문을 계산한다.
2. `progress schema`와 `output/recipes/progress.jq` `validate` 모드로 문서 구조를 검증한다. JSON 손상, 필수 필드 누락, 다른 `mission_id` 또는 미션 경로는 `progress.resume.corrupt`로 중단한다.
3. 같은 미션의 전용 재개 잠금을 원자적으로 획득한다. 이미 잠겼으면 `progress.resume.concurrent`로 거부하고 잠금을 훔치거나 제거하지 않는다.
4. 잠금에 `mission_id`, 소유자, 기준 `revision`, 기준 `progress` `SHA-256`을 기록하고 다시 읽은 정규 `progress`와 `exact` 비교한다.
5. `progress.jq` `resume` 모드로 저장된 `trace`·`inputs`·`git_head`·`toolchain` 지문과 관찰값, 기대 `revision`, 기준 `progress` 해시와 잠금 소유권을 검증한다.

`progress` 해시가 달라졌으면 `progress.resume.stale_hash`, `revision`이 달라졌으면 `progress.resume.stale_revision`, 잠금의 기준 `revision` 또는 해시가 다르면 `progress.resume.double_resume`, `trace`와 입력 지문이 다르면 각각 `progress.resume.precondition_trace`, `progress.resume.precondition_inputs`로 중단한다. 손상 복구를 이유로 추정한 값을 정규 `progress`에 쓰지 말고, `trace.json`에서 재기준선 후보를 만드는 별도 사람 결정을 요청한다.

## 원자적 재개 체크포인트

검증이 끝나면 아직 현재 정규 `progress`가 잠금 기준 해시·`revision`과 같은지 다시 확인한다. 달라졌으면 동일 미션의 다른 세션이 앞선 것이므로 어떤 파일도 덮어쓰지 않는다.

- 후보는 현재 `phase`와 `status`를 임의로 전진시키지 않고, 이전 `revision + 1`과 이전 `progress` `SHA-256`을 `precondition_fingerprints.previous_progress`에 기록한다.
- 현재 관찰한 `trace`·`inputs`·`git_head`·`toolchain` 지문과 `UTC` 시각을 후보에 기록한다.
- `progress.jq` `transition` 모드와 `progress schema`가 모두 성공한 뒤 같은 미션 디렉터리의 임시 파일을 원자적 `rename`하여 `progress.json`을 한 번만 교체한다.
- 먼저 재개한 세션이 revision을 올리므로 같은 기준을 가진 두 번째 재개는 `progress.resume.stale_hash`, `progress.resume.stale_revision` 또는 `progress.resume.double_resume`로 실패해야 한다.

부분 후보, 임시 파일과 실패한 상태를 정규 `progress`로 사용하지 않는다. 완료된 `F5` 미션은 재개하지 않고 `/sensai/status`로 최종 상태만 읽는다.

## 상태와 todo 복원

원자적 `progress` 교체 뒤 진실 우선순위 `trace.json` > `progress.json` > `status.md` > `todo`를 적용한다.

1. 새 정규 progress를 `progress.jq` `status` 모드에 입력해 `status.md`를 재생성한다. 사람이 작성한 별도 상태 문장을 합치지 않는다.
2. `progress.jq` `resume` 모드가 반환한 `todo_snapshot`과 현재 `phase`를 사용해 세션 `todo`를 복원한다.
3. 이미 검증된 이전 단계는 `completed`, 정확한 다음 작업 하나만 `in_progress`, 나머지는 `pending`으로 둔다.

OpenCode 내장 `todo`에 `blocked` 상태를 발명하지 마라. 막힘은 `progress.json`의 `blocked[]`와 `todo` 항목 설명에 보존한다. `todo`가 소실되거나 `status`가 오래되어도 이를 원장과 `progress`보다 우선하지 않는다.

## 실패와 잠금 정리

실패하면 원장, `progress`, `status`와 `todo`를 변경하지 않고 이유 코드, 마지막 검증된 `revision`, 현재 `phase`, `next`, 필요한 사람 결정을 보고한다. 잠금은 이 세션이 획득했고 소유자 토큰이 일치할 때만 정리한다. 다른 세션 잠금, 다른 미션, 대상 코드와 전역 상태는 수정하지 않는다.
