# 하네스 runtime 계약

## source와 load 경계

runtime source는 `output/AGENTS.md`, `output/opencode.json`, `output/agents/`, `output/commands/`, `output/skills/`, `output/schemas/`, `output/recipes/`다. root `manifest.txt`는 이 leaf를 `output/` 기준 상대 경로로 나열한다. target은 2 agents, 9 commands, 15 skills의 exact-set이며 source와 stage에 hidden extra, symlink, 중복 normalized path를 허용하지 않는다.

output의 사람이 읽는 제목, 설명, 지침, provider/model 표시명은 한국어로 작성한다. OpenCode가 요구하는 key/schema field, provider/model ID, path, command/skill 이름, stable ID, enum, reason code, shell·JSON·jq 문법은 번역하지 않는다. 검증기는 영어 자연어 문장 주입을 거부하되 식별자와 코드를 오탐하지 않아야 한다.

`output/opencode.json`의 공급자 ID는 `sensai-ollama`, 주소는 `http://localhost:11434/v1`, `apiKey`는 `ollama`로 고정한다. 이 키는 로컬 OpenAI 호환 공급자 형식을 위한 비밀 아닌 자리표시자이며 실제 자격 증명이 아니다. 환경 변수·실제 비밀값·다른 호스트로 교체하는 설정은 exact config 검증에서 거부한다.

`OPENCODE_CONFIG_DIR`는 OpenCode의 다른 설정 층과 합쳐지는 merged overlay다. 따라서 변수를 지정한 것만으로 isolation을 주장하지 않는다. 의미 검증은 다음을 모두 갖춘 disposable 환경에서 수행한다.

- absent stage root
- disposable `HOME`과 XDG 경로
- 저장소 밖 neutral working directory
- 상속 여부를 탐지하는 sentinel
- source, 실제 global config, stage의 전후 SHA-256

`opencode debug`는 초기화 파일을 쓸 수 있는 mutating diagnostic이다. source tree나 실제 HOME에서 acceptance 명령으로 실행하지 않는다.

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
- lead task: explicit peer만
- peer: edit, task, todowrite, verdict 금지
- shell: 식별된 독립 CLI의 read/validate/render 호출만
- secret, 외부 경로, pipe, redirect, command substitution, rewrite, exec 금지

permission은 의도와 사용자 승인 UI를 제공하지만 OS sandbox가 아니다. filesystem, HOME/XDG, network, credential 격리는 별도 test environment가 담당한다.

## 상태 표기

runtime 구현과 local deterministic QA가 실제 통과하기 전 `LOCAL_IMPLEMENTATION_PASS`를 출력하지 않는다. 모델은 `MODEL_ADMISSION_UNVERIFIED`, Windows는 `WINDOWS_RECEIPT_PENDING`으로 분리한다.
