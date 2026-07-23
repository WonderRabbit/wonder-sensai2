# wonder-sensai

`wonder-sensai`는 legacy codebase를 AS-IS 분석하고 TO-BE 변경을 설계하는 OpenCode 하네스다. 모델의 문장을 사실로 채택하지 않고, 결정적 CLI·schema·validator가 확인한 `path:line` 근거와 안정 ID를 canonical trace에 남긴다.

현재 checkout은 **RUNTIME_CLI + GLOBAL_INSTALLER + HERMETIC_LOAD** 단계다. 공개 계약, fail-closed test runner, root fixture corpus, packaging source인 `output/`, 정확히 2 agent·9 command·15 skill, schema·recipe와 stdlib-only Go CLI source `cmd/sensai/`가 있다. `stage`의 36개 config payload, 기존 전역 OpenCode config에 합류하는 `install`, 외부 CLI, 격리한 macOS OpenCode `1.18.3` semantic load를 검증한다.

제품 경계는 [제품 계약](docs/PROD.md), CodeGraph 운용은 [CodeGraph 하이브리드 분석 가이드](docs/codegraph-analysis-guide.md), Go CLI와 Windows 전달 경계는 [Go CLI Windows PRD](docs/PRD-go-cli-windows.md), tracked binary의 rebuild·commit·push 계획은 [bin artifact 전달 PRD](docs/PRD-bin-artifact-delivery.md), task 배치는 [R4 mapping](docs/r4-mapping.md), 충돌 해소는 [contract freeze](docs/harness/contract-freeze.md), runtime·검증·release 상태는 [runtime](docs/harness/runtime-contract.md), [verification](docs/harness/verification-contract.md), [release](docs/harness/release-contract.md), [implementation status](docs/harness/implementation-status.md)가 소유한다. `.gitignore` 대상인 로컬 `plan/`과 `STATUS.md`는 planning/status input일 뿐 runtime authority나 committed verification gate가 아니다.

## 동결된 실행 경계

- packaging source: `output/AGENTS.md`, `output/opencode.json`, `output/agents/`, `output/commands/`, `output/skills/`, `output/schemas/`, `output/recipes/`; `output/`이 유일한 canonical packaging source root이며 실행 중 탐색 경로가 아니다.
- repository-side: root `fixtures/`, `tests/`, `cmd/sensai/`, `go.mod`, tracked `bin/sensai`, tracked `bin/sensai.exe`, `docs/`, `manifest.txt`; manifest는 `output/` 기준 36개 config leaf만 나열하고 CLI artifact는 별도 관리한다.
- installed topology: Unix는 기존 물리 디렉터리 `$HOME/.config/opencode` 아래 managed config leaf 36개와 `$HOME/.local/bin/sensai`, Windows direct CLI는 `%USERPROFILE%\.config\opencode`와 `%USERPROFILE%\.local\bin\sensai.exe`다.
- payload topology target: exact 2 agents / 9 nested `sensai/*` commands / 15 skills
- OpenCode load baseline: exact `1.18.3`
- mission root: `docs/analysis/missions/<mission-id>/`
- truth priority: validated `trace.json` > validated `progress.json` > derived `status.md`와 in-session todo
- writer: primary lead 한 명만 canonical mission state를 작성하고 peer는 읽기 전용
- root `AGENTS.md`: contributor-only이며 fixture 계약을 설명한다. runtime prompt는 `output/AGENTS.md`이고 자동 로드를 가정하지 않는다.
- output language: 사람이 읽는 제목·설명·지침·표시명은 한국어로 작성하고, 기계 key/schema field/ID/path/command/skill/enum/reason code/문법은 정확히 보존한다.

`OPENCODE_CONFIG_DIR`는 다른 설정과 합쳐지는 overlay이므로 설정 격리를 보장하지 않는다. load 검증은 disposable stage, `HOME`, XDG 경로와 neutral working directory에서만 수행한다. 설치 위치는 이 변수와 무관하게 Unix `$HOME/.config/opencode`와 `$HOME/.local/bin/sensai`, Windows `%USERPROFILE%\.config\opencode`와 `%USERPROFILE%\.local\bin\sensai.exe`로 고정된다.

## 모델과 agent 계약

| Agent | Load baseline | 책임 | 현재 입학 상태 |
| --- | --- | --- | --- |
| `sensai-analysis-lead` | `zai/glm-5.2` | F0 초안, 의미 판정, peer 근거 재확인, mission single writer | `MODEL_ADMISSION=UNVERIFIED` |
| `sensai-evidence-peer` | `sensai-ollama/qwen3.5:9b` | 제한된 범위의 경로·줄 근거, 모순, 모호성, 미확인 수집 | `MODEL_ADMISSION=UNVERIFIED` |

