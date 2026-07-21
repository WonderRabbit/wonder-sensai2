# bin artifact 전달 PRD

## 문제

Go CLI source와 platform별 실행 파일의 역할이 분리돼 있지만, source checkout에서 바로 설치·실행할 artifact를 Git으로 전달하는 규칙이 없으면 사용자는 Go toolchain을 별도로 준비해야 한다. ignored `dist/`를 최종 전달 위치로 취급하면 source mode의 exact `bin/` 경로와 release checkout이 어긋난다. 따라서 재현 가능한 source authority는 유지하면서 macOS와 Windows 실행 파일을 tracked `bin/` 경로에 함께 commit하는 절차가 필요하다.

## 목표

- macOS `bin/sensai`와 Windows `bin/sensai.exe`를 source checkout에 포함하는 tracked 전달 artifact로 고정한다.
- 두 artifact를 같은 source revision, exact Go `1.26.5`, `CGO_ENABLED=0`, `-trimpath`로 재현한다.
- source와 artifact의 권위, 검증, commit·push, 실패 시 rollback 경계를 명확히 한다.
- Windows 네이티브 영수증 전까지 `WINDOWS_COMPATIBILITY_UNVERIFIED`를 유지한다.

## 비목표

- Go source, public command, exit, `reason`, installer 또는 payload 동작을 바꾸지 않는다.
- `output/`, `manifest.txt`, fixtures, schema, recipe, agent, command, skill을 binary에 합치거나 변경하지 않는다.
- archive, tag, GitHub Release, registry, package manager, CI, GoReleaser, 자동 update·uninstall을 추가하지 않는다.
- `dist/`를 canonical release root나 최종 전달 위치로 승격하지 않는다.
- Windows 네이티브 실행 없이 Windows 또는 cross-platform PASS를 주장하지 않는다.

## tracked 전달 경로

tracked artifact exact-set은 다음 두 파일이다.

| GOOS | GOARCH | tracked path | 용도 |
| --- | --- | --- | --- |
| `darwin` | `arm64` | `bin/sensai` | macOS source mode와 Unix installer source |
| `windows` | `amd64` | `bin/sensai.exe` | Windows direct source mode와 installer source |

두 파일은 `output/`의 36개 managed config leaf와 root `manifest.txt`에 포함하지 않는다. `dist/`가 필요하면 ignored·noncanonical local scratch로만 사용하며 commit, release 후보, 최종 전달의 기준으로 삼지 않는다.

## source와 artifact 권위

`cmd/sensai/`와 `go.mod`가 CLI 동작, review와 재현의 semantic authority다. `bin/sensai`와 `bin/sensai.exe`는 그 source에서 생성한 tracked 전달 artifact이며 직접 patch하거나 서로 다른 source revision에서 만들지 않는다. source가 바뀌어 artifact bytes에 영향을 줄 수 있으면 두 target을 함께 재생성하고, artifact만 달라졌다면 exact toolchain·source revision·명령을 evidence로 설명할 수 있어야 한다.

artifact bytes는 source 의미를 override하지 않지만 release checkout의 실행 가능성에는 필수다. 따라서 source와 artifact가 불일치하면 artifact를 전달하지 않고 source에서 다시 build한다.

## exact build matrix

build prerequisite는 exact Go `1.26.5`다. 자동 toolchain download나 다른 patch version으로 대체하지 않는다.

```sh
SENSAI_GO="${SENSAI_GO:-go}"
test "$("$SENSAI_GO" version | awk '{print $3}')" = go1.26.5
mkdir -p bin
env CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 "$SENSAI_GO" build -trimpath -o bin/sensai ./cmd/sensai
env CGO_ENABLED=0 GOOS=windows GOARCH=amd64 "$SENSAI_GO" build -trimpath -o bin/sensai.exe ./cmd/sensai
```

빌드 입력은 같은 checked-out source revision이어야 한다. macOS 파일에는 `.exe` suffix를 붙이지 않고 Windows 파일에는 반드시 `.exe` suffix를 둔다.

## commit과 push 계획

