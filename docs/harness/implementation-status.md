# 하네스 구현 상태

> 이 파일은 source-owned 파생 요약이다. schema, runtime, evidence보다 권위가 낮으며 구현 task가 끝날 때 current workspace fingerprint와 함께 갱신한다.

## 2026-07-21 Go CLI cutover 상태

| 축 | 상태 | 현재 증거 |
| --- | --- | --- |
| contract freeze | `COMPLETE` | 제품, mapping, runtime, verification, release 계약 존재 |
| `LOCAL_IMPLEMENTATION` | `PASS` | stdlib-only Go CLI, managed global install, runtime overlay와 결정적 preflight가 current fingerprint에서 통과 |
| `MODEL_ADMISSION` | `UNVERIFIED` | live response/tool-use 호출 없음 |
| `TUI/LIVE_DELEGATION` | `UNVERIFIED` | 실제 session receipt 없음 |
| `WINDOWS_NATIVE` | `TEST_UNAVAILABLE` | 현재 환경에 Windows 호스트 없음 |
| `MACOS_STATIC_SUBSTITUTE` | `PASS` | 현재 payload·설정·경로·quoting·checksum 범위 |
| `WINDOWS_COMPATIBILITY` | `UNVERIFIED` | 실제 Windows 실행 없음 |

## 동결된 목표

- canonical `output/` packaging source
- `output/`은 36개 config leaf의 packaging source이며 runtime fallback이 아님
- exact Go `1.26.5`, module `github.com/WonderRabbit/wonder-sensai2`, stdlib-only source
- `darwin/arm64` `sensai`와 `windows/amd64` `sensai.exe` build target
- Unix `$HOME/.config/opencode` + `$HOME/.local/bin/sensai`, Windows `%USERPROFILE%\.config\opencode` + `%USERPROFILE%\.local\bin\sensai.exe`
- project `.sensai/{schemas,recipes}` file-level override 후 global absent-only fallback
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
- output 상대 2/9/15/2/5의 36-leaf config catalog와 별도 설치 Go CLI
- absent managed leaf 설치, byte-equal no-op, conflict pre-write 거부, unmanaged 보존과 rollback journal
- absolute/PATH/source executable 해석과 project/global asset provenance; present-invalid override fail-closed
- `windows/amd64` cross-build와 PE32+ metadata는 확인했지만 Windows direct CLI와 OpenCode slash-command는 미검증
- output 사람용 문구·표시명 한국어 계약과 한 단어·짧은 문장·제목·목록 주입 거부 로컬 oracle; 독립 재검증은 `PENDING`

## 외부 또는 후속 단계에 남은 증거

- live model/TUI/delegation
- `VALUE_PROVEN` 전 exact deny인 delivery 후보 5 skill의 입학 영수증과 live F3-F5
- 실제 Windows direct-CLI 실행과 native receipt
- extension 없는 기존 `output/commands/` binding을 대체할 Windows OpenCode slash-command 계약
- Windows compatibility 승인

따라서 terminal status는 `LOCAL_IMPLEMENTATION_PASS / MODEL_ADMISSION_UNVERIFIED / WINDOWS_TEST_UNAVAILABLE / WINDOWS_COMPATIBILITY_UNVERIFIED / MACOS_STATIC_SUBSTITUTE_PASS`다. Windows 또는 cross-platform PASS는 선언하지 않는다.
