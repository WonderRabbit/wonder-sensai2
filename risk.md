# wonder-sensai2 완료 가능성 및 리스크

평가일: 2026-07-19

## 결론

현재 source-owned 계약, fail-closed runner, root fixture corpus, 27-PRD reconciliation, `output/` topology와 literal target catalog 이후의 **macOS deterministic local implementation 완료 가능성은 66%**로 평가한다. live model admission과 실제 Windows 사용자 receipt까지 포함한 외부 완결 가능성은 **36%**다. 두 수치는 통계적 확률이 아니라 현재 증거에 기반한 비보정 engineering forecast이며 기본 불확실성은 ±10%p다.

Windows는 local 구현의 H1/H2 선행 조건이 아니다. macOS에서 runtime, fixture, validator, isolated OpenCode load, release 후보를 먼저 완성한 뒤 Windows 사용자가 최종 receipt를 실행한다. 따라서 Windows 미가용은 local 진행률을 낮추거나 막지 않지만 cross-platform 완료는 계속 미확인으로 남긴다.

## 상태별 전망

| 범위 | 현재 중앙값 | 완료로 인정하는 조건 |
| --- | ---: | --- |
| 계약 동결 | 100% | source-owned 상위·runtime·verification·release 계약, G-00 증거 |
| macOS 최소 deterministic MVP | 72% | schema/validator + root fixture + 1개 projection/render + mutation |
| macOS local implementation 전체 | 66% | exact 2/9/15, permissions, packaging, continuity, isolated `1.18.3` load, preflight |
| live model admission | 38% | 승인된 credential로 response/tool-call/stream/structured-output matrix 통과 |
| Windows final receipt | 55% | current release 후보를 사용자가 실제 Windows에서 실행한 schema-valid receipt |
| 외부 상태 포함 전체 완료 | 36% | local gate + model admission + Windows receipt 모두 현재 fingerprint에 결합 |

각 확률은 독립이 아니며 서로 더하거나 곱하지 않는다. 실제 gate가 통과할 때만 재평가한다.

## 평가 가정

- macOS deterministic 구현과 QA는 Windows 호스트 없이 순서대로 계속한다.
- Windows 사용자는 local release 후보와 native PowerShell kit가 준비된 뒤 최종 receipt만 실행한다.
- OpenCode 기준 버전은 exact `1.18.3`이며, 다른 버전은 별도 drift 판정 대상이다.
- lead `zai/glm-5.2`와 peer `sensai-ollama/qwen3.5:9b`는 discovery/load baseline일 뿐 live model admission이 아니다.
- credential과 모델 비용 권한은 현재 범위에 없으며 live call을 하지 않는다.
- `output/` 하나만 runtime source로 사용하고 root runtime duplicate와 `.opencode/` 복사본을 만들지 않는다.
- `OPENCODE_CONFIG_DIR`는 merged overlay이며 isolation으로 간주하지 않는다.
- root `AGENTS.md`는 contributor/fixture 관리 계약이며 T05 승인 변경 이후 새 hash로 보호한다. runtime 계약은 `output/AGENTS.md`이고 staged 자동 로드에만 의존하지 않는다.
- implementation은 shell과 독립 CLI로 한정하고 Node/TS/Go/plugin/MCP/custom tool/Yeoman을 추가하지 않는다.
- output의 사람용 문구와 표시명은 한국어로 작성하고 기계 key/schema field/ID/path/command/skill/enum/reason code/문법은 원형을 보존한다.
- commit, tag, push, publish 없이 unborn/untracked workspace receipt로 진행한다.

## 현재 증거

### 확인됨

