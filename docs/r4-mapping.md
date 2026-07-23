# 작업·에이전트·도구 매핑

## 상태

이 문서는 27개 PRD의 R4 결정을 source-owned 목표 계약으로 승격한다. runtime source는 유일한 `output/` root이며 agent는 `output/agents/`, command는 `output/commands/`, skill은 `output/skills/`에 둔다. 아래 목록은 구현 target이며 현재 future leaf 존재나 모델 입학을 주장하지 않는다.

output에서 사람이 읽는 agent/command/skill 설명과 지침은 한국어로 작성한다. 기계 ID, path, command/skill name, enum, reason code와 문법은 exact-set 그대로 보존한다.

## exact-set 목표

### Agent 2개

| agent | mode | model discovery/load 값 | 책임과 권한 |
| --- | --- | --- | --- |
| `sensai-analysis-lead` | primary | `zai/glm-5.2` | 범위·의미·판정·산출, primary single writer, peer에만 위임 |
| `sensai-evidence-peer` | hidden subagent | `sensai-ollama/qwen3.5:9b` | 제한된 읽기 전용 근거 수집, 편집·재위임·최종 판정 금지 |

두 모델 값은 discovery/load baseline일 뿐이다. `MODEL_ADMISSION=UNVERIFIED`다.

### Command 9개

| command | 소유 단계 | 핵심 출력 |
| --- | --- | --- |
| `/sensai/analyze` | F1 | AS-IS 기술 trace와 7범주 convention |
| `/sensai/analyze-business` | F2 | 비즈니스 사실과 glossary |
| `/sensai/document-asis` | F3 | AS-IS 4종 산출 |
| `/sensai/change-design` | F4 | 수정요청, designs, bindings |
| `/sensai/deliver` | F5 | TO-BE 5종 산출 |
| `/sensai/verify` | 공통 | schema, provenance, 구조, render의 read-only 판정 |
| `/sensai/run` | F0-F5 | mission 시작과 전체 흐름 운영 |
| `/sensai/resume` | 연속성 | precondition 검증 후 todo 복원 |
| `/sensai/status` | 연속성 | progress에서 파생한 현재 뷰 |

legacy `/sensai/design`은 target exact-set에 없다.

### Skill 15개

| 구분 | skill |
| --- | --- |
| 공통 근거 | `sensai-evidence-first` |
| 고정 trace 가속기 | `sensai-react-trace`, `sensai-vertx-trace`, `sensai-spec-evidence` |
| 기본 투영 | `sensai-ui-definition`, `sensai-mermaid-sequence` |
| 분석 확장 | `sensai-stack-discovery`, `sensai-convention-extract`, `sensai-business-trace` |
| 산출 확장 | `sensai-dataflow-chart`, `sensai-user-story`, `sensai-test-scenario` |
| TO-BE | `sensai-requirement-analyze`, `sensai-change-design` |
| 품질 | `sensai-checklist` |

각 skill은 fixture, metric, threshold, 사람 승인을 가진 admission 증거가 생긴 뒤 agent allowlist에 들어간다. exact-set target 자체가 입학 증거를 대체하지 않는다.

## 작업 매핑

| task | writer/worker | skill | 결정적 도구 | 결과 규칙 |
| --- | --- | --- | --- | --- |
| stack discovery | peer 수집, lead 확인 | stack-discovery | `fd`, `rg`, `jq`, `yq` | 미식별은 `UNSUPPORTED` |
| 구조 후보 | peer | react/vertx/spec trace | `sg`, `rg` 구조화 출력 | 후보는 사실이 아님 |
| 관계 후보 (F1/F2) | peer 수집, lead 재확인 | evidence-first | admission된 CodeGraph MCP/CLI, `rg`, `sg` | graph edge는 candidate, direct `path:line` 필수 |
| convention 판정 | lead | convention-extract | `sg`, `jq` | 7 category, 각 직접 근거 |
| business 사실 | peer 수집, lead 판정 | business-trace | `sg`, `rg`, `jq`, `yq` | 암묵 규칙은 `UNKNOWN` |
| AS-IS 투영 | lead | UI, sequence, dataflow, story | `jq`, `mdq`, `mmdc` | DATAFLOW는 deliverable |
| 수정요청 분석 | lead | requirement-analyze | `jq`, `mdq` | source와 modality 보존 |
| 변경 설계 | lead | change-design | 검증된 원장, `sg`, `rg`, `jq` | 새 graph 호출 금지, binding과 violation gate 필수 |
| TO-BE 투영 | lead | UI, sequence, dataflow, story, test | `jq`, `mdq`, `mmdc` | 5-mode provenance |
| 독립 검증 | peer 조사, 결정적 validator 판정 | evidence-first, checklist | `jq`, `mdq`, `mmdc` | 모델 성공 문장 불인정 |

