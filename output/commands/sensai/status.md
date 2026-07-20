---
description: 검증된 progress에서 현재 단계 차단 항목과 다음 작업을 읽기 전용으로 표시한다
agent: sensai-analysis-lead
subtask: false
---

# 미션 상태 조회

`$ARGUMENTS`를 `<mission-id>` 형식의 데이터로만 해석하라. 사용자 문자열을 셸 문법으로 실행하지 마라. `<mission-id>`는 `^[a-z0-9]+(-[a-z0-9]+)*$`를 만족해야 하고 정규 미션 루트는 정확히 `docs/analysis/missions/<mission-id>/`다.

표시는 `"$HOME/.local/bin/sensai" mission status <mission-id>`의 검증된 Markdown 출력을 그대로 사용한다. `HOME`이 비어 있거나 절대 경로가 아니면 중단한다. 정확한 `"$HOME/.local/bin/sensai"`가 정규 실행 파일이 아니거나 `CLI`가 설치된 `runtime root`를 검증하지 못하면 중단한다. CLI 실패 시 오래된 `status.md`를 대신 보여주거나 모델이 상태를 추정하지 않는다.

미션에 필요한 schema와 recipe의 경로를 모델이 직접 조립하거나 읽어 검증하지 마라. 설치된 `CLI`가 각 파일을 대상 프로젝트의 `.sensai/{schemas,recipes}`에서 먼저 선택하고, 해당 project file이 없을 때만 전역 OpenCode config의 같은 파일로 fallback한다. project file이 존재하지만 invalid이면 전역 파일로 우회하지 않고 fail closed한다. 모델은 이 선택과 검증을 다시 구현하지 말고 성공한 `mission status`가 반환한 검증 결과만 그대로 사용한다.

## 읽기 전용 경계

이 명령은 읽기 전용이다. 원장, `progress.json`, `status.md`, 승인, 영수증, `todo`, 잠금 또는 미션 상태를 작성·수정·삭제하지 않는다. 대상 코드, 다른 미션, 저장소 루트의 전역 `progress`와 전역 OpenCode 설정도 변경하지 않는다. 상태 조회를 이유로 `checkpoint`, `revision` 증가, 잠금 획득 또는 `todo` 갱신을 수행하지 마라.

## 결정적 상태 파생

1. 정규 미션 루트의 물리 `trace.json`과 `progress.json`만 읽는다.
2. 설치된 `CLI`가 선택한 schema와 recipe로 `trace`와 `progress`의 `validate`를 수행한 결과만 사용한다.
3. 저장된 `trace`·`inputs`·`git_head`·`toolchain` 지문과 현재 관찰값을 비교한다.
4. 검증 성공 시 설치된 `CLI`가 반환하는 Markdown을 그대로 표시한다.
5. 기존 `status.md`가 있으면 파생 결과와 `byte exact` 비교해 `current` 또는 `stale`만 함께 보고하고 파일은 고치지 않는다.

출력은 현재 `phase`, 진행률, `status`, `revision`, `blocked[]`, `unknowns[]`, `next`, `todo_snapshot`, 원장과 `progress` 경로를 포함한다. 상태 문장을 모델이 새로 요약하거나 `status.md`를 진실 원장처럼 읽지 않는다. 진실 우선순위는 검증된 `trace.json` > 검증된 `progress.json` > 파생 `status.md` > 세션 `todo`다.

검증 실패, 해시 불일치, 심볼릭 링크, 다른 `mission ID` 또는 손상된 `JSON`이면 마지막으로 검증할 수 있었던 경로와 이유 코드만 출력하고 상태를 추정하지 않는다. `blocked[]`가 있어도 OpenCode 기본 `todo`의 `blocked` 상태로 변환하지 않는다.