이 alias는 config load를 위한 baseline이다. live response, tool call, streaming, structured output, delegation 성능을 검증했다는 뜻이 아니다. live model call은 별도 승인과 current-fingerprint receipt가 있어야 입학할 수 있다.

두 agent source는 `output/agents/`에만 있다. lead는 `primary`와 `zai/glm-5.2`를 명시하고 현재 미션 루트의 단일 작성자이며 `sensai-evidence-peer`만 호출한다. peer는 `subagent`, `hidden`, `sensai-ollama/qwen3.5:9b`를 명시하고 `edit`, `task`, `todowrite`, `question`을 거부한다. `small_model`은 peer 라우팅 규칙이 아니며 위임은 agent ID와 `permission.task`의 exact allow로 결정한다.

## 빠른 시작

```sh
./bin/sensai install
./bin/sensai doctor tools
./bin/sensai doctor models
./bin/sensai stage <absent-absolute-stage-path>
$HOME/.local/bin/sensai doctor models
$HOME/.local/bin/sensai mission init sample-mission fixtures/inputs/legacy-react 'AS-IS 분석과 TO-BE 변경 설계'
$HOME/.local/bin/sensai mission status sample-mission
```

빌드 prerequisite는 정확히 Go `1.26.5`이며 `go.mod`의 directive는 `go 1.26.0`이다. `$HOME/.local/bin`이 `PATH`에 있으면 설치 뒤 `sensai doctor models`처럼 호출해도 같다. `PATH`가 가리키는 실제 실행 파일은 정확히 `$HOME/.local/bin/sensai`여야 하며 symlink는 거부한다. source checkout에서는 tracked `./bin/sensai` 또는 그 절대 경로를 사용할 수 있다. source 호출과 installed 호출의 mission asset 선택은 같고, `stage`와 `install`만 source checkout 전용이다. 전달 artifact는 tracked `bin/sensai`와 `bin/sensai.exe`이고 semantic authority는 `cmd/sensai/`와 `go.mod`다. `dist/`는 ignored·noncanonical local scratch일 뿐 최종 전달 위치가 아니다. Windows OpenCode slash-command 연동은 별도 범위다.

`doctor tools`는 설치를 수행하지 않고 `opencode`, `fd`, `rg`, `sg`, `jq`, `yq`, `mdq`, `mmdc`의 실행 파일과 제품 식별을 확인한다. OpenCode는 정확히 `1.18.3`, `sg`는 ast-grep, `yq`는 Mike Farah 제품이어야 한다. `doctor models`는 자격증명 파일을 읽거나 모델을 호출하지 않고 canonical config와 toolchain lock의 정확한 alias·localhost transport 설정만 확인한다. 정상 출력 상태는 config discovery `READY`, lead/peer admission `UNVERIFIED`, `UNVERIFIED`다.

미션 상태는 `docs/analysis/missions/<mission-id>/` 아래 `trace.json`, `progress.json`, `status.md`로만 생성된다. `mission checkpoint`와 `mission resume`은 schema·recipe, 현재 revision과 SHA-256, 동일 미션 잠금을 확인하고 같은 디렉터리의 임시 파일을 원자적으로 rename한다. 사용자 인자는 데이터로만 다루며 셸 코드로 실행하지 않는다.

CLI 종료 코드는 `0` 성공, `64` 사용법 오류, `65` 입력·설정·제품 식별 오류, `69` 필수 도구 또는 transport 사용 불가, `73` stage 대상 생성 불가 또는 install managed 충돌, `75` lock·revision·hash 충돌이다. 이는 테스트 러너의 assertion `1`과 infrastructure `70` 계약과 별개다.

`stage <absent-absolute-stage-path>`는 `manifest.txt`의 36개 managed leaf를 부재한 절대 경로에 byte-exact 투영하며 CLI는 넣지 않는다. source와 stage의 SHA-256을 확인하고 같은 parent의 임시 sibling에서 완성한 뒤 한 번의 rename으로 공개한다. stage 대상이 이미 있으면 exit `73`으로 거부한다.

