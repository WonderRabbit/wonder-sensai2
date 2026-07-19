# wonder-sensai

`wonder-sensai`는 legacy codebase를 AS-IS 분석하고 TO-BE 변경을 설계하는 OpenCode 하네스다. 모델의 문장을 사실로 채택하지 않고, 결정적 CLI·schema·validator가 확인한 `path:line` 근거와 안정 ID를 canonical trace에 남긴다.

현재 checkout은 **RUNTIME_CLI + FILESYSTEM_PACKAGING** 단계다. 공개 계약, fail-closed test runner, root fixture corpus, canonical `output/` runtime, 정확히 2 agent·9 command·15 skill, schema·recipe, repository-side `bin/sensai`와 36-leaf root manifest가 있다. disposable target의 stage/install 파일시스템 계약은 구현됐지만 OpenCode hermetic semantic load는 아직 주장하지 않는다.

제품 경계는 [제품 계약](docs/PROD.md), task 배치는 [R4 mapping](docs/r4-mapping.md), 충돌 해소는 [contract freeze](docs/harness/contract-freeze.md), runtime·검증·release 상태는 [runtime](docs/harness/runtime-contract.md), [verification](docs/harness/verification-contract.md), [release](docs/harness/release-contract.md), [implementation status](docs/harness/implementation-status.md)가 소유한다. `.gitignore` 대상인 `plan/prd/`의 정확히 27개 문서는 planning input이며 runtime authority가 아니다.

## 동결된 실행 경계

- runtime source: `output/AGENTS.md`, `output/opencode.json`, `output/agents/`, `output/commands/`, `output/skills/`, `output/schemas/`, `output/recipes/`; `output/`이 유일한 canonical runtime root
- repository-side: root `fixtures/`, `tests/`, `bin/`, `docs/`, `manifest.txt`; manifest leaf는 `output/` 기준 상대 경로이고 stage에서는 접두사를 제거한다.
- payload topology target: exact 2 agents / 9 nested `sensai/*` commands / 15 skills
- OpenCode load baseline: exact `1.18.3`
- mission root: `docs/analysis/missions/<mission-id>/`
- truth priority: validated `trace.json` > validated `progress.json` > derived `status.md`와 in-session todo
- writer: primary lead 한 명만 canonical mission state를 작성하고 peer는 읽기 전용
- root `AGENTS.md`: contributor-only이며 fixture 계약을 설명한다. runtime prompt는 `output/AGENTS.md`이고 자동 로드를 가정하지 않는다.
- output language: 사람이 읽는 제목·설명·지침·표시명은 한국어로 작성하고, 기계 key/schema field/ID/path/command/skill/enum/reason code/문법은 정확히 보존한다.

`OPENCODE_CONFIG_DIR`는 다른 설정과 합쳐지는 overlay이므로 설정 격리를 보장하지 않는다. load 검증은 disposable stage, `HOME`, XDG 경로와 neutral working directory에서만 수행한다.

## 모델과 agent 계약

| Agent | Load baseline | 책임 | 현재 입학 상태 |
| --- | --- | --- | --- |
| `sensai-analysis-lead` | `zai/glm-5.2` | F0 초안, 의미 판정, peer 근거 재확인, mission single writer | `MODEL_ADMISSION=UNVERIFIED` |
| `sensai-evidence-peer` | `sensai-ollama/qwen3.5:9b` | 제한된 범위의 경로·줄 근거, 모순, 모호성, 미확인 수집 | `MODEL_ADMISSION=UNVERIFIED` |

이 alias는 config load를 위한 baseline이다. live response, tool call, streaming, structured output, delegation 성능을 검증했다는 뜻이 아니다. live model call은 별도 승인과 current-fingerprint receipt가 있어야 입학할 수 있다.

두 agent source는 `output/agents/`에만 있다. lead는 `primary`와 `zai/glm-5.2`를 명시하고 현재 미션 루트의 단일 작성자이며 `sensai-evidence-peer`만 호출한다. peer는 `subagent`, `hidden`, `sensai-ollama/qwen3.5:9b`를 명시하고 `edit`, `task`, `todowrite`, `question`을 거부한다. `small_model`은 peer 라우팅 규칙이 아니며 위임은 agent ID와 `permission.task`의 exact allow로 결정한다.

## 빠른 시작

```sh
./bin/sensai doctor tools
./bin/sensai doctor models
./bin/sensai stage <absent-absolute-stage-path>
./bin/sensai install <absent-absolute-config-path>
./bin/sensai mission init sample-mission fixtures/legacy-project 'AS-IS 분석과 TO-BE 변경 설계'
./bin/sensai mission status sample-mission
```

