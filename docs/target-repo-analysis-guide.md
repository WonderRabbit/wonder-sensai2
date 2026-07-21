# wonder-sensai 설치와 대상 저장소 분석 안내서

이 문서는 OpenCode `1.18.3`과 현재 `cmd/sensai/` Go source를 기준으로 한다. 결정적 packaging·설치·mission 검증은 구현돼 있지만 live model response, TUI delegation과 Windows 실행은 별도 admission 대상이다. 설정이 load됐다는 사실을 모델 분석 성공으로 확대하지 않는다.

## 설치 topology

서로 다른 네 경계를 섞지 않는다.

| 경계 | 기본 위치 | 역할 |
| --- | --- | --- |
| source checkout | `/absolute/path/to/wonder-sensai2` | `output/`, `manifest.txt`, `cmd/sensai/`, `go.mod`, tracked `bin/sensai`, `bin/sensai.exe`, tests와 docs 보유 |
| global OpenCode config | `$HOME/.config/opencode` | installer가 관리하는 config leaf 36개와 기존 unmanaged content 보유 |
| installed CLI | `$HOME/.local/bin/sensai` | 설치 뒤 사용하는 유일한 executable |
| project | `/absolute/path/to/target` | `.sensai/{schemas,recipes}` override와 `docs/analysis/missions/` 보유 |

`output/`은 packaging source일 뿐 runtime 탐색 root가 아니다. installer는 `output/` 접두사를 제거한 36개 leaf를 global config 아래에 배치한다. CLI는 config 안에 넣지 않고 `$HOME/.local/bin/sensai` 하나로 설치한다. 대상 저장소에 `output/`, `bin/sensai` 또는 global config 복사본을 만들지 않는다.

## 설치 전 확인

release source checkout은 tracked `bin/sensai`를 포함한다. `cmd/sensai/`와 `go.mod`가 semantic authority이고 binary는 exact Go `1.26.5`로 생성한 전달 artifact이므로 설치 안내 중 임의로 다시 build하지 않는다. source checkout과 HOME은 symlink component가 없는 physical absolute path여야 한다. global config root는 installer가 만들지 않으므로 먼저 존재하는 regular directory인지 확인한다.

```sh
set -eu

SENSAI_SOURCE="/absolute/path/to/wonder-sensai2"
TARGET_REPO="/absolute/path/to/order-service"

test -x "$SENSAI_SOURCE/bin/sensai"
test -d "$HOME/.config/opencode"
test ! -L "$HOME/.config/opencode"
test -d "$TARGET_REPO"
test ! -L "$TARGET_REPO"

"$SENSAI_SOURCE/bin/sensai" doctor tools
```

install 전에는 `doctor tools`만 실행한다. 이 명령은 `opencode`, `fd`, `rg`, `sg`, `jq`, `yq`, `mdq`, `mmdc`의 제품 식별을 확인한다. OpenCode는 exact `1.18.3`, `sg`는 ast-grep, `yq`는 Mike Farah 제품이어야 한다. `doctor models`는 설치된 global config를 읽으므로 install 성공 뒤 installed CLI로 실행한다.

`output/opencode.json`의 `apiKey: ollama`는 localhost OpenAI-compatible provider 형식을 위한 비밀 아닌 자리표시자다. 실제 token이나 `.env` 값을 복사하지 않는다.

## global install

`install`은 source checkout의 CLI에서 인자 없이 실행한다.

```sh
"$SENSAI_SOURCE/bin/sensai" install
```

성공 출력은 `mode=install`, `status=READY`, `config_target`, `cli_target`, `leaf_count=36`, `manifest_sha256`, `config_sha256`, `cli_sha256`, `config_created`, `config_unchanged`, `cli_result`, `path_contains_local_bin`을 포함한다. 설치 규칙은 다음과 같다.

- managed leaf가 absent면 생성한다.
- source와 byte-equal인 regular leaf는 no-op으로 분류한다.
- differing regular leaf, symlink, directory 또는 비정규 leaf는 첫 write 전에 `package.managed_conflict`, exit `73`으로 거부한다.
- `$HOME/.local/bin/sensai`도 같은 absent/equal/conflict 규칙을 따르며 equal 판정에는 executable mode가 필요하다.
- global config root의 unmanaged file과 directory는 보존한다.
- 실패 시 이번 실행이 만든 expected-hash 파일과 owned empty directory만 rollback한다. preexisting equal leaf와 unmanaged content는 지우지 않는다.
- 같은 source로 다시 실행하면 `config_created=0`, `config_unchanged=36`, `cli_result=unchanged`인 idempotent no-op이다.

