# wonder-sensai 제품 계약

## 현재 상태

이 문서는 27개 PRD에서 제품 경계와 입학 조건을 복구한 source-owned 상위 계약이다. 현재 저장소에는 `output/AGENTS.md`, baseline `output/opencode.json`, fixture/test/catalog가 있지만 나머지 runtime leaf는 아직 없으며, 본 문서의 존재는 구현·모델·Windows 호환성 완료를 뜻하지 않는다.

| 상태 축 | 현재 값 | 의미 |
| --- | --- | --- |
| `LOCAL_IMPLEMENTATION` | `OUTPUT_TOPOLOGY_AND_FIXTURES` | runtime root와 fixture/test/catalog는 있으나 agent/command/skill/schema/recipe/load는 미완료다. |
| `MODEL_ADMISSION` | `UNVERIFIED` | 별칭 발견·로드 값은 정했지만 live 응답과 tool call은 검증하지 않았다. |
| `WINDOWS_RECEIPT` | `PENDING_USER_RECEIPT` | Windows 검증은 구현의 선행 조건이 아니라 최종 사용자 실행 영수증이다. |

## 제품 목적과 경계

`wonder-sensai`는 기존 코드베이스를 근거 중심으로 분석해 AS-IS를 이해하고, 사람 승인을 받은 수정요청을 TO-BE 설계와 산출물로 투영하는 OpenCode 전역 설치용 하네스다. canonical 사실은 mission별 `trace.json`이며, 모델 문장이나 파생 Markdown·SVG는 validator를 통과해도 원장을 대신하지 않는다.

제품 구현 기준은 다음과 같다.

- OpenCode 기준 버전은 `1.18.3`이다.
- 설치 가능한 runtime source는 단일 `output/` root다. root duplicate와 `.opencode/` 복사본을 함께 유지하지 않는다.
- runtime leaf는 `output/AGENTS.md`, `output/opencode.json`, `output/agents/`, `output/commands/`, `output/skills/`, `output/schemas/`, `output/recipes/`다.
- output의 사람이 읽는 제목·설명·지침·표시명은 한국어로 작성하고 기계 key/schema field/ID/path/command/skill/enum/reason code/문법은 원형을 보존한다.
- root `manifest.txt`는 `output/` 상대 leaf를 나열하고 stage/install은 `output/` 접두사 없이 config root에 배치한다.
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

## 제품 금지선

현재 구현에 다음을 추가하지 않는다.

- Node.js 또는 TypeScript 제품 runtime
- Go module, Go binary, 범용 wrapper
- plugin, MCP, custom tool, codegraph 상시 경로
- Yeoman 또는 코드 생성
- live model call, 자격 증명 복사, raw model transcript 저장
- 실제 전역 OpenCode 설정 수정
- commit, tag, push, publish

루트 `AGENTS.md`는 저장소 기여자와 fixture 관리 계약이다. runtime prompt는 `output/AGENTS.md`이며 staged config에서 자동 로드된다고 가정하지 않고, runtime 불변조건은 source-owned config, agent, command, skill에도 직접 둔다. 절대 경로의 `instructions` 의존은 허용하지 않는다.

## Go와 확장 입학 게이트

Go wrapper를 포함한 후보 기능은 기본값이 `NOT_ADMITTED`다. 다음을 모두 만족할 때만 별도 변경으로 검토한다.

1. 현재 shell과 독립 CLI 조합이 실패하는 재현 fixture가 최소 2개 있다.
2. 후보가 실패를 복구하고 기존 오류 의미와 exit semantics를 보존한다.
3. 정확도, wall time, RSS, 안전성의 사전 threshold를 통과한다.
4. deterministic 회귀와 퇴출 경로가 있다.
5. 사람이 증거를 검토해 승인한다.

편의성이나 미래 가능성만으로는 입학할 수 없다.

## 권위와 증거

source-owned 계약의 우선순위는 실제 schema·validator·runtime 동작과 검증 영수증, 본 문서와 `docs/harness/`, 파생 status 순이다. ignored `plan/`과 루트 `STATUS.md`는 구현 권위가 아니다. 현재 runtime 세부 계약은 [runtime-contract.md](harness/runtime-contract.md), 검증은 [verification-contract.md](harness/verification-contract.md), release 표기는 [release-contract.md](harness/release-contract.md), 역할·도구 매핑은 [r4-mapping.md](r4-mapping.md)를 따른다.
