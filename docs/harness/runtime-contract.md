# 하네스 runtime 계약

## packaging과 설치 경계

`output/`은 `AGENTS.md`, `opencode.json`, `toolchain.lock.json`, agents, commands, skills, schemas, recipes로 이루어진 36개 managed config leaf의 packaging source다. root `manifest.txt`는 이 leaf를 `output/` 기준 상대 경로로 나열한다. target은 2 agents, 9 commands, 15 skills의 exact-set이며 source와 stage에 hidden extra, symlink, 중복 normalized path를 허용하지 않는다. `output/`은 실행 중 runtime asset 탐색 경로가 아니다.

output의 사람이 읽는 제목, 설명, 지침, provider/model 표시명은 한국어로 작성한다. OpenCode가 요구하는 key/schema field, provider/model ID, path, command/skill 이름, stable ID, enum, reason code, shell·JSON·jq 문법은 번역하지 않는다. 검증기는 영어 자연어 문장 주입을 거부하되 식별자와 코드를 오탐하지 않아야 한다.

`output/opencode.json`의 공급자 ID는 `sensai-ollama`, 주소는 `http://localhost:11434/v1`, `apiKey`는 `ollama`로 고정한다. 이 키는 로컬 OpenAI 호환 공급자 형식을 위한 비밀 아닌 자리표시자이며 실제 자격 증명이 아니다. 환경 변수·실제 비밀값·다른 호스트로 교체하는 설정은 exact config 검증에서 거부한다.

`stage <absent-absolute-target>`는 36개 config leaf만 부재한 target에 원자 투영하며 CLI는 포함하지 않는다. `install`은 인자를 받지 않고 기존 물리 `$HOME/.config/opencode`에 이 leaf를 파일 단위로 설치하며 `$HOME/.local/bin/sensai` 하나를 별도로 게시한다. managed leaf와 CLI가 absent면 생성하고 source와 byte-equal인 regular file이면 no-op이다. differing regular file, symlink, directory 또는 비정규 파일은 `package.managed_conflict`, exit `73`으로 pre-write 거부한다. root 자체와 unmanaged file·directory는 그대로 보존하고 실패 시 이번 실행이 만든 expected-hash 파일과 owned empty directory만 rollback한다.

`OPENCODE_CONFIG_DIR`는 OpenCode의 다른 설정 층과 합쳐지는 merged overlay다. 따라서 변수를 지정한 것만으로 isolation을 주장하지 않는다. 설치 위치를 바꾸지도 않는다. 의미 검증은 다음을 모두 갖춘 disposable 환경에서 수행한다.

- absent stage root
- disposable `HOME`과 XDG 경로
- 저장소 밖 neutral working directory
- 상속 여부를 탐지하는 sentinel
- source, 실제 global config, stage의 전후 SHA-256

`opencode debug`는 초기화 파일을 쓸 수 있는 mutating diagnostic이다. source tree나 실제 HOME에서 acceptance 명령으로 실행하지 않는다.

OpenCode `1.18.3` debug 초기화는 disposable config root에 `.gitignore`를 추가할 수 있으므로 load 뒤에는 managed 36개 leaf의 byte 불변과 알려진 추가 leaf를 분리해 검사한다. source checkout, 실제 HOME 또는 실제 global config에서 debug acceptance를 실행하지 않는다.

## 실행 파일과 runtime asset 해석

installed mode의 실행 파일은 regular executable `$HOME/.local/bin/sensai` 하나다. 절대 경로 호출과 `PATH` 호출은 해석 뒤 이 exact physical path여야 하며 symlink executable 또는 symlink parent를 거부한다. source mode는 checkout의 exact `<source>/bin/sensai`만 허용한다. source와 installed mode의 mission asset 선택은 같고 `stage`와 `install`만 source mode 전용이다.

runtime global config root는 `OPENCODE_CONFIG_DIR`, `${XDG_CONFIG_HOME}/opencode`, `$HOME/.config/opencode` 순으로 선택한다. `opencode.json`과 `toolchain.lock.json`은 항상 이 global root에서 읽는다. mission schema·recipe는 각 요청 파일마다 다음 순서로 선택한다.

