# OpenCode에 wonder-sensai를 격리 적용하고 대상 저장소를 분석하는 안내서

> [!IMPORTANT]
> **현재 가능한 범위와 중단선**
>
> commit `9306a49`의 canonical `output/` exact-set, repository-side CLI와 filesystem package의 결정적 검사는 구현돼 있다. 그러나 hermetic semantic load, live model response, tool use, TUI, delegation, Windows 실행과 실제 대상 저장소의 F0–F5 분석은 검증되지 않았다. 현재 상태는 `RUNTIME_CLI + FILESYSTEM_PACKAGING / MODEL_ADMISSION_UNVERIFIED`이며 다음 네 블로커를 모두 해소하기 전에는 live A-to-Z 분석을 시작하면 안 된다.
>
> 1. 설치되는 36-leaf `output/`에는 repository-side `bin/sensai`가 없다. 그런데 `/sensai/run`, `/sensai/status`, `/sensai/resume`은 `./bin/sensai`를 호출하고 현재 `permission.bash`도 이 실행을 허용하지 않는다.
> 2. F3–F5 명령이 요구하는 `sensai-dataflow-chart`, `sensai-user-story`, `sensai-requirement-analyze`, `sensai-change-design`, `sensai-test-scenario` 다섯 스킬은 현재 `permission.skill`에서 deny된다.
> 3. 분석 명령은 대상 코드를 읽어야 하지만 committed skill 문구는 “현재 미션 루트 밖을 읽거나 쓰지 말라”고 더 엄격하게 제한한다. 충돌 시 더 제한적인 계약을 적용하므로 target-read가 막힌다.
> 4. F0/F3/F5 승인 영수증은 command 계약에 필요하지만 이를 생성하는 canonical CLI나 사용자 interface, admitted writer가 없다. 모델이 대신 만들 수 없으므로 현재 F0 승인 단계도 통과할 수 없다.
>
> 따라서 지금 안전하게 수행할 수 있는 범위는 **격리 stage/install과 disposable semantic smoke 준비, provider/model 설정 확인, secret preflight를 통과한 입력에 대한 repository-side CLI 초기화 준비**까지다. semantic smoke를 직접 통과해도 위 네 runtime blocker와 target merge blocker는 남는다. 임의 권한 확대, CLI 복사, 승인 파일 수기 생성을 canonical 우회책으로 취급하지 말고 live 분석 전에 `STOP`한다.

이 문서는 OpenCode `1.18.3`을 기준으로 한다. “검증됨”은 현재 저장소의 결정적 검사 범위만 뜻하며, 모델이 실제 코드를 정확히 분석했다는 뜻이 아니다.

## 먼저 이해할 세 개의 루트

세 루트를 섞지 않는 것이 가장 중요한 안전 규칙이다.

| 루트 | 예시 | 역할 | 들어 있으면 안 되는 것 |
| --- | --- | --- | --- |
| source checkout | `/absolute/path/to/wonder-sensai2` | canonical `output/`, repository-side `bin/sensai`, `tests/`, `docs/`, `manifest.txt`를 보유 | 대상 저장소의 분석 산출물 |
| 격리 OpenCode config root | `/absolute/path/to/opencode-sensai-1.18.3` | canonical `output/`의 36개 leaf를 `output/` 접두사 없이 설치 | 기존 개인·회사 OpenCode 설정과 자격 증명 |
| 대상 저장소 | `/absolute/path/to/order-service` | 실제 읽기 대상이며, 향후 `docs/analysis/missions/<mission-id>/`가 생길 위치 | source checkout이나 전역 OpenCode 설정의 복사본 |

`./bin/sensai stage`와 `./bin/sensai install`은 동작상 같은 package transaction을 수행하고 출력의 `mode`만 다르다. 두 명령은 다음 계약을 따른다.

- 대상은 **존재하지 않는 정규화된 절대 경로**여야 한다. parent는 이미 존재하는 물리 디렉터리여야 하며 symlink component와 `..`를 허용하지 않는다.
- 대상이 이미 있으면 exit `73`으로 거부한다. merge, overwrite, backup을 수행하지 않는다.
- root `manifest.txt`에 정렬된 정확히 36개 leaf만 복사한다.
- source의 `output/` 접두사는 제거된다. 예를 들어 `output/opencode.json`은 config root의 `opencode.json`이 된다.
- repository-side `bin/`, `tests/`, `fixtures/`, `docs/`, root `AGENTS.md`, `manifest.txt`는 설치 payload에 포함되지 않는다.
- 같은 parent filesystem의 임시 sibling에서 완성한 뒤 한 번의 rename으로 공개하고, source/stage SHA-256 일치를 확인한다.

기존 대상 저장소 안이나 실제 global config에 설치하지 않는다. 특히 `TARGET_REPO/.opencode`, `~/.config/opencode`, 현재 사용 중인 `OPENCODE_CONFIG_DIR`는 설치 대상으로 삼지 않는다.

## 준비물

### 고정 버전과 도구

다음 실행 파일이 `PATH`에 있어야 한다.

| 실행 파일 | 요구되는 제품 |
| --- | --- |
| `opencode` | 정확히 OpenCode `1.18.3` |
| `fd` | fd |
| `rg` | ripgrep |
| `sg` | ast-grep |
| `jq` | jq |
| `yq` | Mike Farah yq |
| `mdq` | mdq |
| `mmdc` | Mermaid CLI |

source checkout에서 다음 두 명령을 먼저 실행한다.

```sh
./bin/sensai doctor tools
./bin/sensai doctor models
```

`doctor tools`는 설치를 대신하지 않는다. 실행 파일 존재 여부뿐 아니라 `sg`가 ast-grep인지, `yq`가 Mike Farah 제품인지, OpenCode가 정확히 `1.18.3`인지 확인한다. 잘못된 동명 도구는 `tool.identity_mismatch`로 거부된다.

`doctor models`는 모델을 호출하거나 자격 증명을 읽지 않는다. 다음 alias와 transport가 canonical config에 있는지만 확인한다.

- lead: `zai/glm-5.2`
- peer: `sensai-ollama/qwen3.5:9b`
- local transport: `http://localhost:11434/v1`
- admission: `UNVERIFIED`

`MODEL_ADMISSION_UNVERIFIED`는 설정에서 alias를 찾았더라도 응답, streaming, structured output, 단일·연속 tool call, delegation이 아직 입학되지 않았다는 뜻이다. `output/opencode.json`의 `apiKey: ollama`는 localhost OpenAI-compatible provider 형식을 위한 고정 자리표시자이며 실제 secret이 아니다. 실제 token이나 `.env`를 이 값에 복사하지 않는다.

## A. 작업 변수를 정한다

아래 값은 사용자가 바꾸는 명시적 예시다. 모두 따옴표를 유지한다.

```sh
set -eu

SENSAI_SOURCE="/absolute/path/to/wonder-sensai2"
SENSAI_BASELINE_COMMIT="9306a49a36c110498e52bd212a3bf0c1f7eb8489"
SENSAI_CONFIG_PARENT="/absolute/path/to/dedicated-config-parent"
SENSAI_CONFIG="$SENSAI_CONFIG_PARENT/opencode-sensai-1.18.3"
TARGET_REPO_INPUT="/absolute/path/to/order-service"
TARGET_SCOPE="services/order"
MISSION_ID="order-service"
GOAL="주문 생성부터 결제 요청까지의 AS-IS를 분석하고 멱등성 변경안을 설계한다"

test "$(git -C "$SENSAI_SOURCE" rev-parse HEAD)" = "$SENSAI_BASELINE_COMMIT"
test -z "$(git -C "$SENSAI_SOURCE" status --short -- output bin/sensai manifest.txt)"
```

`SENSAI_CONFIG_PARENT`는 이미 존재해야 하고 `SENSAI_CONFIG`는 존재하지 않아야 한다. source, config, target은 서로 다른 경로로 둔다. 마지막 두 검사는 이 문서가 근거로 삼지 않는 uncommitted runtime WIP를 실수로 stage/install하지 않도록 막는다. runtime source가 dirty하거나 다른 commit이면 이 버전의 명령을 실행하지 않는다.

## B. 대상 저장소를 사전 점검한다

### 모든 component가 물리 경로인지 확인

```sh
set -eu

absolute_path_without_symlink_components() {
  CHECK_PATH=$1
  case "$CHECK_PATH" in
    /*) ;;
    *) return 1 ;;
  esac
  case "$CHECK_PATH" in
    /|*/|*//*|*/./*|*/../*|*/.|*/..) return 1 ;;
  esac
  CHECK_CURRENT=/
  CHECK_RELATIVE=${CHECK_PATH#/}
  CHECK_OLD_IFS=$IFS
  IFS=/
  set -f
  set -- $CHECK_RELATIVE
  set +f
  IFS=$CHECK_OLD_IFS
  for CHECK_COMPONENT do
    case "$CHECK_COMPONENT" in
      ''|.|..) return 1 ;;
    esac
    if test "$CHECK_CURRENT" = /; then
      CHECK_CURRENT=/$CHECK_COMPONENT
    else
      CHECK_CURRENT=$CHECK_CURRENT/$CHECK_COMPONENT
    fi
    test ! -L "$CHECK_CURRENT" || return 1
  done
}

absolute_path_without_symlink_components "$TARGET_REPO_INPUT"
TARGET_REPO_PHYSICAL="$(CDPATH= cd -- "$TARGET_REPO_INPUT" && pwd -P)"
test "$TARGET_REPO_INPUT" = "$TARGET_REPO_PHYSICAL"
TARGET_REPO=$TARGET_REPO_PHYSICAL
test -d "$TARGET_REPO"
```

마지막 leaf만 `test ! -L`로 검사해서는 부족하다. 위 함수는 root부터 target까지 모든 component를 순서대로 검사하고, symlink, `.`·`..`, 중복 slash와 filesystem root를 거부한다.

### 상대 scope 검증

`TARGET_SCOPE`는 대상 root 기준 상대 경로다. 절대 경로, 빈 값, **어느 위치에든 있는** `.`·`..` component, 중복 slash를 거부한다.