`install`은 인자를 받지 않는다. Unix는 이미 존재하는 물리 디렉터리 `$HOME/.config/opencode` 아래에 36개 managed leaf를 파일 단위로 설치하고 `$HOME/.local/bin/sensai`를 게시한다. Windows는 `%USERPROFILE%\.config\opencode`와 `%USERPROFILE%\.local\bin\sensai.exe`에 같은 규칙을 적용한다. managed leaf나 CLI가 없으면 생성하고, source와 byte-equal인 regular file이면 no-op이다. 내용이 다르거나 symlink·reparse point·directory·비정규 파일이면 쓰기 전에 `package.managed_conflict`, exit `73`으로 거부한다. config root의 기존 파일과 디렉터리 등 unmanaged content는 보존하며, 실패 시 이번 실행이 만든 expected-hash 파일과 빈 디렉터리만 회수한다.

mission의 schema·recipe는 파일별로 `<project>/.sensai/{schemas,recipes}`를 먼저 보고 해당 파일이 없을 때만 runtime global config의 `{schemas,recipes}`로 fallback한다. project 파일이 존재하지만 invalid, symlink, directory이면 global 파일로 우회하지 않고 fail closed한다. `opencode.json`과 `toolchain.lock.json`은 global config에서만 읽는다. project root는 `SENSAI_PROJECT_ROOT` 또는 물리 CWD지만 CWD의 `output/`이나 `$HOME/.local/output`은 runtime fallback이 아니다.

## Command catalog 목표

각 command source는 최종적으로 `output/commands/sensai/<name>.md`에 들어간다. 현재 flow에서 legacy 통합 design command는 사용하지 않으며 AS-IS 문서화, 변경 설계, TO-BE 전달의 소유권을 분리한다.

1. `/sensai/analyze` — F1 기술 분석
2. `/sensai/analyze-business` — F2 비즈니스 분석
3. `/sensai/document-asis` — F3 AS-IS 4종 투영과 hard gate
4. `/sensai/change-design` — F4 수정요청과 binding 설계
5. `/sensai/deliver` — F5 TO-BE 5종 투영
6. `/sensai/run` — F0-F5 mission 시작과 오케스트레이션
7. `/sensai/resume` — fingerprint와 revision을 검증한 재개
8. `/sensai/status` — 파생 progress/status 출력
9. `/sensai/verify` — schema, provenance, render 검증

Command 파일의 exact-set과 정적 계약은 구현됐지만 OpenCode TUI에서 실제 load 또는 모델 실행이 검증됐다고 주장하지 않는다.

## Skill catalog 목표

공통·기존 분석/투영 6종:

- `sensai-evidence-first`
- `sensai-react-trace`
- `sensai-vertx-trace`
- `sensai-spec-evidence`
- `sensai-ui-definition`
- `sensai-mermaid-sequence`

확장 분석·운영·전달 9종:

- `sensai-stack-discovery`
- `sensai-convention-extract`
- `sensai-business-trace`
- `sensai-dataflow-chart`
- `sensai-user-story`
- `sensai-test-scenario`
- `sensai-requirement-analyze`
- `sensai-change-design`
- `sensai-checklist`

각 skill source는 `output/skills/<name>/SKILL.md`에 위치하며 official frontmatter와 본문 계약, fixture, evidence, permission, admission 상태를 갖춰야 한다. 파일이 존재하고 exact-set test가 통과하기 전에는 구현 완료가 아니다.

## Trace와 convention 계약

`trace.json`은 canonical truth다. UI, Mermaid, dataflow, story, test는 trace에서 재생 가능한 표현물이며 원장을 대체하지 않는다. exact join은 양쪽 직접 근거를 요구하고, 동적 경로는 `unresolved`, 복수 후보는 `ambiguous` 또는 `many_to_many`, 충돌은 `conflict`로 남긴다. 이름 유사도로 빈 연결을 채우지 않는다.

CONVENTION_CATEGORIES: NAMING, STRUCTURE, COMPONENT, API, STATE, ERROR, TEST

`DATAFLOW`는 convention category가 아니라 AS-IS/TO-BE deliverable이며 provenance `dataflow` 모드로 검증한다.

## CodeGraph 하이브리드 분석

