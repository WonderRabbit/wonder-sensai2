# 하네스 구현 상태

> 이 파일은 source-owned 파생 요약이다. schema, runtime, evidence보다 권위가 낮으며 구현 task가 끝날 때 current workspace fingerprint와 함께 갱신한다.

## 2026-07-19 T05 상태

| 축 | 상태 | 현재 증거 |
| --- | --- | --- |
| contract freeze | `COMPLETE` | 제품, mapping, runtime, verification, release 계약 존재 |
| `LOCAL_IMPLEMENTATION` | `OUTPUT_TOPOLOGY_AND_FIXTURES` | runner/fixture/output contracts는 있고 future runtime leaves는 없음 |
| `MODEL_ADMISSION` | `UNVERIFIED` | baseline alias만 동결; live call 없음 |
| `WINDOWS_RECEIPT` | `PENDING_USER_RECEIPT` | 최종 kit와 사용자 receipt 없음 |

## 동결된 목표

- canonical `output/` runtime source
- OpenCode `1.18.3`
- lead `zai/glm-5.2`, peer `sensai-ollama/qwen3.5:9b`는 discovery/load 값만
- exactly 2 agents, 9 commands, 15 skills
- root `fixtures/` repository-side corpus
- `docs/analysis/missions/<mission-id>/`
- primary lead single writer
- 7 convention category, `DATAFLOW` deliverable
- F0 lead draft + human approval; F0/F3/F5/violation/admission hard gates
- macOS deterministic 구현/QA, Windows final user receipt

## 현재 확인된 증거

- 실행 가능한 fail-closed `tests/test.sh`
- root fixture/golden corpus와 exact-set/hash/14+14 oracle
- `output/AGENTS.md`와 처음에는 byte-identical로 이동한 뒤 사람용 표시명만 한국어화한 `output/opencode.json`
- output 상대 2/9/15/2/5 및 36-leaf target catalog
- output 사람용 문구·표시명 한국어 계약과 한 단어·짧은 문장·제목·목록 주입 거부 로컬 oracle; 독립 재검증은 `PENDING`

## 아직 없는 증거

- output schema, recipe, root manifest, installer
- output agent, command, skill runtime 파일
- isolated OpenCode semantic load
- AS-IS/TO-BE deterministic projection
- live model/TUI/delegation
- Windows user receipt

따라서 `LOCAL_IMPLEMENTATION_PASS`, model admission, Windows/cross-platform PASS를 선언하지 않는다.
