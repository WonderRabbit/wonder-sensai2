# wonder-sensai 제품 계약

## 현재 상태

이 문서는 기존 27개 planning PRD에서 제품 경계와 입학 조건을 복구한 source-owned 상위 계약이다. 현재 저장소에는 36개 config payload, stdlib-only Go CLI와 global installer, schema·recipe·agent·command·skill과 결정적 검증이 있다. Go runtime 요구사항은 [Go CLI와 Windows 전달 PRD](PRD-go-cli-windows.md), tracked binary의 rebuild·commit·push 절차는 [bin artifact 전달 PRD](PRD-bin-artifact-delivery.md)가 소유한다. 이 구현은 live 모델 또는 Windows 호환성 완료를 뜻하지 않는다.

| 상태 축 | 현재 값 | 의미 |
| --- | --- | --- |
| `LOCAL_IMPLEMENTATION` | `GLOBAL_INSTALLER_READY` | 36개 managed config leaf, Go CLI, project/global overlay와 결정적 load가 구현됐다. |
| `MODEL_ADMISSION` | `UNVERIFIED` | 별칭 발견·로드 값은 정했지만 live 응답과 tool call은 검증하지 않았다. |
| `WINDOWS_RECEIPT` | `PENDING_USER_RECEIPT` | Windows 검증은 구현의 선행 조건이 아니라 최종 사용자 실행 영수증이다. |

## 제품 목적과 경계

`wonder-sensai`는 기존 코드베이스를 근거 중심으로 분석해 AS-IS를 이해하고, 사람 승인을 받은 수정요청을 TO-BE 설계와 산출물로 투영하는 OpenCode 전역 설치용 하네스다. canonical 사실은 mission별 `trace.json`이며, 모델 문장이나 파생 Markdown·SVG는 validator를 통과해도 원장을 대신하지 않는다.

제품 구현 기준은 다음과 같다.

- OpenCode 기준 버전은 `1.18.3`이다.
- CLI build prerequisite는 정확히 Go `1.26.5`이고 module은 `github.com/WonderRabbit/wonder-sensai2`이며 외부 Go module을 추가하지 않는다.
- `cmd/sensai/`와 `go.mod`가 CLI 동작의 semantic authority다. `bin/sensai`와 `bin/sensai.exe`는 이 source에서 exact matrix로 함께 재생성해 commit하는 tracked 전달 artifact이며 직접 수정하지 않는다.
- `dist/`는 사용해도 ignored·noncanonical local scratch일 뿐 release나 전달의 권위 경로가 아니다.
- `output/`은 설치 payload의 단일 packaging source다. runtime asset 탐색은 이 디렉터리나 실행 파일 parent로 fallback하지 않는다.
- packaging leaf는 `output/AGENTS.md`, `output/opencode.json`, `output/agents/`, `output/commands/`, `output/skills/`, `output/schemas/`, `output/recipes/`, `output/toolchain.lock.json` 아래 정확히 36개다.
- output의 사람이 읽는 제목·설명·지침·표시명은 한국어로 작성하고 기계 key/schema field/ID/path/command/skill/enum/reason code/문법은 원형을 보존한다.
- root `manifest.txt`는 `output/` 상대 managed config leaf 36개를 나열한다. `stage`는 부재한 절대 target에 이 leaf만 투영하고, `install`은 Unix의 기존 `$HOME/.config/opencode` 또는 Windows의 기존 `%USERPROFILE%\.config\opencode`에 파일 단위로 합류시킨다.
- installed CLI는 config root 밖의 Unix `$HOME/.local/bin/sensai` 또는 Windows `%USERPROFILE%\.local\bin\sensai.exe` 하나다. `install`은 인자를 받지 않고 platform별 exact `bin/` source layout에서만 실행된다.
- managed leaf나 CLI가 없으면 설치하고 byte-equal regular file이면 no-op이다. differing regular file, symlink, directory와 비정규 파일은 pre-write conflict이며 unmanaged content는 보존한다.
- runtime schema·recipe는 project `.sensai/{schemas,recipes}`의 같은 상대 파일을 우선하고 project 파일이 없을 때만 global config의 파일로 fallback한다. present-invalid project 파일은 fail closed한다.
- 목표 exact-set은 agent 2개, `sensai/*` command 9개, skill 15개다.
- fixture의 canonical source는 루트 `fixtures/`다.
- mission 상태와 산출물의 유일한 루트는 `docs/analysis/missions/<mission-id>/`다.
- primary lead만 mission 상태와 산출물을 쓰는 single writer다. peer는 읽기·근거 수집만 수행한다.
- macOS에서 deterministic 구현과 QA를 완료할 수 있다. Windows 실행은 release 후보가 준비된 뒤 사용자가 수행하는 최종 영수증이다.

## 모델 계약

초기 discovery/load 값은 다음 두 exact alias다.

| 역할 | alias | 현재 효력 |
| --- | --- | --- |
| lead | `zai/glm-5.2` | baseline discovery/load 값만 확정 |
| peer | `sensai-ollama/qwen3.5:9b` | baseline discovery/load 값만 확정 |