```sh
relative_scope_without_symlink_components() {
  SCOPE_VALUE=$1
  case "$SCOPE_VALUE" in
    ''|/*|*//*|*"
"*|*"	"*) return 1 ;;
    .git|.git/*|.omo|.omo/*|docs/analysis/missions|docs/analysis/missions/*) return 1 ;;
  esac
  SCOPE_CURRENT=$TARGET_REPO
  SCOPE_OLD_IFS=$IFS
  IFS=/
  set -f
  set -- $SCOPE_VALUE
  set +f
  IFS=$SCOPE_OLD_IFS
  for SCOPE_COMPONENT do
    case "$SCOPE_COMPONENT" in
      ''|.|..) return 1 ;;
    esac
    SCOPE_CURRENT=$SCOPE_CURRENT/$SCOPE_COMPONENT
    test ! -L "$SCOPE_CURRENT" || return 1
  done
  test -e "$SCOPE_CURRENT"
}

relative_scope_without_symlink_components "$TARGET_SCOPE"
TARGET_SCOPE_PATH=$TARGET_REPO/$TARGET_SCOPE
SCOPE_SYMLINK="$(find "$TARGET_SCOPE_PATH" -type l -print -quit)" || exit 69
test -z "$SCOPE_SYMLINK"
```

component 검사 뒤 마지막 `find`는 scope 내부의 symlink도 하나라도 발견하면 실패한다. `a/./b`, `a/../b`와 내부 symlink가 안전해 보이더라도 committed CLI 계약은 이를 허용하지 않으므로 우회하지 않는다.

### secret-like path 이름을 content 없이 검사

commit `9306a49`의 `bin/sensai`는 mission 입력 hash를 만들 때 선택한 scope 아래의 **모든 regular file 내용을 `shasum`으로 읽는다**. directory scope에서는 `$TARGET_REPO/.git`, `$TARGET_REPO/.omo`, `$TARGET_REPO/docs/analysis/missions`만 prune한다. OpenCode의 이후 read permission과 별개이므로, secret 이름 예시를 문서에 적는 것만으로는 보호되지 않는다.

따라서 `mission init`, `status`, `checkpoint`, `resume`, OpenCode와 model을 실행하기 전에 path 이름만 검사한다. 아래 `find`는 파일 content를 열지 않고 pathname만 전달하며, secret-like 이름을 발견하면 temp marker를 남겨 `STOP`한다.

```sh
SECRET_SCAN_ROOT="$(mktemp -d /private/tmp/sensai-secret-scan.XXXXXX)" || exit 73
SECRET_FOUND_MARKER=$SECRET_SCAN_ROOT/found

SECRET_SCAN_OK=1
find "$TARGET_SCOPE_PATH" \
  -path "$TARGET_REPO/.git" -prune -o \
  -path "$TARGET_REPO/.omo" -prune -o \
  -path "$TARGET_REPO/docs/analysis/missions" -prune -o \
  -exec sh -c '
    SECRET_MARKER=$1
    SECRET_ROOT=$2
    shift 2
    for SECRET_PATH do
      SECRET_RELATIVE=${SECRET_PATH#"$SECRET_ROOT"/}
      SECRET_BASENAME=${SECRET_PATH##*/}
      SECRET_MATCH=0
      case "$SECRET_BASENAME" in
        .env|.env.*|*.pem|*id_rsa*|*credentials*|*secrets.*|auth.json)
          SECRET_MATCH=1
          ;;
      esac
      case "/$SECRET_RELATIVE/" in
        */.ssh/*|*/.aws/*|*/.config/opencode/*|*/.local/share/opencode/*)
          SECRET_MATCH=1
          ;;
      esac
      if test "$SECRET_MATCH" -eq 1; then
        : >"$SECRET_MARKER"
        printf "SECRET_LIKE_PATH=%s\n" "$SECRET_RELATIVE" >&2
      fi
    done
  ' sh "$SECRET_FOUND_MARKER" "$TARGET_SCOPE_PATH" {} + || SECRET_SCAN_OK=0

SECRET_PATH_FOUND=0
test ! -e "$SECRET_FOUND_MARKER" || SECRET_PATH_FOUND=1
case "$SECRET_SCAN_ROOT" in
  /private/tmp/sensai-secret-scan.*) find "$SECRET_SCAN_ROOT" -depth -delete ;;
  *) printf '%s\n' "정리 거부: $SECRET_SCAN_ROOT" >&2; exit 73 ;;
esac
test "$SECRET_SCAN_OK" -eq 1 || exit 69
test "$SECRET_PATH_FOUND" -eq 0 || exit 65
```

검출된 파일을 열어 확인하지 않는다. 이름만으로 false positive라고 판단하거나 ignore해서도 안 된다. 소유자가 scope에서 제외하거나 안전한 별도 입력 사본을 마련한 뒤 처음부터 preflight한다. 이 검사를 통과해도 secret 부재를 증명하는 것은 아니며, 현재 committed CLI가 secret content를 절대로 읽지 않는다고 주장할 수 없다.

### target runtime merge surface 확인

OpenCode의 config source는 한 파일이 다른 파일을 통째로 대체하는 방식이 아니라 여러 층에서 merge될 수 있다. target project의 instruction도 configured `instructions`와 함께 적용될 수 있다. 따라서 아래 project-local surface를 사전에 확인한다.

```sh
TARGET_MERGE_SURFACE_FOUND=0
for TARGET_MERGE_SURFACE in \
  opencode.json opencode.jsonc .opencode AGENTS.md CLAUDE.md; do
  if test -e "$TARGET_REPO/$TARGET_MERGE_SURFACE" || \
     test -L "$TARGET_REPO/$TARGET_MERGE_SURFACE"; then
    printf '%s\n' "TARGET_MERGE_SURFACE=$TARGET_MERGE_SURFACE"
    TARGET_MERGE_SURFACE_FOUND=1
  fi
done
test "$TARGET_MERGE_SURFACE_FOUND" -eq 0
```

하나라도 발견되면 원본을 보존하고 live 분석 전에 `STOP`한다. 현재 하네스에는 target-local `opencode.json`, `opencode.jsonc`, `.opencode/`, `AGENTS.md`, `CLAUDE.md`와 canonical runtime을 어떻게 결합할지 승인된 merge policy가 없다. 파일을 덮어쓰거나 이름을 바꾸거나 자동 merge하지 말고, 각 지침·권한·agent·command의 충돌을 다루는 별도 계약과 admission을 먼저 만든다. neutral disposable smoke의 성공은 특정 target에서의 merged config나 combined instruction 동작을 증명하지 않는다.

### dirty change 처리 결정

secret과 merge-surface 검사를 모두 통과한 뒤에만 Git 기준선을 기록한다.

```sh
test "$(git -C "$TARGET_REPO" rev-parse --is-inside-work-tree)" = "true"
test "$(git -C "$TARGET_REPO" rev-parse --show-toplevel)" = "$TARGET_REPO"
git -C "$TARGET_REPO" status --short
git -C "$TARGET_REPO" rev-parse HEAD
```

`git status --short`가 비어 있지 않다면 분석 전에 사람이 다음 중 하나를 명시한다.

- 현재 dirty 파일도 입력으로 포함한다.
- 특정 경로는 scope에서 제외한다.
- 소유자가 먼저 별도 commit 또는 보관을 마친 뒤 새 HEAD에서 시작한다.

하네스가 dirty change를 자동 discard, stash, commit하면 안 된다. 기준선에는 `HEAD`, `git status --short`, 입력 hash와 포함·제외 결정을 함께 남긴다.

다음은 입력에서 제외해야 하는 대표 path다. 위 사전검사 없이 “읽지 않는다”고 가정하지 않는다.

- `.env`, `*.pem`, `id_rsa`, credential·secret 파일
- 실제 global OpenCode config와 auth data
- raw model transcript
- scope 밖 파일과 symlink가 가리키는 외부 파일

OpenCode `permission`은 행동 정책과 승인 UI이지 OS sandbox가 아니다. 진짜 격리는 별도 `HOME`, XDG, `TMPDIR`, neutral CWD, filesystem·network 경계로 만든다.

## C. 일회용 stage로 package를 점검한다

이 단계는 실제 config 설치 전에 disposable target에 36개 leaf가 원자적으로 배치되는지 확인한다.

```sh
STAGE_PARENT="$(mktemp -d /private/tmp/sensai-stage-parent.XXXXXX)"
STAGE_CONFIG="$STAGE_PARENT/config"

"$SENSAI_SOURCE/bin/sensai" stage "$STAGE_CONFIG"
test "$(find "$STAGE_CONFIG" -mindepth 1 ! -type d | wc -l | tr -d ' ')" = "36"
test -f "$STAGE_CONFIG/AGENTS.md"
test -f "$STAGE_CONFIG/opencode.json"
test ! -e "$STAGE_CONFIG/bin/sensai"
```

예상 출력에는 `mode=stage`, `status=READY`, `files=36`, payload hash와 target 경로가 보인다. target이 이미 존재하면 삭제하거나 합치지 말고 새 absent path를 만든다. `bin/sensai`가 없다는 검사는 committed package 경계를 확인하는 것이며 slash-command blocker가 해소됐다는 뜻이 아니다.

일회용 stage를 정리할 때는 확인된 전용 temp root만 지운다.

```sh
case "$STAGE_PARENT" in
  /private/tmp/sensai-stage-parent.*) find "$STAGE_PARENT" -depth -delete ;;
  *) printf '%s\n' "정리 거부: $STAGE_PARENT" >&2; exit 73 ;;
esac
```

## D. 지속 사용할 격리 config에 설치한다

실제 global config가 아닌 전용 absent path에만 설치한다.