1. project root는 absolute physical `SENSAI_PROJECT_ROOT`, 없으면 물리 CWD다.
2. `<project>/.sensai/{schemas,recipes}/<file>`이 없으면 global config의 같은 상대 파일을 사용한다.
3. project 파일이 존재하면 그것만 선택한다. invalid JSON/jq, symlink, directory 또는 비정규 파일이면 `runtime.asset_invalid`로 fail closed하고 global 파일로 fallback하지 않는다.
4. 선택한 경로의 provenance는 `project` 또는 `global`이며 mission fingerprint에 반영한다.

CWD는 project root의 기본값일 뿐 `output/` asset fallback이 아니다. 실행 파일 parent의 `output/`, `$HOME/.local/output`, source `output/`은 runtime fallback이 아니다.

## AGENTS와 instructions

루트 `AGENTS.md`는 contributor/fixture 계약이며 stage에 복사하지 않는다. runtime 계약 `output/AGENTS.md`는 manifest leaf로 stage에 `AGENTS.md`로 배치하지만 custom config directory에서 자동 로드된다고 가정하지 않는다. runtime에 필요한 증거, 권한, UNKNOWN, single-writer, gate 규칙은 config/agent/command/skill에도 명시적으로 반복한다. 장비별 절대 경로의 `instructions`가 없으면 동작하지 않는 설계는 실패다.

## mission 상태

모든 mission 파일은 다음 경계 안에 있다.

```text
docs/analysis/missions/<mission-id>/
  trace.json
  progress.json
  status.md
  artifacts/
  receipts/
```

`<mission-id>`는 traversal이 없는 canonical slug다. global progress singleton을 만들지 않는다. 진실 우선순위는 validated `trace.json` > validated `progress.json` > 파생 `status.md`와 OpenCode todo다.

primary lead가 single writer다. 쓰기는 같은 파일시스템의 임시 파일, fsync 가능한 경계, atomic rename, revision과 precondition fingerprint 비교를 사용한다. 같은 mission의 동시 writer/resume은 거부한다. peer는 읽기 전용이다.

## F0-F5 상태 전이

- F0: lead가 target, scope, goal, dependency, todo를 draft한다. 사람 approval receipt 전에는 F1/F2로 이동하지 않는다.
- F1/F2: 기술·비즈니스 조사는 병렬 가능하지만 canonical merge는 lead가 직렬 수행한다.
- F3: AS-IS 4종과 검증 receipt가 있고 사람이 승인해야 F4로 이동한다.
- F4: design은 convention과 business binding을 모두 갖는다. violation은 사람 verdict 전까지 차단한다.
- F5: TO-BE 5종, validator, render receipt가 있고 사람이 승인해야 종료한다.

각 transition은 revision, 이전 상태 hash, current input hash, human receipt가 필요한 경우 receipt hash를 검증한다. stale·corrupt·경로 이탈·double resume은 partial write 없이 실패한다.

## 근거와 산출

canonical trace는 7 convention category, 비즈니스 사실, AS-IS/TO-BE kind, exact binding, uncertainty 상태를 보존한다. `DATAFLOW`는 convention이 아니라 provenance `dataflow` 모드로 검증하는 deliverable이다. UI, Mermaid, dataflow, story, test는 원장 ID와 직접 근거로 역대조한다.

## permission 경계

- lead write: 현재 mission root만
- lead와 peer read: 현재 대상 저장소 안에서 명시적으로 선택된 source만, 비밀 경로 제외
- lead task: explicit peer만
- peer: edit, task, todowrite, verdict 금지
- shell: 식별된 독립 CLI의 read/validate/render 호출만
- secret, 외부 경로, pipe, redirect, command substitution, rewrite, exec 금지

permission은 의도와 사용자 승인 UI를 제공하지만 OS sandbox가 아니다. filesystem, HOME/XDG, network, credential 격리는 별도 test environment가 담당한다.

## 상태 표기

runtime 구현과 local deterministic QA가 실제 통과하기 전 `LOCAL_IMPLEMENTATION_PASS`를 출력하지 않는다. 이 PASS는 core·install·AS-IS 결정적 범위이며 live F3-F5 성공이 아니다. delivery 후보 5 skill은 `VALUE_PROVEN` 전 exact deny이고 모델은 `MODEL_ADMISSION_UNVERIFIED`다. Windows native는 `WINDOWS_TEST_UNAVAILABLE`, compatibility는 `WINDOWS_COMPATIBILITY_UNVERIFIED`, macOS 대체 검사는 `MACOS_STATIC_SUBSTITUTE_PASS`로 분리한다.