이 값은 모델 입학을 뜻하지 않는다. 별칭 발견, config load, model response, streaming, structured output, 단일·연속 tool call은 서로 다른 증거 축이다. 명시적 사용자 승인과 자격 증명 없이 live model call을 실행하지 않으며 `MODEL_ADMISSION=UNVERIFIED`를 유지한다.

## 워크플로와 사람 결정

| 단계 | 결과 | 전환 규칙 |
| --- | --- | --- |
| F0 | lead가 mission 범위와 계획을 draft | 사람이 명시적으로 승인해야 F1/F2로 진행 |
| F1 | AS-IS 기술 분석 | F3 입력의 한 축 |
| F2 | AS-IS 비즈니스 분석 | F3 입력의 한 축 |
| F3 | AS-IS 4종 산출 | 사람이 승인해야 TO-BE로 진행 |
| F4 | 수정요청, designs, bindings | 위반은 사람 판정 전까지 hard stop |
| F5 | TO-BE 5종 산출과 검증 | 사람이 최종 승인해야 mission 종료 |

hard gate는 F0, F3, F5, 일관성 violation, 후보 admission이다. lead는 F0 계획을 작성하지만 승인 verdict를 발명할 수 없다. 모든 human verdict는 현재 precondition fingerprint에 결합돼야 하며 stale approval은 재사용하지 않는다.

## 분석과 산출 계약

기술 convention category는 정확히 다음 7개다.

1. `stack`
2. `structure`
3. `naming`
4. `api_pattern`
5. `state`
6. `coding_standard`
7. `scaffold_pattern`

`DATAFLOW`는 convention category가 아니라 검증 대상 deliverable이다. AS-IS는 UI 정의서, 시퀀스, 데이터플로우, 사용자 스토리 4종이다. TO-BE는 같은 4종과 테스트 시나리오를 합친 5종이다. 모든 사실과 산출 요소는 안정적 ID와 직접 근거를 가지며, 근거 부족·복수 후보·충돌은 `UNKNOWN`, `unresolved`, `ambiguous`, `many_to_many`, `conflict`로 보존한다.

## CodeGraph 하이브리드 입학 계약

CodeGraph는 F1/F2의 cross-file 관계 후보를 좁히는 optional extension candidate lane이며 canonical source나 validator가 아니다. 현재 상태는 `CODEGRAPH_ADMISSION=NOT_ADMITTED`이고 후보 평가의 시작 상태는 `REQUIRED_TO_EVALUATE`다. default·required 분석 경로가 아니며 아래 route는 제품 입학 완료가 아니라 후보 평가 절차다. MCP permission은 unknown `codegraph_*`를 deny하고 exact `codegraph_explore`만 `ask`한다. package는 MCP나 CodeGraph server/index를 설치·수정하지 않는다. 사용자가 command 기반 MCP를 별도로 구성해도 CLI status admission을 먼저 통과하고 이 exact 요청을 승인한 경우에만 MCP explore가 primary route다. catalog 부재나 usable response 전 MCP `timeout`, `deny`, `transport_error`에서는 같은 frozen packet으로 package가 승인한 read-only CLI에 정확히 한 번 failover한다. MCP와 CLI를 경쟁 SSOT로 만들지 않는다.

route-level admission은 CLI 존재 확인과 정확한 `codegraph status . --json` 결과가 소유한다. `initialized=true`, canonical target root와 `projectPath` 일치, `pendingChanges.added|modified|removed`가 모두 정수 `0`, `worktreeMismatch=null`, `index.reindexRecommended=false`인 경우만 후보 평가의 graph query를 허용한다. 실패는 `out_of_scope`, `stale_graph`, `unsupported`로 보존하고 graph query를 0회로 유지한 채 repo-local `rg` 또는 `sg`로 fallback한다. catalog 존재, status PASS, persistent read-only permission은 capability projection일 뿐 확장 입학 증거가 아니다.

한국어 원문은 `original_ko`로 보존한다. lead는 direct source에서 English topic/framework term과 symbol/file anchor를 먼저 확인하고 `query_en` ASCII 120바이트, symbol별 160바이트, path별 240바이트와 count cap을 검사한 뒤 graph query 전에 one-subject·one-scope packet을 freeze한다. required field/type이 없거나 malformed인 입력은 `unsupported`, byte·count cap을 넘은 입력은 `ambiguous`로 폐기한다. 허용된 query는 최대 1회이며 query, MCP, CLI는 같은 packet을 사용하고 graph 결과로 query나 anchor를 정제하지 않는다. MCP 또는 CLI가 usable response를 반환했지만 schema-invalid·`malformed`이면 전체를 폐기하고 `unsupported`, raw response가 65536바이트를 넘으면 전체를 폐기하고 `ambiguous`로 중단한다. usable response 이후 실패에는 다른 transport failover, retry, merge를 허용하지 않는다. permission glob은 command shape와 numeric flag만 제한하며 response byte를 강제하지 않으므로, 전체 경로는 별도의 call·file·numeric cap과 consumption cap으로 제한될 뿐 완전한 기계적 bounded 실행이라고 주장하지 않는다. graph 결과는 candidate이며 lead가 현재 source의 direct `path:line`을 다시 확인하고 다른 failure mode의 도구와 합치기 전에는 canonical trace에 병합하지 않는다. 이 조합이 필요한 이유는 filesystem, lexical, AST, graph index, runtime이 서로 다른 사각지대를 가지기 때문이다.

