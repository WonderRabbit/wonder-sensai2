# 하네스 계약 동결

## 목적

이 문서는 상충하던 27개 PRD 결정을 구현 전에 하나의 source-owned 계약으로 동결한다. ignored `plan/`은 역사·계획 입력으로 남지만 runtime은 이 파일에 의존하지 않는다.

## 동결 결정

| 주제 | canonical 결정 | 배제한 해석 |
| --- | --- | --- |
| payload | `output/`의 36-leaf packaging source + existing global config managed install + 플랫폼별 별도 `sensai`/`sensai.exe` | 단일 config root에 CLI 포함 또는 runtime `output/` fallback |
| OpenCode | exact `1.18.3` | `1.17.18` 이상 범위 허용 |
| model baseline | lead `zai/glm-5.2`, peer `sensai-ollama/qwen3.5:9b` | Qwen 35B를 현재 lead alias로 간주 |
| model status | discovery/load 값만, `MODEL_ADMISSION=UNVERIFIED` | alias 발견을 live 입학으로 간주 |
| topology | 2 agents / 9 commands / 15 skills target | 3-command·6-skill historical payload |
| fixture | 루트 `fixtures/` | `tests/fixtures/` canonical source |
| mission root | `docs/analysis/missions/<mission-id>/` | 전역 `docs/analysis/progress.json` singleton |
| writer | primary lead single writer | peer edit, parallel canonical merge |
| convention | 7 category | `DATAFLOW`를 category로 추가 |
| dataflow | AS-IS/TO-BE deliverable | 분석 convention |
| F0 | lead가 draft, 사람이 승인 | 사람만 decomposition 수행, 모델 self-approval |
| hard gate | F0, F3, F5, violation, admission | F3/F5만 hard gate |
| config dir | `OPENCODE_CONFIG_DIR`는 merged overlay | 설정 격리 보장으로 간주 |
| AGENTS | root는 contributor/fixture 계약, `output/AGENTS.md`는 runtime 계약 | implicit 자동 로드에만 의존 |
| output language | 사람용 제목·설명·지침·표시명은 한국어 | 기계 key/ID/path/name/enum/reason code/문법 번역 |
| instructions | source-owned 상대 계약만 | 장비별 절대 경로 의존 |
| platform | macOS가 deterministic 구현/QA gate | Windows를 H1/H2 선행 조건으로 사용 |
| Windows | 최종 사용자 receipt | 로컬 PASS 산술에 포함 |
| CLI | stdlib-only Go module, exact build prerequisite Go `1.26.5` | POSIX shell runtime, third-party Go module |
| build target | `darwin/arm64` `sensai`, `windows/amd64` `sensai.exe` | 다른 target 또는 suffix |
| scope | Go CLI와 독립 검증 도구 기반 | Node/TS/plugin/MCP/custom tool/Yeoman |

## source authority

1. 실행 가능한 schema, validator, config, catalog와 현재 실행 영수증
2. [제품 계약](../PROD.md), 본 디렉토리의 runtime·verification·release 계약, [R4 mapping](../r4-mapping.md)
3. 파생 implementation status
4. ignored `plan/`과 루트 `STATUS.md`

낮은 층의 성공 문장이나 오래된 상태는 높은 층의 현재 증거를 덮을 수 없다. 계약이 구현과 다르면 false-green이 아니라 구현 실패다.

## 보존 계약

루트 `AGENTS.md`의 T01-T04 baseline SHA-256은 `64d0ffefedf2df07095a3316ebf48586366a4565cf1d3f8bed596e054c3c4866`이었다. 사용자가 T05에서 fixture 역할과 검증 절차 추가를 명시적으로 승인했으며 새 SHA는 `tests/contracts/root-agents.sha256.txt`가 보호한다. runtime `output/AGENTS.md`는 stage payload에 포함하되 implicit 자동 로드에 의존하지 않고 불변조건을 agent, command, skill, config에도 직접 둔다.

## 현재 비주장

- live model, TUI, delegation 성공 주장 없음
- Windows 또는 cross-platform PASS 주장 없음
- commit, tag, push, publish 없음

36개 managed config leaf, 별도 installed Go CLI와 deterministic OpenCode load는 구현됐다. Unix installed path는 `$HOME/.local/bin/sensai`, Windows direct-CLI path는 `%USERPROFILE%\.local\bin\sensai.exe`다. runtime schema·recipe는 project `.sensai/{schemas,recipes}`의 같은 파일을 우선하고 해당 project file이 absent일 때만 global config로 fallback한다. present-invalid project file은 fail closed하며 CWD나 executable parent의 `output/`은 fallback이 아니다. Windows OpenCode slash-command integration은 payload binding을 바꾸지 않는 현재 범위 밖이며 `WINDOWS_COMPATIBILITY_UNVERIFIED`다.
