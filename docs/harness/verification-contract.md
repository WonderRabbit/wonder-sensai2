# 하네스 검증 계약

## 검증 축

검증은 다음 축을 서로 대체하지 않게 분리한다.

| 축 | 판정자 | 현재 플랫폼 |
| --- | --- | --- |
| source contract | 파일 exact-set, parser, link 검사 | macOS |
| deterministic behavior | shell, jq, schema, fixture, mutation | macOS |
| OpenCode load | disposable HOME/XDG/stage의 safe projection | macOS, `1.18.3` |
| live model | 명시 승인된 모델 실험 receipt | `UNVERIFIED` |
| TUI/delegation | 실제 non-model 또는 승인된 session receipt | `UNVERIFIED` |
| Windows | 사용자가 release 후보로 실행한 signed/hashed receipt | `PENDING_USER_RECEIPT` |

macOS deterministic PASS는 Windows 영수증 없이 진행하고 완성할 수 있다. Windows는 H1/H2의 선행 blocker가 아니며 final user receipt만 담당한다. Windows receipt가 없다는 이유로 local implementation을 멈추지 않지만 cross-platform PASS를 주장하지도 않는다.

## 테스트 원칙

각 구현 task는 다음 순서를 따른다.

1. production edit 전 의도한 assertion failure를 관측한다.
2. assertion failure와 command-not-found, parser 오류, zero-case를 구분한다.
3. 최소 구현 후 같은 oracle이 green인지 확인한다.
4. missing, extra, duplicate, stale, mutation, misleading success를 대립 입력으로 확인한다.
5. 실제 사용자 표면을 수동 QA하고 cleanup을 기록한다.

`git diff --check`, grep hit, stale log, skipped case, worker 요약, ignored `STATUS.md`는 단독 PASS 증거가 아니다. unborn/untracked checkout에서는 tracked diff 밖의 파일을 포함한 whitespace 검사와 explicit file inventory가 필요하다.

## local implementation gate

`LOCAL_IMPLEMENTATION_PASS`는 다음이 모두 현재 workspace fingerprint에서 통과할 때만 허용한다.

- source-owned Markdown과 상대 링크
- `output/` relative literal agent 2 / command 9 / skill 15 exact-set와 36-leaf manifest target
- output 사람용 문구·표시명 한국어와 기계 식별자·문법 원형 보존
- trace/progress schema와 valid/invalid fixture
- jq validator와 target mutation
- permissions와 banned-runtime 검사
- manifest, stage, install transaction
- AS-IS/TO-BE deterministic projection과 render
- continuity, hard gate, single-writer, fresh-process resume
- disposable OpenCode `1.18.3` semantic load
- nonzero exact case count와 evidence audit

모델이 source로부터 trace를 생성하는 능력은 local deterministic projection과 별도다.

## false-success 대립 검사

- `dirty_worktree/unborn_baseline`: untracked 파일까지 fingerprint와 검사에 포함한다.
- `stale_state`: 오래된 status나 receipt의 workspace hash 불일치를 거부한다.
- `misleading_success_output`: PASS 문자열과 실제 exit/assertion count가 다르면 실패한다.
- `missing_upper_level_contract`: `docs/PROD.md`, mapping, harness 계약 중 하나라도 없으면 실패한다.
- `platform_drift`: macOS와 Windows 상태를 하나의 boolean로 축약하지 않는다.
- `config_merge`: inherited sentinel과 duplicate surface를 탐지한다.
- `debug_mutation`: source/global 전후 hash와 disposable tree 변화를 기록한다.
- `output_root_drift`: root runtime duplicate, `.opencode/`, output 누락, repo-side asset의 manifest 혼입을 거부한다.

## manual QA

문서 task는 실제 파일 inventory와 sentinel 검색을 그대로 실행한다. runtime task는 CLI, isolated load, render, mission state 같은 사용 표면을 직접 구동한다. 성공 기준은 exit 0뿐 아니라 예상 파일·내용·hash·부작용·cleanup까지 포함한다.

## 외부 상태 표기

- `MODEL_ADMISSION_UNVERIFIED`: live response/tool-use 비용을 쓰지 않았거나 입학 matrix가 불완전하다.
- `WINDOWS_RECEIPT_PENDING`: Windows kit 또는 실제 receipt가 아직 없다.
- `WINDOWS_RECEIPT_REJECTED`: receipt schema, version, case, hash, cleanup 중 하나가 실패했다.
- `WINDOWS_RECEIPT_ACCEPTED`: 사용자가 실제 Windows에서 실행한 current release receipt가 모든 항목을 만족한다.
