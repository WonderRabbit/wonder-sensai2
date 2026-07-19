---
description: 미션 원장과 AS-IS·TO-BE 산출물의 스키마 provenance 렌더 영수증을 읽기 전용으로 검증한다
agent: sensai-analysis-lead
subtask: false
---

# 미션 결정적 검증

`$ARGUMENTS`를 `<mission-id> [asis|tobe|all]` 형식의 데이터로만 해석하라. 사용자 문자열을 셸 문법으로 실행하지 마라. 모드 생략값은 `all`이고 정규 미션 루트는 정확히 `docs/analysis/missions/<mission-id>/`다.

## 읽기 전용 경계

이 명령은 읽기 전용이다. 원장, 산출 파일, 승인, 영수증 또는 미션 상태를 쓰거나 작성·수정·삭제하지 않는다. `sensai-analysis-lead`가 검증을 조정하지만 정규 상태의 단일 작성자 권한을 이 명령에서 사용하지 않는다. 미션 루트 밖을 수정하지 않으며 대상 코드, 전역 OpenCode 설정과 다른 미션도 변경하지 않는다.

입력 누락, 경로 이탈, 심볼릭 링크, 다른 미션 ID 또는 지원하지 않는 모드는 검증 실행 전 거부한다. 사용자가 제공한 값은 명령, 옵션, 파이프, 리다이렉션 또는 명령 치환으로 실행하지 않는다.

## 검증 순서

1. `trace.json`과 선택한 산출이 현재 `source fingerprint`, `revision`, 입력 해시와 일치하는지 확인한다.
2. `trace schema`와 `trace.jq`를 적용하고 실제 종료 코드와 원장 해시를 수집한다.
3. AS-IS 모드는 `asis/ui.md`, `asis/sequence.mmd`, `asis/dataflow.mmd`, `asis/story.md`를 확인한다.
4. TO-BE 모드는 `tobe/ui.md`, `tobe/sequence.mmd`, `tobe/dataflow.mmd`, `tobe/story.md`, `tobe/test.md`를 확인한다.
5. 각 파일에 `provenance.jq`의 `ui`, `mermaid`, `dataflow`, `story`, `test` 중 정확한 모드를 적용한다. AS-IS에는 존재하는 네 모드만 적용한다.
6. `Mermaid` 원문은 `mmdc` 실제 종료 코드 `0`, 비어 있지 않은 `SVG`, 원문·`SVG` 해시가 기존 `render` 영수증과 일치하는지 확인한다.
7. `validator`·`render` 영수증의 실제 종료 코드, 해시와 판정을 표준 출력으로 요약한다. 검증 결과 자체를 새 영수증 파일로 쓰지 않는다.

## 근거와 실패 판정

모든 확정 요소는 안정 `ID`, 실제 `path:line`, 하나 이상의 `evidence_ids`로 원장에 `exact` 역참조돼야 한다. 근거가 없으면 `UNKNOWN`, 동적 값은 `unresolved`, 복수 후보는 `ambiguous` 또는 `many_to_many`, 상충은 `conflict`로 그대로 보고한다. 이름 유사성으로 누락된 연결을 보정하지 않는다.

`validator` 또는 렌더 종료 코드가 0이 아니거나 해시·`provenance`·`binding`·사람 승인 상태가 불일치하면 실패한 검증기, 대상 경로, 이유 코드와 다음 게이트만 보고한다. 파일을 고치거나 실패를 통과로 바꾸지 않는다.

## 역할 분리

근거 위치 재확인이 필요하면 `sensai-evidence-peer`에 `subtask: true`인 읽기 전용 단일 질문만 위임한다. 피어는 `path:line`, `evidence_ids`, 안정 ID, `UNKNOWN`, `unresolved`, `ambiguous`, `many_to_many`, `conflict`와 관찰한 종료 코드만 반환한다. `sensai-analysis-lead`는 이를 직접 재확인해 읽기 전용 판정만 직렬로 종합하며 누구도 이 명령에서 미션 파일을 작성하지 않는다.