persistent read-only CLI allow는 사용자 승인 경로로 유지한다. 다만 OpenCode `1.18.3`은 shell AST의 각 command를 독립적으로 permission 평가하므로 CodeGraph glob은 각 command의 argv shape·numeric flag와 secret·redirect 방어를 투영할 뿐, `|`, `;`, `&&`, `||`, `&`로 여러 개별 허용 command를 조합하거나 per-turn·per-mission call count를 초과하는 일을 기계적으로 막지 못한다. 각 명령 별도 실행, pipe 금지, query 최대 1회는 lead/skill behavioral budget이지 security boundary가 아니다. 기계적 강제가 필요하면 CodeGraph bash pattern을 `ask`/`deny`로 바꾸거나 외부 sandbox/wrapper를 사용해야 하며 현재 package는 이를 설치하지 않는다. unknown `codegraph_*` MCP deny와 exact `codegraph_explore` ask는 별도 경계로 유지한다.

F3는 검증된 F1/F2 원장만 AS-IS 산출로 투영하고 F4는 승인된 AS-IS 원장만 binding 설계에 사용한다. 두 단계 모두 새 graph discovery나 graph 호출을 실행하지 않는다. 필요한 관계가 `unsupported`, `unresolved`, `ambiguous`, `conflict`이거나 문서와 source가 불일치하면 산출·설계를 중단한다. 상세 운용은 [CodeGraph 하이브리드 분석 가이드](codegraph-analysis-guide.md)를 따른다.

## 제품 금지선

현재 구현에 다음을 추가하지 않는다.

- Node.js 또는 TypeScript 제품 runtime
- third-party Go module, wrapper shell, 범용 wrapper
- package가 설치·수정하는 plugin, MCP, custom tool 또는 CodeGraph server/index
- `codegraph init`, `index`, `sync`, `serve`, `uninit`, `install`, `upgrade` 자동 실행
- Yeoman 또는 코드 생성
- live model call, 자격 증명 복사, raw model transcript 저장
- managed 범위 밖의 전역 OpenCode 설정 수정 또는 기존 content 덮어쓰기
- commit, tag, push, publish

루트 `AGENTS.md`는 저장소 기여자와 fixture 관리 계약이다. runtime prompt는 `output/AGENTS.md`이며 staged config에서 자동 로드된다고 가정하지 않고, runtime 불변조건은 source-owned config, agent, command, skill에도 직접 둔다. 절대 경로의 `instructions` 의존은 허용하지 않는다.

## Go CLI와 확장 입학 게이트

현재 stdlib-only Go CLI는 기존 command·exit·`reason`, package transaction과 mission CAS를 보존하는 제품 runtime으로 입학했다. module source, exact Go `1.26.5`, 두 target과 Windows 증명 경계는 [Go CLI와 Windows 전달 PRD](PRD-go-cli-windows.md), tracked artifact 갱신과 Git 전달은 [bin artifact 전달 PRD](PRD-bin-artifact-delivery.md)를 따른다. 추가 wrapper, dependency 또는 확장 기능은 기본값이 `NOT_ADMITTED`다. 다음을 모두 만족할 때만 별도 변경으로 검토한다.

1. 현재 Go CLI와 독립 도구 조합이 실패하는 재현 fixture가 최소 2개 있다.
2. 후보가 실패를 복구하고 기존 오류 의미와 exit semantics를 보존한다.
3. 정확도, wall time, RSS, 안전성의 사전 threshold를 통과한다.
4. deterministic 회귀와 퇴출 경로가 있다.
5. 사람이 증거를 검토해 승인한다.

편의성이나 미래 가능성만으로는 입학할 수 없다.

CodeGraph는 이 확장 gate의 optional candidate lane이다. 현재 `CODEGRAPH_ADMISSION=NOT_ADMITTED`이며 새 평가 기록은 `REQUIRED_TO_EVALUATE`에서 시작한다. 위 5개 gate와 사람 승인을 모두 만족하기 전에는 route-level status PASS, MCP ask 승인, persistent read-only permission만으로 입학을 주장할 수 없다.

## 권위와 증거

source-owned 계약의 우선순위는 실제 schema·validator·runtime 동작과 검증 영수증, 본 문서와 `docs/harness/`, 파생 status 순이다. ignored `plan/`과 루트 `STATUS.md`는 구현 권위가 아니다. 현재 runtime 세부 계약은 [runtime-contract.md](harness/runtime-contract.md), 검증은 [verification-contract.md](harness/verification-contract.md), release 표기는 [release-contract.md](harness/release-contract.md), 역할·도구 매핑은 [r4-mapping.md](r4-mapping.md)를 따른다.