```sh
(
test -n "${SENSAI_CONFIG:-}" || exit 73
test -n "${SENSAI_CONFIG_PARENT:-}" || exit 73
test -n "${SENSAI_SOURCE:-}" || exit 73
test -n "${TARGET_REPO:-}" || exit 73
test -n "${HOME:-}" || exit 73
set -u

config_install_normalized_path() {
  test "$#" -eq 1 || return 1
  case "$1" in
    /*) ;;
    *) return 1 ;;
  esac
  case "$1" in
    /|*/|*//*|*/./*|*/../*|*/.|*/..) return 1 ;;
  esac
  return 0
}

config_install_physical_identity() {
  test "$#" -eq 1 || return 1
  CONFIG_INSTALL_INPUT=$1
  config_install_normalized_path "$CONFIG_INSTALL_INPUT" || return 1
  if test -e "$CONFIG_INSTALL_INPUT" || test -L "$CONFIG_INSTALL_INPUT"; then
    test -d "$CONFIG_INSTALL_INPUT" || return 1
    (CDPATH= cd -- "$CONFIG_INSTALL_INPUT" && pwd -P) || return 1
    return 0
  fi
  CONFIG_INSTALL_PARENT=${CONFIG_INSTALL_INPUT%/*}
  CONFIG_INSTALL_LEAF=${CONFIG_INSTALL_INPUT##*/}
  test -n "$CONFIG_INSTALL_LEAF" || return 1
  test -n "$CONFIG_INSTALL_PARENT" || CONFIG_INSTALL_PARENT=/
  test -d "$CONFIG_INSTALL_PARENT" || return 1
  CONFIG_INSTALL_PARENT_PHYSICAL="$(
    CDPATH= cd -- "$CONFIG_INSTALL_PARENT" && pwd -P
  )" || return 1
  if test "$CONFIG_INSTALL_PARENT_PHYSICAL" = /; then
    printf '/%s\n' "$CONFIG_INSTALL_LEAF"
  else
    printf '%s/%s\n' \
      "$CONFIG_INSTALL_PARENT_PHYSICAL" "$CONFIG_INSTALL_LEAF"
  fi
}

config_install_existing_directory() {
  test "$#" -eq 1 || return 1
  test -d "$1" || return 1
  config_install_physical_identity "$1" || return 1
}

config_install_roots_are_disjoint() {
  test "$#" -eq 2 || return 1
  case "$1" in
    "$2"|"$2"/*) return 1 ;;
  esac
  case "$2" in
    "$1"|"$1"/*) return 1 ;;
  esac
  return 0
}

test ! -e "$SENSAI_CONFIG" || exit 73
test ! -L "$SENSAI_CONFIG" || exit 73
CONFIG_INSTALL_CANDIDATE="$(
  config_install_physical_identity "$SENSAI_CONFIG"
)" || exit 73
test "$CONFIG_INSTALL_CANDIDATE" = "$SENSAI_CONFIG" || exit 73
CONFIG_INSTALL_PARENT_PHYSICAL="$(
  config_install_existing_directory "$SENSAI_CONFIG_PARENT"
)" || exit 73
case "$CONFIG_INSTALL_CANDIDATE" in
  "$CONFIG_INSTALL_PARENT_PHYSICAL"/*) ;;
  *) exit 73 ;;
esac
CONFIG_INSTALL_SOURCE_PHYSICAL="$(
  config_install_existing_directory "$SENSAI_SOURCE"
)" || exit 73
CONFIG_INSTALL_TARGET_PHYSICAL="$(
  config_install_existing_directory "$TARGET_REPO"
)" || exit 73
CONFIG_INSTALL_HOME_PHYSICAL="$(
  config_install_existing_directory "$HOME"
)" || exit 73
if test -n "${OPENCODE_CONFIG_DIR:-}"; then
  CONFIG_INSTALL_ACTUAL_GLOBAL=$OPENCODE_CONFIG_DIR
else
  CONFIG_INSTALL_ACTUAL_XDG=${XDG_CONFIG_HOME:-$CONFIG_INSTALL_HOME_PHYSICAL/.config}
  CONFIG_INSTALL_ACTUAL_GLOBAL=$CONFIG_INSTALL_ACTUAL_XDG/opencode
fi
CONFIG_INSTALL_ACTUAL_GLOBAL_PHYSICAL="$(
  config_install_physical_identity "$CONFIG_INSTALL_ACTUAL_GLOBAL"
)" || exit 73

for CONFIG_INSTALL_PROTECTED in \
  "$CONFIG_INSTALL_SOURCE_PHYSICAL" "$CONFIG_INSTALL_TARGET_PHYSICAL" \
  "$CONFIG_INSTALL_HOME_PHYSICAL" \
  "$CONFIG_INSTALL_ACTUAL_GLOBAL_PHYSICAL"; do
  config_install_roots_are_disjoint \
    "$CONFIG_INSTALL_CANDIDATE" "$CONFIG_INSTALL_PROTECTED" || exit 73
done

"$SENSAI_SOURCE/bin/sensai" install "$SENSAI_CONFIG" || exit 73
)
```

이 config root는 개인 설정과 merge할 용도가 아니다. persistent라는 말은 “이번 확인 뒤 자동 삭제하지 않는다”는 뜻일 뿐, global config로 승격한다는 뜻이 아니다.

## E. 완전히 일회용인 semantic smoke를 수행한다

다음 예시는 config뿐 아니라 `HOME`, 모든 XDG 경로, `TMPDIR`, CWD를 격리한다. `OPENCODE_CONFIG_DIR`만 지정하면 다른 설정 층과 merge되므로 full isolation이 아니다. `opencode debug`는 `.gitignore`, database, log, lock 같은 초기화 파일을 쓸 수 있는 mutating diagnostic이므로 source tree, 대상 저장소, 실제 HOME에서 실행하지 않는다.

아래 smoke는 모델을 호출하지 않는다. 실제 `$TARGET_REPO`를 열거나 hash하지 않고, `$SMOKE_ROOT/work` 안에 내용이 알려진 disposable Git repository를 만든다. 그 repository에서 exact 2 agent, 9 nested command, 15 skill을 확인하고 알려진 `README.md`의 SHA-256과 clean Git status가 바뀌지 않았는지 검사한 뒤 전용 temp root를 정리한다.

commit `9306a49`에는 repository-owned hermetic semantic-load acceptance receipt가 없다. 아래 블록은 사용자가 직접 실행할 수 있는 격리 smoke 절차이며, 실제로 통과하기 전에는 현재 검증 결과로 기록하지 않는다.

```sh
SMOKE_ROOT="$(mktemp -d /private/tmp/sensai-smoke.XXXXXX)" || exit 73
SMOKE_STATUS=0
if SENSAI_SOURCE="$SENSAI_SOURCE" SMOKE_ROOT="$SMOKE_ROOT" PATH="$PATH" \
  /bin/sh -eu <<'SENSAI_SEMANTIC_SMOKE'

OPENCODE_BIN="$(command -v opencode)"
SMOKE_CONFIG="$SMOKE_ROOT/config"
SMOKE_HOME="$SMOKE_ROOT/home"
SMOKE_XDG_CONFIG="$SMOKE_ROOT/xdg-config"
SMOKE_XDG_DATA="$SMOKE_ROOT/xdg-data"
SMOKE_XDG_CACHE="$SMOKE_ROOT/xdg-cache"
SMOKE_XDG_STATE="$SMOKE_ROOT/xdg-state"
SMOKE_TMP="$SMOKE_ROOT/tmp"
SMOKE_WORK="$SMOKE_ROOT/work"
SMOKE_TARGET="$SMOKE_WORK/target-repo"

cleanup_smoke() {
  case "$SMOKE_ROOT" in
    /private/tmp/sensai-smoke.*) find "$SMOKE_ROOT" -depth -delete ;;
    *) printf '%s\n' "정리 거부: $SMOKE_ROOT" >&2; return 73 ;;
  esac
}
trap cleanup_smoke EXIT

mkdir -p "$SMOKE_HOME" "$SMOKE_XDG_CONFIG" "$SMOKE_XDG_DATA" \
  "$SMOKE_XDG_CACHE" "$SMOKE_XDG_STATE" "$SMOKE_TMP" "$SMOKE_TARGET"

git -C "$SMOKE_TARGET" init -q
printf '%s\n' '# disposable semantic-load target' >"$SMOKE_TARGET/README.md"
git -C "$SMOKE_TARGET" add README.md
git -C "$SMOKE_TARGET" \
  -c user.name=sensai-smoke -c user.email=sensai-smoke@invalid \
  commit -qm 'test: initialize disposable target'

README_SHA_BEFORE="$(shasum -a 256 "$SMOKE_TARGET/README.md" | awk '{print $1}')"
TARGET_STATUS_BEFORE="$(git -C "$SMOKE_TARGET" status --short)"
test -z "$TARGET_STATUS_BEFORE"
"$SENSAI_SOURCE/bin/sensai" stage "$SMOKE_CONFIG"

(
  cd "$SMOKE_TARGET"
  env -i \
    PATH="$PATH" \
    HOME="$SMOKE_HOME" \
    XDG_CONFIG_HOME="$SMOKE_XDG_CONFIG" \
    XDG_DATA_HOME="$SMOKE_XDG_DATA" \
    XDG_CACHE_HOME="$SMOKE_XDG_CACHE" \
    XDG_STATE_HOME="$SMOKE_XDG_STATE" \
    TMPDIR="$SMOKE_TMP/" \
    OPENCODE_CONFIG_DIR="$SMOKE_CONFIG" \
    USER=sensai-smoke LOGNAME=sensai-smoke SHELL=/bin/sh \
    LANG=C.UTF-8 LC_ALL=C CI=1 \
    "$OPENCODE_BIN" debug config --pure
) >"$SMOKE_ROOT/config.json"

(
  cd "$SMOKE_TARGET"
  env -i \
    PATH="$PATH" \
    HOME="$SMOKE_HOME" \
    XDG_CONFIG_HOME="$SMOKE_XDG_CONFIG" \
    XDG_DATA_HOME="$SMOKE_XDG_DATA" \
    XDG_CACHE_HOME="$SMOKE_XDG_CACHE" \
    XDG_STATE_HOME="$SMOKE_XDG_STATE" \
    TMPDIR="$SMOKE_TMP/" \
    OPENCODE_CONFIG_DIR="$SMOKE_CONFIG" \
    USER=sensai-smoke LOGNAME=sensai-smoke SHELL=/bin/sh \
    LANG=C.UTF-8 LC_ALL=C CI=1 \
    "$OPENCODE_BIN" debug skill --pure
) >"$SMOKE_ROOT/skills.json"

jq -e '
  ([.agent | to_entries[] | select(.key | startswith("sensai-")) | .key] | sort)
  == (["sensai-analysis-lead", "sensai-evidence-peer"] | sort)
' \
  "$SMOKE_ROOT/config.json"
jq -e '
  ([.command | to_entries[] | select(.key | startswith("sensai/")) | .key] | sort)
  == ([
    "sensai/analyze", "sensai/analyze-business", "sensai/change-design",
    "sensai/deliver", "sensai/document-asis", "sensai/resume", "sensai/run",
    "sensai/status", "sensai/verify"
  ] | sort)
' \
  "$SMOKE_ROOT/config.json"
jq -e '
  ([.[] | select(.name | startswith("sensai-")) | .name] | sort)
  == ([
    "sensai-business-trace", "sensai-change-design", "sensai-checklist",
    "sensai-convention-extract", "sensai-dataflow-chart", "sensai-evidence-first",
    "sensai-mermaid-sequence", "sensai-react-trace", "sensai-requirement-analyze",
    "sensai-spec-evidence", "sensai-stack-discovery", "sensai-test-scenario",
    "sensai-ui-definition", "sensai-user-story", "sensai-vertx-trace"
  ] | sort)
' \
  "$SMOKE_ROOT/skills.json"

while IFS= read -r PAYLOAD_LEAF; do
  cmp -s "$SENSAI_SOURCE/output/$PAYLOAD_LEAF" "$SMOKE_CONFIG/$PAYLOAD_LEAF"
done <"$SENSAI_SOURCE/manifest.txt"

README_SHA_AFTER="$(shasum -a 256 "$SMOKE_TARGET/README.md" | awk '{print $1}')"
TARGET_STATUS_AFTER="$(git -C "$SMOKE_TARGET" status --short)"
test "$README_SHA_BEFORE" = "$README_SHA_AFTER"
test "$TARGET_STATUS_BEFORE" = "$TARGET_STATUS_AFTER"
printf '%s\n' \
  "SEMANTIC_LOAD=PASS agents=2 commands=9 skills=15 disposable_target_unchanged=true"
SENSAI_SEMANTIC_SMOKE
then
  SMOKE_STATUS=0
else
  SMOKE_STATUS=$?
fi
test ! -e "$SMOKE_ROOT"
test "$SMOKE_STATUS" -eq 0
unset SMOKE_ROOT SMOKE_STATUS
```