## CodeGraph route와 단계 제한

- CodeGraph는 확장 입학 게이트의 optional candidate lane이며 현재 `CODEGRAPH_ADMISSION=NOT_ADMITTED`, 평가 시작 상태는 `REQUIRED_TO_EVALUATE`다. default·required path가 아니고 5개 확장 gate와 사람 승인 전에는 입학을 주장하지 않는다. persistent read-only permission은 capability projection일 뿐 admission이 아니다.
- unknown `codegraph_*` MCP는 deny하고 exact `codegraph_explore`만 `ask`한다. 사용자가 command 기반 MCP를 구성했더라도 먼저 CLI `codegraph status . --json`으로 canonical root와 freshness를 입학 판정한다. 통과하고 exact 요청을 승인한 경우에만 MCP explore가 primary route다. catalog 부재나 usable response 전 MCP `timeout`, `deny`, `transport_error`에서는 같은 frozen packet으로 승인된 read-only CLI에 정확히 한 번 failover한다.
- scope·freshness admission 실패 시 graph call을 열지 않고 `rg` 또는 `sg`로 돌아간다.
- 한국어 원문은 `original_ko`로 보존한다. direct source에서 English term과 symbol/file anchor를 확인하고 byte·count cap을 검사한 뒤 첫 query 전에 packet을 freeze한다. graph 결과로 packet을 정제하지 않으며 query→MCP→CLI failover까지 같은 packet을 사용한다.
- required field/type 누락이나 malformed 입력은 `unsupported`, byte·count cap 초과 입력은 `ambiguous`로 폐기하며 frozen query는 최대 1회다. `query_en`은 ASCII 120바이트, symbol은 각각 160바이트, path는 각각 240바이트다. MCP/CLI usable response가 schema-invalid·`malformed`이면 폐기 후 `unsupported`, raw response가 65536바이트를 넘으면 폐기 후 `ambiguous`로 중단한다. usable response 이후 실패에는 failover·retry·merge를 허용하지 않는다. permission glob은 각 command의 shape와 numeric flag만 제한하고 response byte, shell command 조합, per-turn·per-mission call count를 강제하지 않으므로 call·file·numeric cap과 별도 consumption cap을 behavioral budget으로 적용한다.
- `fd`는 file set, `rg`는 lexical `path:line`, `sg`는 AST shape, CodeGraph는 cross-file relation candidate, runtime은 observable behavior를 소유한다. 서로 다른 failure mode를 교차 검증할 때만 도구를 추가하며 모든 도구를 의례적으로 순회하지 않는다.
- lead는 graph candidate의 현재 source `path:line`을 직접 다시 확인한 뒤에만 직렬 병합한다. F3와 F4는 새 graph discovery·query·focused operation을 모두 금지하고 검증된 원장만 소비한다.
- 상세 예산, 허용 명령, 교차 검증과 문제 해결은 [CodeGraph 하이브리드 분석 가이드](codegraph-analysis-guide.md)를 따른다.

## 위임과 쓰기 경계

- lead는 mission root `docs/analysis/missions/<mission-id>/`의 primary single writer다.
- peer는 파일을 쓰거나 task를 재위임하거나 사람 verdict를 만들지 않는다.
- F1/F2는 조사 lane을 병렬화할 수 있지만 canonical trace merge는 lead가 직렬로 수행한다.
- worker 반환 근거는 lead가 결정적 도구로 재확인한다.
- 상태 우선순위는 validated trace, validated progress, 파생 status/todo 순이다.

## CLI와 permission

허용 후보는 `fd`, `rg`, `sg`(ast-grep), `jq`, Mike Farah `yq`, yshavit `mdq`, `mmdc`와 exact argv가 승인된 persistent read-only CodeGraph CLI다. MCP는 unknown `codegraph_*` deny와 exact `codegraph_explore` ask를 적용한다. lead/skill은 rewrite, exec, pipe, redirect, shell substitution, secret 경로, 외부 쓰기와 CodeGraph index/server mutation을 운영상 금지한다. 기존 permission의 command shape·numeric flag·secret·redirect 방어는 유지하지만, OpenCode `1.18.3`이 shell AST의 각 command를 독립 평가하므로 glob은 개별 허용 command의 `|`, `;`, `&&`, `||`, `&` 조합이나 per-turn·per-mission call count를 기계적으로 막지 못한다. 따라서 각 명령 별도 실행, pipe 금지, query 최대 1회는 behavioral budget이지 security boundary가 아니다. 기계적 강제가 필요하면 CodeGraph bash pattern을 `ask`/`deny`로 바꾸거나 외부 sandbox/wrapper를 사용해야 하며 현재 package는 이를 설치하지 않는다. consumption cap, deterministic adversarial test와 disposable environment도 별도로 필요하다.
