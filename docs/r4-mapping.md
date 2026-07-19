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
| 구조 후보 | peer | react/vertx/spec trace | `ast-grep`, `rg` 구조화 출력 | 후보는 사실이 아님 |
| convention 판정 | lead | convention-extract | `ast-grep`, `jq` | 7 category, 각 직접 근거 |
| business 사실 | peer 수집, lead 판정 | business-trace | `ast-grep`, `rg`, `jq`, `yq` | 암묵 규칙은 `UNKNOWN` |
| AS-IS 투영 | lead | UI, sequence, dataflow, story | `jq`, `mdq`, `mmdc` | DATAFLOW는 deliverable |
| 수정요청 분석 | lead | requirement-analyze | `jq`, `mdq` | source와 modality 보존 |
| 변경 설계 | lead | change-design | `ast-grep`, `rg`, `jq` | binding과 violation gate 필수 |
| TO-BE 투영 | lead | UI, sequence, dataflow, story, test | `jq`, `mdq`, `mmdc` | 5-mode provenance |
| 독립 검증 | peer 조사, 결정적 validator 판정 | evidence-first, checklist | `jq`, `mdq`, `mmdc` | 모델 성공 문장 불인정 |

## 위임과 쓰기 경계

- lead는 mission root `docs/analysis/missions/<mission-id>/`의 primary single writer다.
- peer는 파일을 쓰거나 task를 재위임하거나 사람 verdict를 만들지 않는다.
- F1/F2는 조사 lane을 병렬화할 수 있지만 canonical trace merge는 lead가 직렬로 수행한다.
- worker 반환 근거는 lead가 결정적 도구로 재확인한다.
- 상태 우선순위는 validated trace, validated progress, 파생 status/todo 순이다.

## CLI와 permission

허용 후보는 `fd`, `rg`, `ast-grep`, `jq`, Mike Farah `yq`, yshavit `mdq`, `mmdc`다. rewrite, exec, pipe, redirect, shell substitution, secret 경로, 외부 쓰기는 금지한다. permission은 OS sandbox가 아니므로 deterministic adversarial test와 disposable environment가 별도로 필요하다.