`doctor tools`는 설치를 수행하지 않고 `opencode`, `fd`, `rg`, `sg`, `jq`, `yq`, `mdq`, `mmdc`의 실행 파일과 제품 식별을 확인한다. OpenCode는 정확히 `1.18.3`, `sg`는 ast-grep, `yq`는 Mike Farah 제품이어야 한다. `doctor models`는 자격증명 파일을 읽거나 모델을 호출하지 않고 canonical config와 toolchain lock의 정확한 alias·localhost transport 설정만 확인한다. 정상 출력 상태는 config discovery `READY`, lead/peer admission `UNVERIFIED`, `UNVERIFIED`다.

미션 상태는 `docs/analysis/missions/<mission-id>/` 아래 `trace.json`, `progress.json`, `status.md`로만 생성된다. `mission checkpoint`와 `mission resume`은 schema·recipe, 현재 revision과 SHA-256, 동일 미션 잠금을 확인하고 같은 디렉터리의 임시 파일을 원자적으로 rename한다. 사용자 인자는 데이터로만 다루며 셸 코드로 실행하지 않는다.

CLI 종료 코드는 `0` 성공, `64` 사용법 오류, `65` 입력·설정·제품 식별 오류, `69` 필수 도구 또는 transport 사용 불가, `75` lock·revision·hash 충돌이다. 이는 테스트 러너의 assertion `1`과 infrastructure `70` 계약과 별개다.

`stage`와 `install`은 정렬·중복 없음·정규화된 36개 `manifest.txt` leaf만 `output/` 접두사 없이 부재 중인 절대 경로에 배치한다. source와 stage의 SHA-256이 모두 같아야 하며, 동일한 parent filesystem의 sibling 임시 디렉터리에서 완성한 뒤 한 번의 rename으로 공개한다. 대상이 이미 있으면 merge·overwrite·backup 없이 exit `73`으로 거부하고 기존 대상은 바꾸지 않는다. 이 검증은 파일시스템 topology만 증명하며, 격리된 OpenCode semantic load는 별도 단계다.

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

## PRD alias와 의존 순서

bare T2와 R3 표기는 사용하지 않는다. canonical mapping은 다음과 같다.

- T2 program/charter → `T2-research-program.md`
- T2 experiment methodology → `T2-methodology.md`
- R3 CLI catalog → `R3-cli-tools.md`
- R3 tool integration → `R3-tool-integration.md`
- dependency order → `R3-cli-tools.md` → `I4-agent-update.md` → `R3-tool-integration.md`

이름이 사라진 이전 초안은 현재 authority가 아니다. Axis A의 current 단계는 `01-analysis.md`, `02-business-analysis.md`, `03-asis-deliverables.md`, `04-change-design.md`, `05-tobe-deliverables.md`다.

## 플랫폼 정책

macOS가 deterministic 구현과 QA의 현재 gate다. schema, jq recipe, fixture, transaction, projection, render, continuity, disposable OpenCode load를 macOS에서 끝까지 구현한다. Windows는 release 후보와 native PowerShell kit가 준비된 뒤 사용자가 실행하는 최종 receipt다. Windows receipt는 H1/H2 선행 조건이 아니며, receipt 전에는 cross-platform 성공을 주장하지 않는다.

## 현재 검증

```sh
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
```

- `self`: fail-closed runner, semantic failure, infrastructure failure, signal cleanup, unborn fingerprint를 확인한다.
- `docs`: Markdown 링크, exact 27 PRD, alias/catalog/model/version/category/platform/status 계약과 대립 mutation을 확인한다.
- `catalog-oracle`: `output/` 상대 literal 2 agents/9 commands/15 skills/2 schemas/5 recipes와 36-leaf manifest target, root/runtime 분리, 27 PRD topology parity를 확인한다.
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
- `packaging`: root manifest와 T05 oracle의 36-leaf exact-set, source/stage hash, 접두사 없는 topology, runtime AGENTS 포함, repository-side 자산 제외, 동일 parent 원자 이동과 source 불변을 확인한다.
- `expect-fail existing-install-target`: 기존 대상에 대한 exit `73`과 byte-exact 보존만 성공적인 거부로 인정한다.
- `expect-fail stale-catalog-doc`: isolated source copy에 stale catalog 항목을 넣고 named semantic assertion failure를 확인한다.
- `core-readiness`: runtime AGENTS/config/toolchain, 2/9/15 payload, schema/recipe, fixture, root manifest와 CLI가 모두 존재하는지 확인한다.

증거는 명시한 `--evidence` 디렉터리에 source fingerprint, assertion, command exit, reason, cleanup과 함께 기록한다. exit `64`는 usage, `70`은 test infrastructure 문제이며 의도한 RED로 인정하지 않는다.

현재 상태는 `LOCAL_IMPLEMENTATION=RUNTIME_CLI_FILESYSTEM_PACKAGING`, `MODEL_ADMISSION=UNVERIFIED`, `WINDOWS_RECEIPT=PENDING_USER_RECEIPT`다. 36-leaf manifest와 disposable stage/install은 구현됐지만 full payload semantic load, live model, TUI/delegation, Windows 또는 cross-platform 성공은 아직 주장하지 않는다.