`SEMANTIC_LOAD=PASS`는 이 수동 실행에서 관찰한 config/agent/command/skill 적재와 disposable target 불변만 뜻한다. 실제 `$TARGET_REPO`를 검사한 결과가 아니며 live model, tool use, TUI, delegation, target-specific merge, F0–F5 분석 성공으로 해석하지 않는다. commit `9306a49`에는 두 번의 idempotent load, inherited-config sentinel, 실제 global/source 전후 fingerprint와 init-file exact-set을 묶어 판정하는 repository acceptance가 아직 없다.

## F. 준비 상태를 판정한다

| 관찰 | 판정 | 다음 행동 |
| --- | --- | --- |
| `doctor tools` 또는 semantic load 실패 | `STOP` | 도구 identity, OpenCode `1.18.3`, path, inherited config를 고친 뒤 smoke부터 반복 |
| provider/model ID가 목록에 없음 | `STOP` | provider와 model discovery를 준비하되 secret을 출력·복사하지 않음 |
| target runtime merge surface가 하나라도 존재 | `STOP` | 원본을 보존하고 target-specific merge policy와 admission을 먼저 마련 |
| secret-like path가 하나라도 발견됨 | `STOP` | content를 열지 말고 scope 제외 또는 안전한 별도 입력을 사람이 결정 |
| `MODEL_ADMISSION_UNVERIFIED` | `STOP_BEFORE_MODEL_ANALYSIS` | 승인된 live admission matrix와 current-fingerprint receipt를 기다림 |
| 다섯 F3–F5 skill이 deny됨 | `STOP_BEFORE_MODEL_ANALYSIS` | 임의 allow 없이 permission 계약과 admission을 먼저 수정·검증 |
| target-read와 mission-root-only skill 계약이 충돌 | `STOP_BEFORE_MODEL_ANALYSIS` | source 계약을 정합하게 고치고 다시 admission |
| canonical approval receipt 생성 interface가 없음 | `STOP_AT_F0_GATE` | writer를 발명하거나 수기 JSON을 만들지 말고 interface 구현·검증을 기다림 |
| 모든 blocker가 해소되고 미래 runtime admission이 승인됨 | `READY_TO_ATTEMPT` | 아래 의도된 F0–F5 흐름을 실제 대상에서 시도하고 새 evidence를 기록 |

committed baseline `9306a49`는 마지막 행으로 판정할 수 없다. semantic smoke가 성공해도 지금의 올바른 결론은 `STOP_BEFORE_MODEL_ANALYSIS`와 `STOP_AT_F0_GATE`다.

### 미래 runtime admission 뒤의 격리 실행 예시

> 이 예시는 현재 실행 절차가 아니다. 네 committed runtime blocker, secret·target merge preflight, provider/model admission이 모두 해결되고 current-fingerprint receipt가 승인된 미래에만 사용한다. 현재 상태에서는 계속 `STOP_BEFORE_MODEL_ANALYSIS` 또는 `STOP_AT_F0_GATE`를 적용한다.

설치된 `$SENSAI_CONFIG`와 별도로, login state·database·cache·lock·temp를 보관할 지속형 isolated runtime root를 하나 정한다. 아래 경로는 사용자가 교체하는 전용 절대 경로 예시다. 기존 디렉터리를 재사용하지 않고, 물리 parent 아래의 absent leaf를 `mkdir` 한 번으로 소유한 뒤 marker를 기록한다.

```sh
SENSAI_RUNTIME_ROOT="/absolute/path/to/persistent-isolated-sensai-runtime"
SENSAI_RUNTIME_MARKER="$SENSAI_RUNTIME_ROOT/.wonder-sensai-isolated-runtime"
SENSAI_RUNTIME_HOME="$SENSAI_RUNTIME_ROOT/home"
SENSAI_RUNTIME_XDG_CONFIG="$SENSAI_RUNTIME_ROOT/xdg-config"
SENSAI_RUNTIME_XDG_DATA="$SENSAI_RUNTIME_ROOT/xdg-data"
SENSAI_RUNTIME_XDG_CACHE="$SENSAI_RUNTIME_ROOT/xdg-cache"
SENSAI_RUNTIME_XDG_STATE="$SENSAI_RUNTIME_ROOT/xdg-state"
SENSAI_RUNTIME_TMP="$SENSAI_RUNTIME_ROOT/tmp"
OPENCODE_BIN="$(command -v opencode)"

normalized_absolute_nonroot_path() {
  test "$#" -eq 1 || return 1
  case "$1" in
    /*) ;;
    *) return 1 ;;
  esac
  case "$1" in
    /|*/|*//*|*/./*|*/../*|*/.|*/..) return 1 ;;
  esac
  return 0
}

physical_directory_identity() {
  test "$#" -eq 1 || return 1
  PHYSICAL_INPUT=$1
  normalized_absolute_nonroot_path "$PHYSICAL_INPUT" || return 1
  if test -e "$PHYSICAL_INPUT" || test -L "$PHYSICAL_INPUT"; then
    test -d "$PHYSICAL_INPUT" || return 1
    (CDPATH= cd -- "$PHYSICAL_INPUT" && pwd -P) || return 1
    return 0
  fi
  PHYSICAL_PARENT=${PHYSICAL_INPUT%/*}
  PHYSICAL_LEAF=${PHYSICAL_INPUT##*/}
  test -n "$PHYSICAL_LEAF" || return 1
  test -n "$PHYSICAL_PARENT" || PHYSICAL_PARENT=/
  test -d "$PHYSICAL_PARENT" || return 1
  PHYSICAL_PARENT_ID="$(CDPATH= cd -- "$PHYSICAL_PARENT" && pwd -P)" || return 1
  test -n "$PHYSICAL_PARENT_ID" || return 1
  if test "$PHYSICAL_PARENT_ID" = /; then
    printf '/%s\n' "$PHYSICAL_LEAF"
  else
    printf '%s/%s\n' "$PHYSICAL_PARENT_ID" "$PHYSICAL_LEAF"
  fi
}

physical_existing_directory() {
  test "$#" -eq 1 || return 1
  test -d "$1" || return 1
  physical_directory_identity "$1" || return 1
}

runtime_root_is_absent_and_physical() {
  test "$#" -eq 1 || return 1
  test ! -e "$1" || return 1
  test ! -L "$1" || return 1
  RUNTIME_CANDIDATE_PHYSICAL="$(physical_directory_identity "$1")" || return 1
  test "$RUNTIME_CANDIDATE_PHYSICAL" = "$1" || return 1
  printf '%s\n' "$RUNTIME_CANDIDATE_PHYSICAL"
}

roots_are_disjoint() {
  test "$#" -eq 2 || return 1
  for DISJOINT_ROOT do
    case "$DISJOINT_ROOT" in
      /*) ;;
      *) return 1 ;;
    esac
    case "$DISJOINT_ROOT" in
      /|*/|*//*|*/./*|*/../*|*/.|*/..) return 1 ;;
    esac
  done
  case "$1" in
    "$2"|"$2"/*) return 1 ;;
  esac
  case "$2" in
    "$1"|"$1"/*) return 1 ;;
  esac
  return 0
}

SENSAI_SOURCE_PHYSICAL="$(physical_existing_directory "$SENSAI_SOURCE")" || exit 73
SENSAI_CONFIG_PHYSICAL="$(physical_existing_directory "$SENSAI_CONFIG")" || exit 73
TARGET_REPO_PHYSICAL="$(physical_existing_directory "$TARGET_REPO")" || exit 73
ACTUAL_HOME_PHYSICAL="$(physical_existing_directory "${HOME:?}")" || exit 73
if test -n "${OPENCODE_CONFIG_DIR:-}"; then
  ACTUAL_OPENCODE_CONFIG=$OPENCODE_CONFIG_DIR
else
  ACTUAL_XDG_CONFIG=${XDG_CONFIG_HOME:-$ACTUAL_HOME_PHYSICAL/.config}
  ACTUAL_OPENCODE_CONFIG=$ACTUAL_XDG_CONFIG/opencode
fi
ACTUAL_OPENCODE_CONFIG_PHYSICAL="$(
  physical_directory_identity "$ACTUAL_OPENCODE_CONFIG"
)" || exit 73
SENSAI_RUNTIME_PHYSICAL="$(
  runtime_root_is_absent_and_physical "$SENSAI_RUNTIME_ROOT"
)" || exit 73

for RESERVED_ROOT in \
  "$SENSAI_SOURCE_PHYSICAL" "$SENSAI_CONFIG_PHYSICAL" \
  "$TARGET_REPO_PHYSICAL" "$ACTUAL_HOME_PHYSICAL" \
  "$ACTUAL_OPENCODE_CONFIG_PHYSICAL"; do
  roots_are_disjoint "$SENSAI_RUNTIME_PHYSICAL" "$RESERVED_ROOT" || exit 73
done

mkdir "$SENSAI_RUNTIME_ROOT"
printf '%s\n' 'wonder-sensai isolated runtime root v1' >"$SENSAI_RUNTIME_MARKER"
mkdir -p "$SENSAI_RUNTIME_HOME" "$SENSAI_RUNTIME_XDG_CONFIG" \
  "$SENSAI_RUNTIME_XDG_DATA" "$SENSAI_RUNTIME_XDG_CACHE" \
  "$SENSAI_RUNTIME_XDG_STATE" "$SENSAI_RUNTIME_TMP"

env -i \
  PATH="$PATH" \
  HOME="$SENSAI_RUNTIME_HOME" \
  XDG_CONFIG_HOME="$SENSAI_RUNTIME_XDG_CONFIG" \
  XDG_DATA_HOME="$SENSAI_RUNTIME_XDG_DATA" \
  XDG_CACHE_HOME="$SENSAI_RUNTIME_XDG_CACHE" \
  XDG_STATE_HOME="$SENSAI_RUNTIME_XDG_STATE" \
  TMPDIR="$SENSAI_RUNTIME_TMP/" \
  OPENCODE_CONFIG_DIR="$SENSAI_CONFIG" \
  USER=sensai-runtime LOGNAME=sensai-runtime SHELL=/bin/sh \
  LANG=C.UTF-8 LC_ALL=C \
  "$OPENCODE_BIN" providers list

env -i \
  PATH="$PATH" \
  HOME="$SENSAI_RUNTIME_HOME" \
  XDG_CONFIG_HOME="$SENSAI_RUNTIME_XDG_CONFIG" \
  XDG_DATA_HOME="$SENSAI_RUNTIME_XDG_DATA" \
  XDG_CACHE_HOME="$SENSAI_RUNTIME_XDG_CACHE" \
  XDG_STATE_HOME="$SENSAI_RUNTIME_XDG_STATE" \
  TMPDIR="$SENSAI_RUNTIME_TMP/" \
  OPENCODE_CONFIG_DIR="$SENSAI_CONFIG" \
  USER=sensai-runtime LOGNAME=sensai-runtime SHELL=/bin/sh \
  LANG=C.UTF-8 LC_ALL=C \
  "$OPENCODE_BIN" models
```