installer는 `OPENCODE_CONFIG_DIR`나 `XDG_CONFIG_HOME`으로 설치 위치를 바꾸지 않는다. 설치 target은 physical `$HOME/.config/opencode`, CLI target은 physical `$HOME/.local/bin/sensai`다.

## installed CLI 호출

install 뒤 global config와 model alias를 확인하는 가장 명시적인 호출은 절대 경로다.

```sh
"$HOME/.local/bin/sensai" doctor models
```

`$HOME/.local/bin`이 `PATH`에 있으면 다음 호출도 같은 executable을 해석한다.

```sh
PATH="$HOME/.local/bin:$PATH" sensai doctor models
```

installed mode는 해석된 executable이 exact physical `$HOME/.local/bin/sensai`일 때만 성립한다. executable 또는 parent symlink, 다른 위치의 동명 binary, relative PATH result는 `runtime.executable_invalid`다. source mode는 tracked exact `<source>/bin/sensai`를 직접, 절대 경로 또는 PATH로 호출할 수 있다. source mode와 installed mode는 mission runtime asset을 같은 규칙으로 선택하며 `stage`와 `install`만 source mode 전용이다.

## stage는 설치와 다르다

`stage`는 release·검증용 config-only projection이다.

```sh
STAGE_TMP_BASE=$(CDPATH= cd -- "${TMPDIR:-/tmp}" && pwd -P) || exit 73
case "$STAGE_TMP_BASE" in
  /|'') printf '%s\n' "temp root 거부: $STAGE_TMP_BASE" >&2; exit 73 ;;
esac
STAGE_PARENT=$(mktemp -d "$STAGE_TMP_BASE/sensai-stage.XXXXXX") || exit 73
STAGE_TARGET="$STAGE_PARENT/config"
"$SENSAI_SOURCE/bin/sensai" stage "$STAGE_TARGET"

test "$(find "$STAGE_TARGET" -type f | wc -l | tr -d ' ')" = "36"
test ! -e "$STAGE_TARGET/bin/sensai"
```

target은 absent normalized absolute path여야 하고 parent는 기존 physical directory여야 한다. source/stage manifest와 SHA-256을 확인한 뒤 같은 parent의 temp sibling을 rename한다. 기존 target을 merge하지 않으며 target이 있으면 exit `73`이다. stage는 global install이나 CLI publication을 대신하지 않는다.

전용 temp root를 정리할 때만 명시적인 경계를 확인한다.

```sh
case "$STAGE_PARENT" in
  "$STAGE_TMP_BASE"/sensai-stage.*) ;;
  *) printf '%s\n' "정리 거부: $STAGE_PARENT" >&2; exit 73 ;;
esac
STAGE_SUFFIX=${STAGE_PARENT#"$STAGE_TMP_BASE"/sensai-stage.}
case "$STAGE_SUFFIX" in
  ''|*/*) printf '%s\n' "정리 거부: $STAGE_PARENT" >&2; exit 73 ;;
esac
test -d "$STAGE_PARENT" && test ! -L "$STAGE_PARENT" || exit 73
test "$(CDPATH= cd -- "$STAGE_PARENT" && pwd -P)" = "$STAGE_PARENT" || exit 73
find "$STAGE_PARENT" -depth -delete
```

## runtime global root와 project override

mission 실행 시 global config root는 다음 순서로 결정된다.

1. `OPENCODE_CONFIG_DIR`
2. `${XDG_CONFIG_HOME}/opencode`
3. `$HOME/.config/opencode`

이 우선순위는 runtime read 위치다. installer의 고정 target을 바꾸지 않는다. `opencode.json`과 `toolchain.lock.json`은 선택된 global root에서만 읽는다.

schema·recipe는 directory 단위가 아니라 요청 파일 단위로 선택한다.

```text
<project>/.sensai/schemas/trace.schema.json
<project>/.sensai/schemas/progress.schema.json
<project>/.sensai/recipes/trace.jq
<project>/.sensai/recipes/progress.jq
```