CodeGraph는 `fd`, `rg`, `sg`, direct source read와 runtime 검증을 대체하지 않는 optional extension candidate lane이다. 현재 `CODEGRAPH_ADMISSION=NOT_ADMITTED`이며 평가는 `REQUIRED_TO_EVALUATE`에서 시작한다. default·required path가 아니고 제품의 5개 확장 gate와 사람 승인을 모두 통과하기 전에는 입학을 주장하지 않는다. package는 MCP나 CodeGraph server/index를 설치·수정하지 않는다. 모든 unknown `codegraph_*` MCP 권한은 deny이고 exact `codegraph_explore`만 `ask`다. 사용자가 command 기반 MCP를 설정하고 CLI status admission 뒤 이 exact 요청을 승인하면 후보 평가에서 MCP explore를 우선한다. catalog 부재나 usable response 전 `timeout`, `deny`, `transport_error`에서는 같은 frozen packet으로 승인된 read-only CodeGraph CLI에 정확히 한 번 failover한다. persistent read-only permission은 capability projection일 뿐 admission이 아니다.

모든 graph route는 대상 저장소의 canonical real path를 고정한 뒤 정확히 `codegraph status . --json`부터 실행한다. `initialized=true`, `projectPath` 일치, 세 `pendingChanges` 값이 정수 `0`, `worktreeMismatch=null`, `index.reindexRecommended=false`인 경우만 query를 허용한다. 실패하면 `out_of_scope`, `stale_graph`, `unsupported`로 중단하고 graph query를 실행하지 않은 채 repo-local `rg` 또는 `sg`로 돌아간다. 하네스는 index 생성·갱신·동기화를 자동 수행하지 않는다.

한국어 원문은 `original_ko`로 보존하되 direct source에서 English term과 identifier/file anchor를 먼저 확인하고 byte·count cap을 검사한 뒤 graph query 전에 packet을 freeze한다. required field/type 누락이나 malformed 입력은 `unsupported`, cap 초과 입력은 `ambiguous`로 폐기한다. frozen query는 최대 1회이며 query, MCP, CLI는 끝까지 이 packet 하나만 사용하고 graph 결과로 query나 anchor를 정제하지 않는다. `query_en`은 ASCII 120바이트, symbol은 각각 160바이트, path는 각각 240바이트다. MCP나 CLI가 usable response를 냈지만 schema-invalid·`malformed`이거나 raw response가 65536바이트를 넘으면 전체를 폐기하고 각각 `unsupported` 또는 `ambiguous`로 중단한다. usable response 이후 실패에는 failover·retry·merge를 허용하지 않는다. 이 값은 call·file·numeric cap과 별도인 consumption cap이며 permission glob 자체가 response byte를 강제하지는 않는다. graph 결과는 candidate이며 lead가 현재 source의 `path:line`을 다시 확인해야 canonical evidence 후보가 된다. F3와 F4는 새 graph 탐색을 실행하지 않고 검증된 F1/F2 원장만 소비한다. 실제 명령, packet 예시, 도구별 장단점과 실패 대응은 [실전 가이드](docs/codegraph-analysis-guide.md)를 따른다.

persistent read-only CodeGraph CLI allow는 유지하지만 security boundary로 과장하지 않는다. OpenCode `1.18.3`은 shell AST의 각 command를 독립적으로 permission 평가하므로 현재 glob은 각 command의 argv shape·numeric flag와 secret·redirect 방어를 투영할 뿐, 개별 허용 command를 `|`, `;`, `&&`, `||`, `&`로 조합하는 일이나 per-turn·per-mission call count를 기계적으로 막지 못한다. “각 명령을 별도로 실행”, “pipe 금지”, “query 최대 1회”는 lead/skill behavioral budget이다. 이를 machine-enforced boundary로 만들려면 CodeGraph bash pattern을 `ask`/`deny`로 바꾸거나 외부 sandbox/wrapper가 필요하지만 현재 package는 그런 도구를 설치하지 않는다. MCP의 unknown `codegraph_*` deny와 exact `codegraph_explore` ask 경계는 그대로다.

## PRD alias와 의존 순서

bare T2와 R3 표기는 사용하지 않는다. canonical mapping은 다음과 같다.

- T2 program/charter → `T2-research-program.md`
- T2 experiment methodology → `T2-methodology.md`
- R3 CLI catalog → `R3-cli-tools.md`
- R3 tool integration → `R3-tool-integration.md`
- dependency order → `R3-cli-tools.md` → `I4-agent-update.md` → `R3-tool-integration.md`

이름이 사라진 이전 초안은 현재 authority가 아니다. Axis A의 current 단계는 `01-analysis.md`, `02-business-analysis.md`, `03-asis-deliverables.md`, `04-change-design.md`, `05-tobe-deliverables.md`다.

## 플랫폼 정책