두 출력에 `zai`, `zai/glm-5.2`, `sensai-ollama/qwen3.5:9b`가 실제로 나타나는지 사람이 확인한다. 하나라도 없으면 여기서 `STOP`하고 아래 launch 블록을 실행하지 않는다. 이 목록 확인도 response/tool-use admission을 대신하지 않는다.

provider login과 auth도 정확히 같은 `env -i`의 `HOME`, XDG, `TMPDIR`, `OPENCODE_CONFIG_DIR` 환경에서 수행해야 한다. 실제 global auth 파일이나 다른 profile의 credential을 복사하지 않는다. 모든 미래 admission 조건과 current fingerprint가 승인된 경우에만 다음 별도 블록으로 launch한다.

```sh

env -i \
  PATH="$PATH" \
  HOME="$SENSAI_RUNTIME_HOME" \
  XDG_CONFIG_HOME="$SENSAI_RUNTIME_XDG_CONFIG" \
  XDG_DATA_HOME="$SENSAI_RUNTIME_XDG_DATA" \
  XDG_CACHE_HOME="$SENSAI_RUNTIME_XDG_CACHE" \
  XDG_STATE_HOME="$SENSAI_RUNTIME_XDG_STATE" \
  TMPDIR="$SENSAI_RUNTIME_TMP/" \
  OPENCODE_CONFIG_DIR="$SENSAI_CONFIG" \
  USER=sensai-runtime LOGNAME=sensai-runtime SHELL=/bin/sh \
  LANG=C.UTF-8 LC_ALL=C \
  "$OPENCODE_BIN" --pure "$TARGET_REPO"
```

target merge surface가 나중에 생기거나 admission fingerprint가 달라지면 launch하지 말고 다시 `STOP`한다. 이 실행에서도 `--auto`를 추가하지 않는다.

## G. repository-side CLI로 F0 파일을 준비한다

설치 payload에는 `bin/sensai`가 없다. secret·path·merge preflight를 모두 통과한 뒤 source checkout의 repository-side CLI로만 결정적 F0 상태를 초기화할 수 있다.

```sh
SENSAI_PROJECT_ROOT="$TARGET_REPO" \
  "$SENSAI_SOURCE/bin/sensai" mission init \
  "$MISSION_ID" "$TARGET_SCOPE" "$GOAL"
```

이 명령은 대상 저장소의 `docs/analysis/missions/$MISSION_ID/`에 다음 파일을 원자적으로 만든다.

- `trace.json`: schema `2.0`의 빈 canonical trace와 target provenance를 가진다.
- `progress.json`: `phase: F0`, `status: planned`, `revision: 1`, fingerprint와 다음 사람 결정을 가진다.
- `status.md`: 검증된 `progress.json`에서 파생된 읽기용 상태다.

이 repository-side CLI 경로의 init/status/checkpoint/resume, schema, hash, revision, lock, atomic rename은 filesystem 범위에서 결정적으로 검증됐다. 그러나 slash command는 target repository에서 `./bin/sensai`를 요구하고 permission도 이를 허용하지 않으므로, 이 외부 호출이 slash-command blocker를 해결하지 않는다.

### 현재 copy-ready status

```sh
SENSAI_PROJECT_ROOT="$TARGET_REPO" \
  "$SENSAI_SOURCE/bin/sensai" mission status "$MISSION_ID"
```

| exit | 의미 | 대응 |
| --- | --- | --- |
| `0` | 성공 | 출력의 revision/hash를 다음 precondition으로 기록 |
| `64` | 사용법 오류 | 인자 수와 형식을 수정 |
| `65` | 입력·설정·제품 식별 오류 | path, schema, identity, fingerprint를 확인 |
| `69` | 필수 도구 또는 transport 사용 불가 | 누락 도구나 구성 transport를 복구 |
| `73` | stage/install target이 존재하거나 생성 불가 | 기존 target을 건드리지 말고 새 absent path 사용 |
| `75` | lock·revision·hash 충돌 | 덮어쓰지 말고 status와 실제 current hash를 다시 확인 |

## H. 미래에 입학된 runtime에서 시도할 F0–F5 흐름

> 이 절은 **의도된 command 계약**을 설명한다. 현재 runtime은 앞의 네 committed blocker와 target preflight 때문에 live 실행이 입학되지 않았으며, 아래 명령의 성공을 현재 사실로 주장하지 않는다.

`order-service` 저장소의 `services/order`를 분석하고 `docs/change-requests/order-idempotency.md`를 변경요청 입력으로 사용하는 예시는 다음 순서다.

```text
/sensai/run order-service services/order 주문 생성부터 결제 요청까지의 AS-IS를 분석하고 멱등성 변경안을 설계한다
/sensai/status order-service

# 사람이 현재 fingerprint에 결합된 F0 계획을 검토하고 승인한다.
/sensai/analyze order-service services/order
/sensai/analyze-business order-service services/order docs/domain/order-policy.md
/sensai/document-asis order-service
/sensai/verify order-service asis

# 사람이 AS-IS 4종, conflict와 UNKNOWN을 검토하고 F3를 승인한다.
/sensai/change-design order-service docs/change-requests/order-idempotency.md
/sensai/deliver order-service
/sensai/verify order-service tobe
/sensai/status order-service

# 사람이 TO-BE 5종과 validator/render receipt를 검토하고 F5를 승인한다.
/sensai/status order-service
```

`/sensai/resume`은 완료되지 않은 nonterminal mission이 중단된 경우에만 사용한다. 예를 들어 F1 조사 도중 세션이 종료되고 current fingerprint와 revision이 그대로라면 새 세션에서 다음처럼 재개를 시도한다.

```text
/sensai/resume order-service
```

F5 승인 뒤 `status: completed`인 mission은 재개할 수 없다. 최종 상태는 `/sensai/status order-service`로만 확인한다.

### 비실행 참고: future repository-side checkpoint와 resume 계약

다음은 CLI 인자 구조를 설명하는 표기일 뿐 copy-ready shell 명령이 아니다. canonical progress candidate를 만드는 admitted runtime과 승인 interface가 없으므로 현재 사용자는 값을 채워 실행하지 않는다.

```text
mission checkpoint <mission-id> <candidate-progress-json> <expected-revision> <expected-progress-sha256>
mission resume <mission-id> [<expected-revision> <expected-progress-sha256>]
```

명령 소유권은 고정이다.

| 단계 | 명령 | 결과와 hard gate |
| --- | --- | --- |
| F0 | `/sensai/run` | scope, goal, dependency, todo draft 후 사람 승인 대기 |
| F1 | `/sensai/analyze` | 기술 사실과 일곱 convention category |
| F2 | `/sensai/analyze-business` | 비즈니스 사실 여섯 분류와 glossary |
| F3 | `/sensai/document-asis` | AS-IS 4종과 검증 후 사람 승인 대기 |
| F4 | `/sensai/change-design` | `REQ-EXT-*`, `DESIGN-*`, 양방향 bindings; violation은 사람 verdict까지 차단 |
| F5 | `/sensai/deliver`, `/sensai/verify` | TO-BE 5종과 검증 후 사람 최종 승인 대기 |
| 연속성 | `/sensai/status`, `/sensai/resume` | 검증된 상태 표시와 CAS 기반 재개 |

F1과 F2의 조사 lane은 나눌 수 있어도 canonical `trace.json` merge는 lead가 직렬로 수행한다. F0, F3, F5는 hard human gate다. 모델은 승인 verdict를 추정하거나 생성할 수 없다.

### 승인 영수증

committed `/sensai/run` 계약은 F0/F3/F5마다 `docs/analysis/missions/<mission-id>/approvals/<gate>-approval.json`과 현재 fingerprint에 결합된 사람 판정을 요구한다. `progress.schema.json`의 `approvals[]` 항목에는 `gate`, `verdict`, `reason`, `actor_role`, `source`, `receipt_path`, `receipt_sha256`, `recorded_at`가 정의돼 있다.

그러나 commit `9306a49`에는 approval receipt 파일을 생성하는 canonical CLI command, TUI form, question-to-receipt interface 또는 admitted human writer가 없다. `mission init`, `checkpoint`, `status`, `resume`은 approval 생성 명령이 아니며, progress schema는 receipt 파일 자체의 닫힌 JSON schema를 제공하지 않는다. 따라서 위 필드 목록을 receipt 파일의 exact schema로 오해하면 안 된다.

현재 대응은 다음과 같다.

- F0 계획을 읽고 검토할 수는 있지만 receipt 생성 지점에서 `STOP_AT_F0_GATE`한다.
- 사용자가 JSON을 손으로 조립하거나 모델에게 생성시키지 않는다.
- 임의 script, `jq` snippet, editor macro를 canonical writer로 발명하지 않는다.
- future interface는 human intent 수집, current trace/input fingerprint binding, receipt file schema, atomic write, receipt SHA-256과 progress transition을 함께 검증해야 한다.
- 그 interface와 adversarial test가 committed source에 들어오기 전에는 F0/F3/F5 승인 또는 완료를 주장하지 않는다.