1. 작업 시작 전에 branch, upstream, dirty worktree를 확인하고 다른 작업자의 변경을 보존한다.
2. exact Go `1.26.5`를 확인한 뒤 같은 source revision에서 두 tracked path를 연속 build한다.
3. 아래 최소 검증을 한 번 수행하고 invocation, exit, SHA-256, observable, cleanup을 evidence에 기록한다.
4. `git diff -- bin/sensai bin/sensai.exe`와 `git status --short`로 두 artifact와 의도한 source·authority 문서만 전달 범위에 있는지 확인한다.
5. broad `git add .`를 사용하지 않고 의도한 source, `bin/sensai`, `bin/sensai.exe`, 직접 관련 문서·contract만 path-scoped stage한다.
6. `git diff --cached --stat`과 staged diff를 읽고 CLI source 변경이 있으면 source와 두 artifact를 하나의 원자적 변경으로 commit한다. source 변경 유무와 관계없이 artifact 두 target은 항상 함께 포함하며 한 target만 담은 commit은 허용하지 않는다.
7. commit tree의 두 artifact와 검증한 SHA-256을 다시 대조한 뒤 현재 branch의 명시적 upstream으로 일반 push한다. tag, force-push, release upload는 수행하지 않는다.
8. push 뒤 remote branch SHA가 local commit과 같은지 확인하고, Windows 상태는 계속 `WINDOWS_COMPATIBILITY_UNVERIFIED`로 보고한다.

## 최소 검증 예산

이 전달 변경은 새 test framework나 broad 반복 검증을 요구하지 않는다. 최종 source와 artifact 입력에서 다음을 각 한 번만 수행한다.

```sh
"$SENSAI_GO" version
"$SENSAI_GO" version -m bin/sensai
"$SENSAI_GO" version -m bin/sensai.exe
file bin/sensai bin/sensai.exe
shasum -a 256 bin/sensai bin/sensai.exe
./bin/sensai help
git diff --check
```

기대 observable은 두 파일이 non-empty regular file이고, `bin/sensai`가 Darwin arm64 executable, `bin/sensai.exe`가 PE32+ x86-64 executable이며, 두 module metadata가 현재 module/source와 exact Go `1.26.5`를 가리키는 것이다. macOS host에서는 `bin/sensai`의 direct `help`만 smoke한다. Windows artifact는 metadata와 file format까지만 확인하며 실행 성공으로 해석하지 않는다. 무관한 selector, full suite, 반복 실행은 이 artifact 전달 계획의 최소 예산 밖이다.

## Windows 증명 경계

`bin/sensai.exe`가 build되고 tracked됐다는 사실은 Windows 네이티브 호환성 영수증이 아니다. 실제 Windows에서 direct CLI의 help, doctor, stage, isolated install, mission과 link/reparse 거부를 확인하기 전 상태는 `WINDOWS_COMPATIBILITY_UNVERIFIED`다. `output/commands/`의 extension 없는 Unix binding은 그대로이므로 Windows OpenCode slash-command integration도 Scope OUT이다.

## rollback과 rebuild

build, metadata, file format, smoke, diff 또는 scope 검증이 실패하면 commit·push를 중단한다. 실패한 uncommitted `bin/sensai`와 `bin/sensai.exe`는 전달 대상으로 사용하지 않고, 원인을 source나 toolchain에서 수정한 뒤 같은 revision과 exact matrix로 두 파일을 함께 다시 build한다. 한 target만 통과한 상태를 보존해 전달하지 않는다.

이미 local commit했다면 push 전에 새 commit으로 숨기지 말고 의도한 Git 복원 절차로 source와 두 artifact를 직전 검증 상태에 함께 되돌린다. 이미 push했다면 force-push나 기존 binary overwrite를 하지 않고 후속 rollback 또는 rebuild commit으로 이력을 보존한다. 사용자 설치 위치의 기존 config나 unmanaged content는 artifact rollback 대상으로 삼지 않는다.

## 수용 조건

- `bin/sensai`와 `bin/sensai.exe`가 tracked exact-set으로 존재하고 같은 source revision에서 생성됐다.
- exact Go `1.26.5`, `CGO_ENABLED=0`, `-trimpath`, `darwin/arm64`와 `windows/amd64` matrix가 지켜졌다.
- `cmd/sensai/`와 `go.mod`의 semantic authority, tracked artifact의 전달 역할, `dist/`의 noncanonical scratch 역할이 authority 문서에서 일치한다.
- 두 artifact의 module metadata, file format, SHA-256과 macOS direct help가 최소 예산 안에서 확인됐다.
- CLI source 변경이 있으면 commit에 source와 두 artifact가 함께 포함되고, source 변경이 없더라도 두 artifact는 같은 commit에 포함된다. 의도하지 않은 file, secret, runtime state, `.omo` evidence는 포함되지 않는다.
- push 뒤 remote branch SHA가 local commit과 일치한다.
- Windows native receipt가 없으면 `WINDOWS_COMPATIBILITY_UNVERIFIED`와 slash-command Scope OUT을 유지한다.

## stop 기준

두 tracked artifact, source·authority 문서, 검증 evidence가 같은 source revision을 가리키고 path-scoped commit과 normal push가 확인되면 작업을 종료한다. exact toolchain 부재, target 하나의 build 실패, source/artifact drift, 범위 밖 변경 혼입, Windows 호환성 과장 중 하나라도 남으면 artifact 전달을 중단하고 push하지 않는다.