macOS가 deterministic 구현과 QA의 현재 gate다. schema, jq recipe, fixture, transaction, projection, render, continuity, disposable OpenCode load를 macOS에서 끝까지 구현한다. Windows는 release 후보의 `sensai.exe`를 직접 전달받아 사용자가 실행하는 최종 receipt다. 실제 Windows 실행 전 상태는 `WINDOWS_COMPATIBILITY_UNVERIFIED`이고, Windows OpenCode slash-command 연동은 Scope OUT이다. Windows receipt는 H1/H2 선행 조건이 아니며, receipt 전에는 cross-platform 성공을 주장하지 않는다.

## 현재 검증

```sh
./tests/test.sh all
./tests/test.sh expect-fail misleading-success-output
./tests/test.sh self
./tests/test.sh docs
./tests/test.sh catalog-oracle
./tests/test.sh expect-fail stale-catalog-doc
./tests/test.sh expect-fail extra-skill
./tests/test.sh fixtures
./tests/test.sh schema-trace
./tests/test.sh expect-fail trace-dangling-id
./tests/test.sh recipe-trace
./tests/test.sh expect-fail evidence-free-glossary
./tests/test.sh provenance
./tests/test.sh expect-fail mismatched-mermaid-source
./tests/test.sh validators
./tests/test.sh expect-fail validator-noop
./tests/test.sh config
./tests/test.sh expect-fail config-claims-live-admission
./tests/test.sh agents
./tests/test.sh expect-fail peer-edit-enabled
./tests/test.sh permissions
./tests/test.sh expect-fail forbidden-mcp-config
./tests/test.sh doctor
./tests/test.sh expect-fail wrong-yq-product
./tests/test.sh packaging
./tests/test.sh expect-fail existing-install-target
./tests/test.sh core-readiness
./tests/test.sh continuity
./tests/test.sh expect-fail concurrent-mission-writer
./tests/test.sh opencode-load
./tests/test.sh expect-fail inherited-config-sentinel
```