- `plan/prd/`에는 27개 PRD가 있다.
- 제품, mapping, contract freeze, runtime, verification, release, implementation-status 계약이 source-owned `docs/`에 존재한다.
- fail-closed test/receipt bootstrap과 semantic docs selector가 current source fingerprint를 검사한다.
- 27개 PRD exact catalog, T2/R3 alias mapping, 9 command/15 skill target 문서가 정합한다.
- `output/` single runtime source, exact 2 agents/9 commands/15 skills, root `fixtures/`, mission root, single writer, 7 convention category가 동결됐다.
- root fixture corpus는 35 inventory leaves, 37 physical leaves, 14 happy/14 adversarial로 검증됐다.
- baseline config는 처음 root에서 `output/opencode.json`으로 byte-identical 이동한 뒤 사람용 provider/model 표시명만 한국어화했고, 기계 필드는 exact 검증으로 고정했으며 root duplicate는 제거됐다.
- `output/AGENTS.md`와 output 상대 36-leaf manifest target catalog가 생겼다. future agent/command/skill/schema/recipe leaf의 존재를 뜻하지는 않는다.
- output의 한 단어·짧은 문장·제목·목록 영어 자연어 주입을 거부하고 형식화된 기계 식별자·코드는 허용하는 로컬 언어 oracle을 수리했다. 독립 재검증은 `PENDING`이다.
- macOS local gate와 Windows final receipt가 분리됐다.
- `AGENTS.md` pre-edit SHA-256은 `64d0ffefedf2df07095a3316ebf48586366a4565cf1d3f8bed596e054c3c4866`으로 기록됐다.

### 아직 없음

- output schema, recipe, validator mutation, root manifest, installer
- output agents, commands, skills runtime leaves
- deterministic AS-IS/TO-BE projection과 continuity 증거
- disposable HOME/XDG/neutral-CWD의 OpenCode semantic load
- live model response/tool-use/TUI/delegation 증거
- Windows receipt kit와 실제 사용자 receipt
- Git HEAD 기반 baseline

## 핵심 리스크

| ID | 리스크 | 가능성 | 영향 | 현재 노출 | 완화 | 종료 게이트 |
| --- | --- | --- | --- | --- | --- | --- |
| R-01 | greenfield runtime 구현 | 높음 | 치명적 | runner/fixture/output 계약은 생겼지만 핵심 agent/command/skill/schema/recipe 실행 leaf가 없다. | strict-serial TDD, 최소 MVP 먼저 | schema/recipe와 최소 projection 실제 통과 |
| R-02 | model baseline과 admission 혼동 | 높음 | 치명적 | exact alias는 동결됐지만 응답·tool call은 미확인이다. | discovery/load/live 상태를 분리 | 승인된 live admission matrix와 receipt |
| R-03 | 27개 PRD 범위 팽창 | 높음 | 높음 | analysis, delivery, continuity, packaging이 한 제품에 있다. | T01-T30 strict serial과 MVP 금지선 | 각 task 증거가 현재 fingerprint에 연속 결합 |
| R-04 | config merge를 isolation으로 오인 | 높음 | 치명적 | `OPENCODE_CONFIG_DIR`는 다른 config 층과 merge될 수 있다. | disposable HOME/XDG, neutral CWD, inherited sentinel | exact 2/9/15 semantic projection, inherited/duplicate 0 |
| R-05 | sLLM tool-use와 장기 흐름 미입학 | 높음 | 치명적 | 모델 관련 값은 전부 discovery/load 또는 predicted다. | deterministic core 먼저, live admission 별도 | tool-call 인자·근거·stream·structured output 기준 통과 |
| R-06 | Windows platform drift | 중간 | 높음 | quoting, NUL, Chromium, PowerShell 안전성은 미확인이다. | local 구현 후 native kit + 최종 사용자 receipt | current release hash의 `WINDOWS_RECEIPT_ACCEPTED` |
| R-07 | oracle/golden 범위 부족 | 중간 | 높음 | root corpus와 fixture oracle은 생겼지만 후속 schema/recipe/permission/projection oracle은 아직 없다. | task별 failing-first mutation을 누적 | false-green mutation을 잡고 전체 deterministic suite 통과 |
| R-08 | permission을 sandbox로 오인 | 중간 | 치명적 | prompt/permission만으로 OS secret·외부 경로를 강제할 수 없다. | disposable filesystem/HOME/network와 adversarial case | secret/external/write bypass 0, 전후 hash 동일 |
| R-09 | mission single-writer/continuity 실패 | 중간 | 높음 | progress schema, lock, atomic write가 없다. | mission root, revision/hash precondition, atomic rename | interrupt/resume/stale/corrupt/double-writer case 통과 |
| R-10 | 상위 계약 누락·source drift | 중간 | 높음 | T01에서 문서를 복구했지만 runtime은 아직 연결되지 않았다. | docs link와 runtime semantic parity 검사 | missing link 0, ignored plan runtime dependency 0 |
| R-11 | OpenCode/CLI 버전 drift | 중간 | 높음 | contract는 `1.18.3`, 실제 future environment는 변할 수 있다. | exact version lock과 doctor identity | current version projection과 drift failure receipt |
| R-12 | unborn/untracked baseline | 높음 | 높음 | HEAD가 없고 핵심 파일이 untracked라 `git diff`가 증거를 누락한다. | explicit inventory, all-file SHA-256, untracked whitespace 검사 | source fingerprint와 task별 before/after receipt |
| R-13 | stale `STATUS.md`가 성공으로 오인 | 높음 | 높음 | 과거에는 존재하지 않는 payload PASS와 잘못된 개수를 주장했다. | ignored/non-authoritative 표시, workspace hash 결합 | stale success phrase 0, status가 source evidence와 일치 |
| R-14 | `opencode debug`의 source/global mutation | 중간 | 치명적 | debug 초기화가 `.gitignore` 등 파일을 쓸 수 있다. | source/real HOME에서 실행 금지, disposable tree만 사용 | source/global 전후 SHA 동일, disposable mutation exact |
| R-15 | platform gate 정책 회귀 | 중간 | 높음 | 오래된 PRD가 Windows를 H1/H2 선행 조건으로 둔다. | source-owned verification 계약과 todo H7 final gate | early-Windows blocker 0, receipt 상태 별도 유지 |
| R-16 | runtime `AGENTS.md` implicit-load 오인 | 중간 | 높음 | `output/AGENTS.md`가 생겼지만 custom config에서 자동 로드된다는 보장은 아직 없다. | manifest에는 포함하되 config/agent/command/skill에도 불변조건 강제 | neutral CWD stage load와 단일 surface 제거 mutation 통과 |
| R-17 | output/root topology 회귀 | 중간 | 치명적 | 이전 계약과 PRD에는 과거 root-runtime source 표현이 있었고 future 구현이 root에 leaf를 만들 수 있다. | 27 PRD topology marker, literal catalog, root duplicate mutation | output 외 runtime leaf 0, manifest union 36, docs parity PASS |