## I. 미션 산출물을 읽는 법

### canonical tree

초기 CLI는 세 파일만 만들고, 입학된 F0–F5 runtime은 검증된 단계에 따라 나머지를 추가하는 계약이다. 아래 `approvals/`는 intended topology이며 현재 canonical writer가 구현됐다는 뜻이 아니다.

```text
docs/analysis/missions/order-service/
├── trace.json
├── progress.json
├── status.md
├── glossary.json
├── glossary.ko.md
├── approvals/
│   ├── F0-approval.json
│   ├── F3-approval.json
│   └── F5-approval.json
├── asis/
│   ├── ui.md
│   ├── sequence.mmd
│   ├── dataflow.mmd
│   └── story.md
├── tobe/
│   ├── ui.md
│   ├── sequence.mmd
│   ├── dataflow.mmd
│   ├── story.md
│   └── test.md
├── artifacts/
└── receipts/
```

진실 우선순위는 다음과 같다.

```text
validated trace.json > validated progress.json > derived status.md > session todo
```

하위 뷰가 상위 문서와 다르면 상위 문서를 검증하고 하위 뷰를 다시 파생한다. `status.md`나 세션 todo의 문장을 `trace.json`에 역으로 덮어쓰지 않는다.

모든 확정 사실과 투영 요소에는 stable ID, 실제 source의 `path:line`, 하나 이상의 `evidence_ids`가 있어야 한다. `path:line`은 존재하는 파일의 실제 줄이어야 하며, 이름이 비슷하다는 이유만으로 join을 만들지 않는다.

| 상태 | 뜻 | 기록 방법 |
| --- | --- | --- |
| `UNKNOWN` | 필요한 사실을 근거로 확정할 수 없음 | 빈칸을 추정하지 말고 unknown 항목으로 보존 |
| `unresolved` | 동적 경로나 연결을 정적으로 결정할 수 없음 | 후보와 차단 이유를 남김 |
| `ambiguous` | 둘 이상의 후보 중 하나를 고를 근거가 없음 | 모든 후보를 보존하고 임의 선택 금지 |
| `many_to_many` | 다대다 관계라 exact 단일 join이 아님 | 관계 형태를 그대로 기록 |
| `conflict` | 근거끼리 서로 충돌함 | 충돌 근거를 모두 연결하고 사람 결정을 요청 |
| `UNSUPPORTED` | 현재 도구·스택 계약으로 지원되지 않음 | `UNSUPPORTED-*` 항목과 근거를 남기고 성공으로 축약하지 않음 |

AS-IS는 `ui.md`, `sequence.mmd`, `dataflow.mmd`, `story.md` 네 출력이다. TO-BE는 같은 네 종류에 `test.md`를 더한 다섯 출력이다. `DATAFLOW`는 convention category가 아니라 provenance 검증 대상 deliverable이다.

## J. 처음 보는 사용자를 위한 관찰과 다음 행동

### `doctor models`에서 `UNVERIFIED`가 보인다

**보이는 것**

```text
모델 alias=zai/glm-5.2 admission=UNVERIFIED reason=MODEL_ADMISSION_UNVERIFIED
```

**다음 행동**: 오류를 숨기거나 `VERIFIED`로 손수 바꾸지 않는다. config discovery는 끝났지만 live 입학은 안 된 정상적인 현재 상태다. provider/model 목록을 확인하고, 승인된 admission 절차가 생길 때까지 모델 분석을 시작하지 않는다.

### stage가 `package.target_exists`로 끝난다

**보이는 것**: exit `73`과 기존 target 경로가 출력된다.

**다음 행동**: 기존 디렉터리를 지우거나 merge하지 않는다. 새 이름의 absent absolute target을 지정한다. 이 거부는 데이터 보존을 위한 정상 동작이다.

### `mission init` 뒤 F0만 보인다

**보이는 것**: `trace.json`, `progress.json`, `status.md`가 생기고 `phase: F0`, `revision: 1`이다.

**다음 행동**: 초기화 성공일 뿐 분석 완료가 아니다. repository-side `mission status`로 fingerprint를 확인하고, committed baseline에서는 live blocker와 approval interface 부재 때문에 F1 진입 전에 멈춘다.

### `mission status`가 precondition 오류로 끝난다

**보이는 것**: `progress.resume.precondition_trace` 또는 `progress.resume.precondition_inputs`와 nonzero exit가 출력된다.

**다음 행동**: 오래된 `status.md`나 모델 요약을 대신 보여주지 않는다. `trace.json`, target 입력과 `progress.json`의 저장 fingerprint가 왜 달라졌는지 사람이 확인하고, 정규 파일을 추정값으로 덮어쓰지 않는다.

### `resume`이 exit `75`로 끝난다

**보이는 것**: `stale_hash`, `stale_revision` 또는 `progress.resume.concurrent` 이유가 보인다.

**다음 행동**: 자동 재시도나 lock 삭제를 하지 않는다. 새 `mission status`, 실제 revision과 progress SHA-256을 읽고 다른 writer가 끝났는지 확인한다.

## K. 문제 해결과 복구

| 증상 | 흔한 원인 | 안전한 확인 | 복구 또는 중단 |
| --- | --- | --- | --- |
| `package.target_not_absolute` | 상대 설치 경로 | 변수 값이 `/`로 시작하는지 확인 | 새 absent absolute path 사용 |
| `package.target_exists`, exit `73` | 기존 target 사용 | `test -e`, `test -L` | merge·overwrite하지 말고 새 target 사용 |
| `package.parent_invalid` | parent 부재, symlink, traversal | `pwd -P`, component별 symlink 확인 | 물리 parent를 먼저 만들고 새 child 선택 |
| `tool.unavailable` | CLI 누락 | `command -v`와 `doctor tools` | 올바른 제품 설치 후 재검사 |
| `tool.identity_mismatch` | Python yq 등 동명 도구 | 각 `--version` 첫 줄 | Mike Farah yq, ast-grep `sg` 등 정확한 제품으로 교체 |
| provider/model ID 없음 | provider 미설정 또는 모델 미제공 | F절의 isolated `env -i` provider/model 확인 블록 | secret을 노출하지 말고 provider 준비; live 분석 중단 |
| 예상 외 agent/command/skill | inherited config merge | disposable HOME/XDG/CWD에서 다시 debug | sentinel이 사라질 때까지 semantic load 실패 처리 |
| target에 `opencode.json`·`.opencode/`·instruction 파일이 있음 | target-specific merge policy 부재 | 다섯 merge surface의 존재만 확인 | 원본 보존, 자동 merge 금지, live 분석 중단 |
| secret-like pathname 발견 | CLI hash가 file content를 읽기 전 차단 필요 | content가 아닌 pathname만 검사 | 파일을 열지 말고 scope 제외 또는 안전한 입력을 사람이 결정 |
| debug 뒤 `.gitignore`가 생김 | OpenCode 초기화 | 변경 위치가 disposable config인지 확인 | 알려진 disposable 변화로 기록; source/global이면 실패 |
| `stale_hash`·`stale_revision` | 입력·progress가 기준 뒤 변경 | status, revision, SHA-256 재확인 | 새 기준으로 사람이 판단; 덮어쓰기 금지 |
| `progress.resume.concurrent` | 같은 mission의 다른 writer 또는 남아 있는 lock | reason과 lock 존재만 확인 | 다른 writer 종료를 확인할 때까지 대기; lock 탈취·수동 삭제 금지 |
| schema 또는 jq validator 실패 | 손상·필수 필드 누락·전이 위반 | 실제 exit와 reason code 확인 | 후보를 canonical로 쓰지 말고 마지막 valid revision에서 복구 |
| dangling `evidence_ids` | 원장에 없는 근거 참조 | ID exact-set과 trace 역참조 | 근거를 실제로 수집하거나 `UNKNOWN` 보존 |
| 잘못된 `path:line` | 이동된 파일, 발명한 줄 번호 | 현재 target에서 경로와 줄 재확인 | fingerprint를 갱신하고 stale receipt 폐기 |
| permission prompt/deny | 정책상 허용되지 않은 행동 | canonical `permission`과 command 비교 | 권한 우회 금지; source 계약 변경·재검증 전 중단 |
| F3–F5에서 skill deny | 다섯 필수 skill 미허용 | `output/opencode.json`의 `permission.skill` 확인 | 현재 live 분석 중단; 임의 allow 금지 |
| `/sensai/run/status/resume`에서 CLI 불가 | 36-leaf 설치에 `bin/sensai`가 없고 command는 `./bin/sensai` 요구 | committed manifest, command, permission 비교 | repository-side CLI를 별도 호출해도 slash blocker는 남았다고 기록 |
| 대상 코드 근거가 수집되지 않음 | target-read와 mission-root-only skill 문구 충돌 | committed command와 skill의 더 제한적인 문구 비교 | source 계약이 정합해질 때까지 분석 중단 |
| F0 승인에서 진행할 수 없음 | canonical receipt 생성 interface 부재 | command 요구사항과 CLI subcommand 목록 비교 | 수기·모델 생성 금지, `STOP_AT_F0_GATE` |
| Windows에서 성공 여부 불명 | final user receipt 없음 | committed release 상태 확인 | `WINDOWS_RECEIPT_PENDING` 유지; 성공 주장 금지 |

손상된 `progress.json`을 추정값으로 고치지 않는다. 마지막으로 검증된 `trace.json`, current target hash, Git HEAD를 보존하고 사람에게 새 기준선 결정을 요청한다. 다른 process가 만든 mission lock을 훔치거나 수동 삭제하지 않고, 자신이 시작한 정상 CLI의 cleanup만 허용한다.

## L. 격리 설치를 안전하게 퇴역한다

먼저 사용 중인 OpenCode process가 config나 runtime state를 참조하지 않는지 확인한다. config payload와 persistent runtime `HOME`/XDG/data/cache/state/temp는 서로 다른 수명과 민감도를 가지므로 각각 퇴역해야 한다. config rename만으로 auth·database·cache가 퇴역했다고 간주하지 않는다.

다음 검사는 절대 경로의 모든 component가 물리 디렉터리인지 확인하고 `/`, trailing slash, `.`·`..`, 중복 slash와 symlink를 거부한다.