각 파일에 대해 project file이 있으면 provenance `project`로 선택한다. project file이 없을 때만 global config의 같은 상대 file을 provenance `global`로 선택한다. 따라서 일부 파일만 project override하고 나머지는 global로 fallback할 수 있다.

present-invalid는 absent가 아니다. project path가 malformed JSON/jq, symlink, directory, nonregular leaf이거나 중간 component가 잘못됐으면 `runtime.asset_invalid`로 중단한다. global file이 valid해도 fallback하지 않는다. global file까지 없으면 `runtime.asset_missing`이다.

project root는 `SENSAI_PROJECT_ROOT`가 있으면 그 absolute physical directory, 없으면 물리 CWD다. CWD는 project 선택에만 쓰인다. CWD의 `output/`, executable parent의 `output/`, `$HOME/.local/output` 또는 source `output/`은 runtime fallback이 아니다.

## project override 예시

global 기본값을 그대로 쓸 때 project `.sensai`를 만들 필요가 없다. 특정 schema 또는 recipe를 project에 고정해야 할 때만 같은 상대 경로의 regular file을 둔다.

```sh
mkdir -p "$TARGET_REPO/.sensai/schemas" "$TARGET_REPO/.sensai/recipes"
cp "$HOME/.config/opencode/schemas/trace.schema.json" \
  "$TARGET_REPO/.sensai/schemas/trace.schema.json"
cp "$HOME/.config/opencode/recipes/trace.jq" \
  "$TARGET_REPO/.sensai/recipes/trace.jq"
```

이 예시는 시작점일 뿐이다. project copy를 수정하면 JSON/jq syntax와 mission validator를 다시 통과해야 한다. invalid override를 둔 채 global fallback을 기대하지 않는다. project에서 override를 제거하려면 소유자가 해당 project file을 명시적으로 제거한 뒤 다시 검증한다.

## mission 시작과 상태 확인

대상 repository에서 installed CLI를 호출하면 CWD가 project root가 된다.

```sh
cd "$TARGET_REPO"

"$HOME/.local/bin/sensai" mission init \
  order-service \
  services/order \
  '주문 생성부터 결제 요청까지의 AS-IS를 분석하고 멱등성 변경안을 설계한다'

"$HOME/.local/bin/sensai" mission status order-service
```

다른 CWD에서 실행해야 한다면 physical absolute project root를 명시한다.

```sh
SENSAI_PROJECT_ROOT="$TARGET_REPO" \
  "$HOME/.local/bin/sensai" mission status order-service
```

`<mission-id>`는 traversal 없는 canonical slug여야 한다. target scope는 project root 기준 relative path다. mission state는 다음 경계에만 생성된다.

```text
docs/analysis/missions/<mission-id>/
  trace.json
  progress.json
  status.md
  artifacts/
  receipts/
```

같은 mission의 writer는 primary lead 하나다. checkpoint와 resume은 revision, current SHA-256, input fingerprint, selected asset provenance와 lock을 확인한다. stale·corrupt·double writer는 partial write 없이 실패해야 한다.

## OpenCode 사용 전 경계

OpenCode는 global config와 project-local OpenCode surface를 자체 규칙으로 merge할 수 있다. `OPENCODE_CONFIG_DIR`만 설정했다고 hermetic isolation이 되지는 않는다. semantic acceptance는 disposable `HOME`, 모든 XDG path, `TMPDIR`, neutral CWD와 inherited sentinel을 사용한다. `opencode debug`는 `.gitignore`, database, log 또는 lock을 만들 수 있으므로 source tree, 실제 HOME, 실제 target에서 acceptance 명령으로 실행하지 않는다.

target에 `opencode.json`, `opencode.jsonc`, `.opencode/`, `AGENTS.md`, `CLAUDE.md`가 있으면 지우거나 덮어쓰지 않는다. canonical global config와의 병합·permission·instruction 영향을 검토한 뒤 live 분석 여부를 결정한다.

`/sensai/run`, `/sensai/status`, `/sensai/resume`의 deterministic CLI binding은 `$HOME/.local/bin/sensai`를 사용한다. target의 `./bin/sensai`나 config-local CLI를 요구하지 않는다. live F0/F3/F5 승인은 current fingerprint에 결합된 human receipt가 있어야 하며 모델이 verdict를 발명할 수 없다.