## 재평가 게이트

| 시점 | 중앙값 변화 기준 |
| --- | --- |
| T05 literal catalogs | extra/missing을 잡는 exact oracle이 생기면 local 위험 감소 |
| T10 validator mutation | schema/recipe false-green이 실제 검출되면 deterministic 신뢰 상승 |
| T20 packaging | source/stage/install transaction과 global invariance가 통과하면 배포 위험 감소 |
| T25 continuity | fresh-process resume와 same-mission contention이 통과하면 운영 위험 감소 |
| T26 isolated load | OpenCode `1.18.3` exact 2/9/15 load가 통과하면 config 위험 크게 감소 |
| T27 local preflight | `LOCAL_IMPLEMENTATION_PASS` 요건이 충족되면 local 확률 대신 현재 PASS로 전환 |
| 모델 admission | 사용자 승인된 live matrix가 통과할 때만 모델 축 갱신 |
| Windows receipt | current release fingerprint의 실제 사용자 receipt를 받을 때만 Windows 축 갱신 |

## 중단 또는 재협상 조건

- deterministic validator 없이 모델 판정만으로 성공을 선언해야 한다.
- `output/` source가 아닌 root runtime copy, `.opencode/` 복사본이나 실제 전역 설정 수정이 필수라고 입증된다.
- Node/TS/Go/plugin/MCP/custom tool/Yeoman이 실패 fixture 없이 필수로 요구된다.
- single-writer 또는 atomic/precondition 계약 없이 동일 mission 병렬 쓰기가 요구된다.
- live credential, 비용, Windows 실행을 로컬 구현의 선행 조건으로 되돌리려 한다.

이 경우 범위를 확장하거나 성공을 강하게 표현하지 않고 해당 축을 `UNVERIFIED` 또는 `PENDING_USER_RECEIPT`로 유지한다.