- `self`: fail-closed runner, semantic failure, infrastructure failure, signal cleanup, unborn fingerprint를 확인한다.
- `all`: `tests/contracts/release-preflight.json`의 결정적 selector 53개를 각각 정확히 한 번 실행하고 각 current-fingerprint receipt를 다시 검증한다. 모델·TUI·live delegation·Windows 상태는 pass 수와 분리한다.
- `expect-fail misleading-success-output`: 출력에 `PASS`가 있어도 실제 exit와 assertion receipt가 실패이면 release preflight가 거부하는 경우만 인정한다.
- `docs`: tracked source-owned `README.md`, `risk.md`, `docs/`의 regular-file·로컬 Markdown 링크, README command/skill catalog, source-owned agent mapping, model/version/category/platform 계약과 대립 mutation을 결정적으로 확인한다. ignored 로컬 `plan/`과 `STATUS.md`는 committed gate가 아니다.
- `catalog-oracle`: `output/` 상대 literal 2 agents/9 commands/15 skills/2 schemas/5 recipes, 36-leaf config manifest와 별도 CLI, physical topology, root/runtime 분리, output 언어·config와 tracked source-owned docs의 output topology 언급을 확인한다. ignored 로컬 `plan/`과 `STATUS.md` parity는 검사하지 않는다.
- `schema-trace`: trace 2.0 schema, 고정 golden, 상태·결합 관계와 단일 필드 mutation의 jq 동등성을 확인한다.
- `expect-fail trace-dangling-id`: 격리한 유효 원장에 dangling evidence ID 하나를 주입하고 `trace.reference_integrity` 실패만 인정한다.
- `recipe-trace`: trace의 전역 ID·직접 근거·exact join·mapping·binding, glossary 근거, 1.0→2.0 보존과 재실행 안정성을 확인한다.
- `expect-fail evidence-free-glossary`: 격리한 glossary의 직접 근거만 제거하고 `glossary.direct_evidence` 실패만 인정한다.
- `provenance`: UI·Mermaid·dataflow·story·test 5모드의 exact ID·source·kind 역대조와 실제 `mmdc` SVG 렌더를 확인한다.
- `e2e-asis`: 검증된 canonical fixture trace에서 기술·비즈니스 fragment, glossary, AS-IS UI·시퀀스·데이터플로우·스토리 투영, provenance, 비어 있지 않은 SVG를 모델 호출 없이 결정적으로 검증한다. 이는 모델의 source→trace 도출 능력 증명이 아니다.
- `expect-fail mismatched-mermaid-source`: 격리한 시퀀스의 source만 관련 없는 유효 근거로 바꾸고 `provenance.source_mismatch` 실패만 인정한다.
- `validators`: `/private/tmp` 격리 복사본에서 critical schema·recipe 규칙 38개와 noop 1개를 약화해 기존 음성 테스트가 mutant를 잡는지 확인하고, 원본 복원 후 전체 selector가 다시 통과하는지 확인한다.
- `expect-fail validator-noop`: 격리한 trace parity validator를 noop으로 바꾸고 negative canary가 `validators.noop_detected`로 실패하는 경우만 인정한다.
- `config`: OpenCode `1.18.3` lock, baseline 모델, runtime instructions, compaction, deny-first 권한 순서와 금지된 확장 표면을 확인한다.
- `expect-fail config-claims-live-admission`: 격리한 model admission만 `VERIFIED`로 바꾸고 `config.model_admission` 실패만 인정한다.
- `agents`: 두 agent frontmatter의 exact model/mode, lead mission-root edit와 peer-only task, peer read-only 권한을 파싱해 확인한다.
- `expect-fail peer-edit-enabled`: 격리한 peer의 `edit`만 허용하고 `agents.peer_permission` 실패만 인정한다.
- `permissions`: last-match 규칙을 실제 허용·거부 입력에 투영해 mission write, peer read-only, exact task/skill, secret 경로, 셸 우회와 runtime source 경계를 확인한다. 이 검사는 OpenCode 정책 투영이며 운영체제 샌드박스 증명이 아니다.
- `expect-fail forbidden-mcp-config`: 격리한 config에 금지된 `mcp` key 하나를 추가하고 `permissions.forbidden_extension_config` 실패만 인정한다.
- `doctor`: 실제 도구 제품·OpenCode 1.18.3, 모델의 `READY/UNVERIFIED/UNVERIFIED`, 미션 init/status/checkpoint/resume의 path·schema·CAS·원자성과 종료 코드를 확인한다.
- `expect-fail wrong-yq-product`: 격리 PATH의 Python 계열 yq를 Mike Farah 제품으로 오인하지 않고 exit `65`와 `tool.identity_mismatch`로 거부하는 경우만 인정한다.
- `packaging`: 36-leaf config manifest, source/stage hash, 기존 global config의 unmanaged 보존, equal managed no-op, 외부 `$HOME/.local/bin/sensai`의 byte·실행 mode와 실제 mission init/status를 확인한다.
- `expect-fail existing-install-target`: differing managed leaf나 CLI 충돌의 exit `73`과 기존 global tree의 byte-exact 보존만 성공적인 거부로 인정한다.
- `expect-fail stale-catalog-doc`: isolated source copy에 stale catalog 항목을 넣고 named semantic assertion failure를 확인한다.
- `core-readiness`: runtime AGENTS/config/toolchain, 2/9/15 payload, schema/recipe, fixture, root manifest와 CLI가 모두 존재하는지 확인한다.
- `continuity`: 격리 mission 저장소에서 초기화, 체크포인트, 중단, 새 프로세스 재개, 단일 작성자와 F0/F3/F5 hard gate를 검증한다.
- `opencode-load`: 36-leaf config payload와 별도 설치 CLI를 disposable `HOME`에 배치하고 XDG·`TMPDIR`·중립 CWD에서 OpenCode `1.18.3` debug load를 실행해 2 agent·9 nested command·15 skill, config binding, idempotence와 알려진 초기화 파일만 확인한다. full resolved config와 모델 응답은 저장하지 않는다.
- `expect-fail inherited-config-sentinel`: disposable global config에 유효한 sentinel과 추가 command를 주입하고 merged overlay가 `opencode-load.inherited_sentinel`로 거부되는 경우만 인정한다.

증거는 명시한 `--evidence` 디렉터리에 source fingerprint, assertion, command exit, reason, cleanup과 함께 기록한다. exit `64`는 usage, `70`은 test infrastructure 문제이며 의도한 RED로 인정하지 않는다.

현재 terminal status는 `LOCAL_IMPLEMENTATION_PASS / MODEL_ADMISSION_UNVERIFIED / WINDOWS_TEST_UNAVAILABLE / WINDOWS_COMPATIBILITY_UNVERIFIED / MACOS_STATIC_SUBSTITUTE_PASS`다. macOS 대체 검사와 Windows cross-build는 현재 payload·설정·경로·quoting·checksum·artifact metadata의 host-side 결정적 범위만 뜻하며, Windows 네이티브 실행이나 호환성 성공을 주장하지 않는다.