```sh
retire_root_is_safe() {
  test "$#" -eq 1 || return 1
  RETIRE_ROOT=$1
  case "$RETIRE_ROOT" in
    /*) ;;
    *) return 1 ;;
  esac
  case "$RETIRE_ROOT" in
    /|*/|*//*|*/./*|*/../*|*/.|*/..) return 1 ;;
  esac
  RETIRE_CURRENT=/
  RETIRE_RELATIVE=${RETIRE_ROOT#/}
  RETIRE_OLD_IFS=$IFS
  IFS=/
  set -f
  set -- $RETIRE_RELATIVE
  set +f
  IFS=$RETIRE_OLD_IFS
  for RETIRE_COMPONENT do
    case "$RETIRE_COMPONENT" in
      ''|.|..) return 1 ;;
    esac
    if test "$RETIRE_CURRENT" = /; then
      RETIRE_CURRENT=/$RETIRE_COMPONENT
    else
      RETIRE_CURRENT=$RETIRE_CURRENT/$RETIRE_COMPONENT
    fi
    test ! -L "$RETIRE_CURRENT" || return 1
  done
  test -d "$RETIRE_ROOT" || return 1
  return 0
}

retire_normalized_absolute_nonroot_path() {
  test "$#" -eq 1 || return 1
  case "$1" in
    /*) ;;
    *) return 1 ;;
  esac
  case "$1" in
    /|*/|*//*|*/./*|*/../*|*/.|*/..) return 1 ;;
  esac
  return 0
}

retire_physical_directory_identity() {
  test "$#" -eq 1 || return 1
  RETIRE_PHYSICAL_INPUT=$1
  retire_normalized_absolute_nonroot_path \
    "$RETIRE_PHYSICAL_INPUT" || return 1
  if test -e "$RETIRE_PHYSICAL_INPUT" || test -L "$RETIRE_PHYSICAL_INPUT"; then
    test -d "$RETIRE_PHYSICAL_INPUT" || return 1
    (CDPATH= cd -- "$RETIRE_PHYSICAL_INPUT" && pwd -P) || return 1
    return 0
  fi
  RETIRE_PHYSICAL_PARENT=${RETIRE_PHYSICAL_INPUT%/*}
  RETIRE_PHYSICAL_LEAF=${RETIRE_PHYSICAL_INPUT##*/}
  test -n "$RETIRE_PHYSICAL_LEAF" || return 1
  test -n "$RETIRE_PHYSICAL_PARENT" || RETIRE_PHYSICAL_PARENT=/
  test -d "$RETIRE_PHYSICAL_PARENT" || return 1
  RETIRE_PHYSICAL_PARENT_ID="$(
    CDPATH= cd -- "$RETIRE_PHYSICAL_PARENT" && pwd -P
  )" || return 1
  if test "$RETIRE_PHYSICAL_PARENT_ID" = /; then
    printf '/%s\n' "$RETIRE_PHYSICAL_LEAF"
  else
    printf '%s/%s\n' \
      "$RETIRE_PHYSICAL_PARENT_ID" "$RETIRE_PHYSICAL_LEAF"
  fi
}

retire_physical_existing_directory() {
  test "$#" -eq 1 || return 1
  test -d "$1" || return 1
  retire_physical_directory_identity "$1" || return 1
}

retire_roots_are_disjoint() {
  test "$#" -eq 2 || return 1
  case "$1" in
    "$2"|"$2"/*) return 1 ;;
  esac
  case "$2" in
    "$1"|"$1"/*) return 1 ;;
  esac
  return 0
}

runtime_root_is_owned_and_expected() {
  test "$#" -eq 8 || return 1
  OWNED_ROOT=$1
  OWNED_MARKER=$2
  OWNED_HOME=$3
  OWNED_XDG_CONFIG=$4
  OWNED_XDG_DATA=$5
  OWNED_XDG_CACHE=$6
  OWNED_XDG_STATE=$7
  OWNED_TMP=$8
  OWNED_MARKER_EXPECTED='wonder-sensai isolated runtime root v1'

  test "$OWNED_MARKER" = \
    "$OWNED_ROOT/.wonder-sensai-isolated-runtime" || return 1
  test "$OWNED_HOME" = "$OWNED_ROOT/home" || return 1
  test "$OWNED_XDG_CONFIG" = "$OWNED_ROOT/xdg-config" || return 1
  test "$OWNED_XDG_DATA" = "$OWNED_ROOT/xdg-data" || return 1
  test "$OWNED_XDG_CACHE" = "$OWNED_ROOT/xdg-cache" || return 1
  test "$OWNED_XDG_STATE" = "$OWNED_ROOT/xdg-state" || return 1
  test "$OWNED_TMP" = "$OWNED_ROOT/tmp" || return 1

  test -d "$OWNED_ROOT" || return 1
  test ! -L "$OWNED_ROOT" || return 1
  test -f "$OWNED_MARKER" || return 1
  test ! -L "$OWNED_MARKER" || return 1
  OWNED_MARKER_ACTUAL="$(cat "$OWNED_MARKER")" || return 1
  test "$OWNED_MARKER_ACTUAL" = "$OWNED_MARKER_EXPECTED" || return 1
  OWNED_MARKER_BYTES="$(wc -c <"$OWNED_MARKER" | tr -d ' ')" || return 1
  OWNED_EXPECTED_BYTES="$(
    printf '%s\n' "$OWNED_MARKER_EXPECTED" | wc -c | tr -d ' '
  )" || return 1
  test "$OWNED_MARKER_BYTES" = "$OWNED_EXPECTED_BYTES" || return 1

  for OWNED_CHILD in \
    "$OWNED_HOME" "$OWNED_XDG_CONFIG" "$OWNED_XDG_DATA" \
    "$OWNED_XDG_CACHE" "$OWNED_XDG_STATE" "$OWNED_TMP"; do
    test -d "$OWNED_CHILD" || return 1
    test ! -L "$OWNED_CHILD" || return 1
    OWNED_CHILD_PHYSICAL="$(
      retire_physical_existing_directory "$OWNED_CHILD"
    )" || return 1
    test "$OWNED_CHILD_PHYSICAL" = "$OWNED_CHILD" || return 1
  done
  return 0
}
```

### persistent runtime state root

future launch 예시의 runtime root를 실제로 만들었다면 별도로 퇴역한다. config payload도 함께 퇴역할 때는 이 runtime 검사를 먼저 완료한 뒤 아래의 분리된 config 절차를 실행한다.

```sh
RETIRE_TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)" || exit 73
retire_root_is_safe "$SENSAI_RUNTIME_ROOT" || exit 73
runtime_root_is_owned_and_expected \
  "$SENSAI_RUNTIME_ROOT" "$SENSAI_RUNTIME_MARKER" \
  "$SENSAI_RUNTIME_HOME" "$SENSAI_RUNTIME_XDG_CONFIG" \
  "$SENSAI_RUNTIME_XDG_DATA" "$SENSAI_RUNTIME_XDG_CACHE" \
  "$SENSAI_RUNTIME_XDG_STATE" "$SENSAI_RUNTIME_TMP" || exit 73

RETIRE_RUNTIME_PHYSICAL="$(
  retire_physical_existing_directory "$SENSAI_RUNTIME_ROOT"
)" || exit 73
RETIRE_SOURCE_PHYSICAL="$(
  retire_physical_existing_directory "$SENSAI_SOURCE"
)" || exit 73
RETIRE_CONFIG_PHYSICAL="$(
  retire_physical_existing_directory "$SENSAI_CONFIG"
)" || exit 73
RETIRE_TARGET_PHYSICAL="$(
  retire_physical_existing_directory "$TARGET_REPO"
)" || exit 73
RETIRE_ACTUAL_HOME_PHYSICAL="$(
  retire_physical_existing_directory "${HOME:?}"
)" || exit 73
if test -n "${OPENCODE_CONFIG_DIR:-}"; then
  RETIRE_ACTUAL_OPENCODE_CONFIG=$OPENCODE_CONFIG_DIR
else
  RETIRE_ACTUAL_XDG_CONFIG=${XDG_CONFIG_HOME:-$RETIRE_ACTUAL_HOME_PHYSICAL/.config}
  RETIRE_ACTUAL_OPENCODE_CONFIG=$RETIRE_ACTUAL_XDG_CONFIG/opencode
fi
RETIRE_ACTUAL_OPENCODE_CONFIG_PHYSICAL="$(
  retire_physical_directory_identity "$RETIRE_ACTUAL_OPENCODE_CONFIG"
)" || exit 73

for RETIRE_PROTECTED_PHYSICAL in \
  "$RETIRE_SOURCE_PHYSICAL" "$RETIRE_CONFIG_PHYSICAL" \
  "$RETIRE_TARGET_PHYSICAL" "$RETIRE_ACTUAL_HOME_PHYSICAL" \
  "$RETIRE_ACTUAL_OPENCODE_CONFIG_PHYSICAL"; do
  retire_roots_are_disjoint \
    "$RETIRE_RUNTIME_PHYSICAL" "$RETIRE_PROTECTED_PHYSICAL" || exit 73
done
SENSAI_RUNTIME_RETIRED="${SENSAI_RUNTIME_ROOT}.retired.${RETIRE_TIMESTAMP}"
test ! -e "$SENSAI_RUNTIME_RETIRED" || exit 73
test ! -L "$SENSAI_RUNTIME_RETIRED" || exit 73
mv "$SENSAI_RUNTIME_ROOT" "$SENSAI_RUNTIME_RETIRED" || exit 73
printf '%s\n' "퇴역된 runtime state root: $SENSAI_RUNTIME_RETIRED"
```

marker, expected child, physical protected root 중 하나라도 다르면 rename 전에 `STOP`한다. marker 이름이나 내용이 맞더라도 symlink인 경우 소유 증거로 인정하지 않는다.

### config payload root

config payload는 runtime state와 별도 root이므로 별도 명령으로 퇴역한다.