실제 대상 저장소를 열기 전에는 [대상 저장소 preflight와 운영](target-repo-preflight-and-operations.md)의 physical path, secret-like path, OpenCode merge surface, Git 기준선 검사를 먼저 수행한다. 같은 문서는 F0-F5 승인 영수증, 실패 복구와 global 설치 퇴역 경계도 정의한다.

## 실패 reason과 대응

| reason | 의미 | 대응 |
| --- | --- | --- |
| `runtime.executable_invalid` | executable 위치·mode·symlink·physical path 오류 | source checkout의 tracked exact `bin/sensai` 또는 `$HOME/.local/bin/sensai` 사용 |
| `runtime.asset_missing` | 선택된 global/project asset이 없음 | provenance 경계에 필요한 regular file 설치 |
| `runtime.asset_invalid` | selected asset이 invalid, symlink, directory 또는 unsafe path | 해당 selected file을 수정하고 다시 실행; 다른 층으로 우회 금지 |
| `mission.project_root_invalid` | project root가 relative, symlink, non-directory 또는 filesystem root | physical absolute project directory 사용 |
| `package.config_root_invalid` | `$HOME/.config/opencode`가 없거나 physical directory가 아님 | 기존 global config root의 소유·형태 확인 |
| `package.cli_parent_invalid` | `$HOME/.local` 또는 `$HOME/.local/bin` 경계 충돌 | symlink·non-directory를 자동 교체하지 말고 소유자가 해결 |
| `package.managed_conflict` | managed config leaf 또는 CLI가 source와 같지 않음 | 자동 overwrite 금지; 기존 파일과 source를 사람이 비교 |
| `package.locked` | config 또는 CLI install lock 획득 실패 | 다른 install 종료와 lock 소유 상태 확인 후 재시도 |
| `package.rollback_failed` | created-file/owned-dir journal과 실제 상태 불일치 | 추가 쓰기를 중단하고 evidence와 남은 상태를 수동 점검 |
| `tool.unavailable` | 필수 독립 CLI 없음 | 올바른 제품을 설치하고 `doctor tools` 재실행 |
| `tool.identity_mismatch` | 동명 CLI가 요구 제품이 아님 | PATH와 제품 버전 수정 |
| `progress.resume.stale_hash` | active progress와 expected hash 불일치 | 최신 status와 hash로 새 resume 요청 |
| `progress.resume.stale_revision` | expected revision 불일치 | 최신 revision 확인 후 재시도 |

exit code는 `0` 성공, `64` usage, `65` data/config, `69` tool/transport unavailable, `73` create/install conflict, `75` lock·revision·hash conflict다.

## 보안과 운영 금지선

- 실제 credential, `.env`, raw model transcript를 config, mission receipt 또는 evidence에 복사하지 않는다.
- source `output/`을 target repository나 `$HOME/.local/output`에 runtime copy로 만들지 않는다.
- managed conflict를 overwrite, backup rename 또는 symlink로 우회하지 않는다.
- project override가 invalid일 때 global fallback을 강제하지 않는다.
- unmanaged global config content를 정리하거나 release archive에 포함하지 않는다.
- `~`, `/`, workspace root, source, target 또는 global config에 broad recursive delete를 사용하지 않는다.
- live model call은 명시적인 비용·credential 승인과 admission receipt 전에는 실행하지 않는다.

## 관련 계약

- [제품 계약](PROD.md)
- [대상 저장소 preflight와 운영](target-repo-preflight-and-operations.md)
- [runtime 계약](harness/runtime-contract.md)
- [검증 계약](harness/verification-contract.md)
- [release 계약](harness/release-contract.md)
- [구현 상태](harness/implementation-status.md)
- [R4 mapping](r4-mapping.md)
- [runtime AGENTS](../output/AGENTS.md)
- [OpenCode config](../output/opencode.json)

공식 OpenCode 문서는 rolling source다. 이 안내서의 config·permission·debug 해석은 repository가 고정한 OpenCode `1.18.3`에 한정한다. 다른 버전은 별도 disposable 환경에서 다시 검증한다.