```sh
(
test -n "${SENSAI_CONFIG:-}" || exit 73
test -n "${SENSAI_CONFIG_PARENT:-}" || exit 73
test -n "${SENSAI_SOURCE:-}" || exit 73
test -n "${TARGET_REPO:-}" || exit 73
test -n "${HOME:-}" || exit 73
set -u

config_retire_normalized_path() {
  test "$#" -eq 1 || return 1
  case "$1" in
    /*) ;;
    *) return 1 ;;
  esac
  case "$1" in
    /|*/|*//*|*/./*|*/../*|*/.|*/..) return 1 ;;
  esac
  return 0
}

config_retire_physical_identity() {
  test "$#" -eq 1 || return 1
  CONFIG_RETIRE_INPUT=$1
  config_retire_normalized_path "$CONFIG_RETIRE_INPUT" || return 1
  if test -e "$CONFIG_RETIRE_INPUT" || test -L "$CONFIG_RETIRE_INPUT"; then
    test -d "$CONFIG_RETIRE_INPUT" || return 1
    (CDPATH= cd -- "$CONFIG_RETIRE_INPUT" && pwd -P) || return 1
    return 0
  fi
  CONFIG_RETIRE_PARENT=${CONFIG_RETIRE_INPUT%/*}
  CONFIG_RETIRE_LEAF=${CONFIG_RETIRE_INPUT##*/}
  test -n "$CONFIG_RETIRE_LEAF" || return 1
  test -n "$CONFIG_RETIRE_PARENT" || CONFIG_RETIRE_PARENT=/
  test -d "$CONFIG_RETIRE_PARENT" || return 1
  CONFIG_RETIRE_PARENT_PHYSICAL="$(
    CDPATH= cd -- "$CONFIG_RETIRE_PARENT" && pwd -P
  )" || return 1
  if test "$CONFIG_RETIRE_PARENT_PHYSICAL" = /; then
    printf '/%s\n' "$CONFIG_RETIRE_LEAF"
  else
    printf '%s/%s\n' \
      "$CONFIG_RETIRE_PARENT_PHYSICAL" "$CONFIG_RETIRE_LEAF"
  fi
}

config_retire_existing_directory() {
  test "$#" -eq 1 || return 1
  test -d "$1" || return 1
  config_retire_physical_identity "$1" || return 1
}

config_retire_roots_are_disjoint() {
  test "$#" -eq 2 || return 1
  case "$1" in
    "$2"|"$2"/*) return 1 ;;
  esac
  case "$2" in
    "$1"|"$1"/*) return 1 ;;
  esac
  return 0
}

config_retire_root_is_safe() {
  test "$#" -eq 1 || return 1
  CONFIG_RETIRE_ROOT=$1
  case "$CONFIG_RETIRE_ROOT" in
    /*) ;;
    *) return 1 ;;
  esac
  case "$CONFIG_RETIRE_ROOT" in
    /|*/|*//*|*/./*|*/../*|*/.|*/..) return 1 ;;
  esac
  CONFIG_RETIRE_CURRENT=/
  CONFIG_RETIRE_RELATIVE=${CONFIG_RETIRE_ROOT#/}
  CONFIG_RETIRE_OLD_IFS=$IFS
  IFS=/
  set -f
  set -- $CONFIG_RETIRE_RELATIVE
  set +f
  IFS=$CONFIG_RETIRE_OLD_IFS
  for CONFIG_RETIRE_COMPONENT do
    case "$CONFIG_RETIRE_COMPONENT" in
      ''|.|..) return 1 ;;
    esac
    if test "$CONFIG_RETIRE_CURRENT" = /; then
      CONFIG_RETIRE_CURRENT=/$CONFIG_RETIRE_COMPONENT
    else
      CONFIG_RETIRE_CURRENT=$CONFIG_RETIRE_CURRENT/$CONFIG_RETIRE_COMPONENT
    fi
    test ! -L "$CONFIG_RETIRE_CURRENT" || return 1
  done
  test -d "$CONFIG_RETIRE_ROOT" || return 1
  return 0
}

CONFIG_RETIRE_PHYSICAL="$(
  config_retire_existing_directory "$SENSAI_CONFIG"
)" || exit 73
CONFIG_RETIRE_PARENT_PHYSICAL="$(
  config_retire_existing_directory "$SENSAI_CONFIG_PARENT"
)" || exit 73
case "$CONFIG_RETIRE_PHYSICAL" in
  "$CONFIG_RETIRE_PARENT_PHYSICAL"/*) ;;
  *) exit 73 ;;
esac
CONFIG_RETIRE_SOURCE_PHYSICAL="$(
  config_retire_existing_directory "$SENSAI_SOURCE"
)" || exit 73
CONFIG_RETIRE_TARGET_PHYSICAL="$(
  config_retire_existing_directory "$TARGET_REPO"
)" || exit 73
CONFIG_RETIRE_HOME_PHYSICAL="$(
  config_retire_existing_directory "$HOME"
)" || exit 73
if test -n "${OPENCODE_CONFIG_DIR:-}"; then
  CONFIG_RETIRE_ACTUAL_GLOBAL=$OPENCODE_CONFIG_DIR
else
  CONFIG_RETIRE_ACTUAL_XDG=${XDG_CONFIG_HOME:-$CONFIG_RETIRE_HOME_PHYSICAL/.config}
  CONFIG_RETIRE_ACTUAL_GLOBAL=$CONFIG_RETIRE_ACTUAL_XDG/opencode
fi
CONFIG_RETIRE_ACTUAL_GLOBAL_PHYSICAL="$(
  config_retire_physical_identity "$CONFIG_RETIRE_ACTUAL_GLOBAL"
)" || exit 73

for CONFIG_RETIRE_PROTECTED in \
  "$CONFIG_RETIRE_SOURCE_PHYSICAL" "$CONFIG_RETIRE_TARGET_PHYSICAL" \
  "$CONFIG_RETIRE_HOME_PHYSICAL" \
  "$CONFIG_RETIRE_ACTUAL_GLOBAL_PHYSICAL"; do
  config_retire_roots_are_disjoint \
    "$CONFIG_RETIRE_PHYSICAL" "$CONFIG_RETIRE_PROTECTED" || exit 73
done

RETIRE_TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)" || exit 73
config_retire_root_is_safe "$SENSAI_CONFIG" || exit 73
case "$SENSAI_CONFIG" in
  "$SENSAI_CONFIG_PARENT"/*) ;;
  *) printf '%s\n' "config parent 불일치" >&2; exit 73 ;;
esac
test "$SENSAI_CONFIG" != "$SENSAI_SOURCE" || exit 73
test "$SENSAI_CONFIG" != "$TARGET_REPO" || exit 73
SENSAI_CONFIG_RETIRED="${SENSAI_CONFIG}.retired.${RETIRE_TIMESTAMP}"
test ! -e "$SENSAI_CONFIG_RETIRED" || exit 73
test ! -L "$SENSAI_CONFIG_RETIRED" || exit 73
mv "$SENSAI_CONFIG" "$SENSAI_CONFIG_RETIRED" || exit 73
printf '%s\n' "퇴역된 config root: $SENSAI_CONFIG_RETIRED"
)
```

XDG나 `HOME`을 runtime root 밖에 따로 배치했다면 각 물리 root에 같은 안전 검사를 적용해 하나씩 rename해야 한다. 이 rename은 isolated 자산의 퇴역이며 OpenCode 제품 자체를 제거하는 `opencode uninstall`과 다르다. 보존 기간과 소유자를 확인한 뒤에도 자동 재귀 삭제를 안내하지 않는다. 특히 `~`, `/`, workspace root, source, target에 broad `rm -rf`를 사용하지 않는다.

## M. 하지 말아야 할 일

- curated instruction을 설치한 뒤 `/init`으로 덮어쓰거나 재생성하지 않는다.
- 사람 hard gate를 무시하는 `--auto` 또는 자동 승인 흐름을 사용하지 않는다.
- existing config에 merge, overwrite, backup install을 시도하지 않는다.
- source tree, 대상 저장소, 실제 global config/HOME에서 `opencode debug`를 실행하지 않는다.
- credential, secret, `.env`, 실제 auth config, raw model transcript를 복사·저장하지 않는다.
- stable ID, `path:line`, `evidence_ids`, approval receipt를 모델이 발명하게 하지 않는다.
- permission deny를 shell 우회, pipe, redirect, command substitution으로 회피하지 않는다.
- semantic load 성공을 live response/tool-use/TUI/delegation 성공으로 확대하지 않는다.
- macOS 결정적 결과를 Windows 또는 cross-platform 성공으로 주장하지 않는다.
- 기준 commit `9306a49`에서 실제 F0–F5 대상 분석이 성공했다고 기록하지 않는다.

## N. 근거 문서와 버전 주의

### 이 저장소의 canonical·상위 계약

- [README](../README.md): 현재 구현 상태, exact-set, 검증 selector와 상태 축
- [runtime contract](harness/runtime-contract.md): source/load, 격리, mission, permission 계약
- [verification contract](harness/verification-contract.md): 검증 축과 false-success 방지
- [release contract](harness/release-contract.md): local/model/Windows 상태 분리와 퇴출
- [implementation status](harness/implementation-status.md): 현재 workspace의 파생 상태 요약
- [제품 계약](PROD.md): 제품 경계, hard gate와 금지선
- [R4 mapping](r4-mapping.md): agent·command·skill·도구 역할 매핑

이 매뉴얼의 현재 상태와 명령은 commit `9306a49a36c110498e52bd212a3bf0c1f7eb8489`의 파일에 결합돼 있다. working tree의 uncommitted runtime 변경은 근거가 아니다. 일부 상위·상태 문서는 같은 commit 안에서도 과거 구현 단계를 서술할 수 있으므로, 충돌할 때는 해당 commit의 executable config, schema, CLI, validator와 README를 직접 대조하고 모순을 숨기지 않는다.

### 설치 runtime source

- [runtime AGENTS](../output/AGENTS.md)
- [OpenCode config](../output/opencode.json)
- command: [run](../output/commands/sensai/run.md), [analyze](../output/commands/sensai/analyze.md), [analyze-business](../output/commands/sensai/analyze-business.md), [document-asis](../output/commands/sensai/document-asis.md), [change-design](../output/commands/sensai/change-design.md), [deliver](../output/commands/sensai/deliver.md), [verify](../output/commands/sensai/verify.md), [status](../output/commands/sensai/status.md), [resume](../output/commands/sensai/resume.md)
- schema: [trace](../output/schemas/trace.schema.json), [progress](../output/schemas/progress.schema.json)

### OpenCode 공식 문서

- [Config](https://opencode.ai/docs/config/)
- [Rules](https://opencode.ai/docs/rules/)
- [CLI](https://opencode.ai/docs/cli/)
- [TUI](https://opencode.ai/docs/tui/)
- [Providers](https://opencode.ai/docs/providers/)
- [Models](https://opencode.ai/docs/models/)
- [Agents](https://opencode.ai/docs/agents/)

공식 웹 문서는 rolling 문서이고 development source도 바뀔 수 있다. 이 안내서의 명령·schema·permission 해석은 현재 저장소가 고정한 OpenCode `1.18.3`에 한정한다. 최신 공식 문서의 예제를 그대로 가져오기 전에 `1.18.3` CLI와 disposable 환경에서 다시 확인하고, 버전 차이를 현재 성공으로 추정하지 않는다.
