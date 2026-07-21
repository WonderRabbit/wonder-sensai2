# Go CLI와 Windows 전달 PRD

## 문제

기존 POSIX shell CLI는 command·exit·`reason` 계약을 구현했지만 Windows에 단일 실행 파일로 전달할 수 없었다. 현재 저장소는 같은 계약을 Go CLI로 이식했고 macOS host 실행과 Windows cross-build가 가능하다. 다만 Windows 네이티브 host에서 직접 CLI를 실행한 영수증은 아직 없고, `output/commands/`는 extension 없는 Unix 설치 경로를 계속 가리킨다. 따라서 Go source, 두 build target, 플랫폼별 경로와 아직 증명하지 않은 OpenCode 연동 범위를 분리해야 한다.

## 목표

- 기존 public command, 한국어 stdout/stderr, exit와 `reason` 의미를 보존하는 독립 Go 실행 파일을 제공한다.
- Go 표준 라이브러리만 사용하는 module source와 정확한 빌드 전제를 고정한다.
- `darwin/arm64` host binary와 `windows/amd64` 전달 binary의 tracked 이름과 위치를 고정한다.
- Unix symlink와 Windows symlink·junction·기타 reparse point를 fail closed로 다룬다.
- config 36개와 별도 CLI의 no-replace 게시, 충돌 전 쓰기 거부, owned-state rollback을 보존한다.
- Windows의 현재 증명 범위를 direct CLI와 OpenCode slash-command 연동으로 나누어 과장된 호환성 주장을 막는다.

## 비목표

- `output/`, `manifest.txt`, fixture, schema, recipe, agent, command, skill payload를 변경하지 않는다.
- command·argument·출력·exit·`reason`을 재설계하지 않는다.
- third-party Go module, wrapper shell, Node.js/TypeScript runtime, installer framework, package manager, CI, GoReleaser를 추가하지 않는다.
- archive, tag, upload, registry publication, 자동 update·uninstall을 구현하지 않는다.
- Windows 네이티브 실행 없이 Windows 또는 cross-platform PASS를 주장하지 않는다.

## 보존하는 CLI 계약

public command는 다음과 같다.

```text
help
doctor tools
doctor models
stage <absent-absolute-target>
install
mission init <mission-id> <target-relative-path> <goal>
mission checkpoint <mission-id> <candidate-progress.json> <expected-revision> <expected-sha256>
mission status <mission-id>
mission resume <mission-id> [<expected-revision> <expected-sha256>]
```

| exit | 보존 의미 |
| --- | --- |
| `0` | 성공 |
| `64` | 사용법 오류 |
| `65` | 입력·설정·제품 식별 오류 |
| `69` | 필수 도구 또는 transport 사용 불가 |
| `73` | stage 대상 생성 불가 또는 install managed 충돌 |
| `75` | lock·revision·hash 충돌 또는 rollback cleanup 실패 |
| `130` | interrupt; 오류 문구 없이 종료 |

기존 `reason` 문자열은 호환성 식별자다. 특히 `cli.usage`, `runtime.executable_invalid`, `runtime.asset_invalid`, `tool.unavailable`, `doctor.tools_failed`, `model.alias_mismatch`, `model.transport_unavailable`, `package.target_exists`, `package.managed_conflict`, `package.locked`, `package.rollback_failed`, `mission.id_invalid`, `mission.project_root_invalid`, `progress.resume.concurrent`, `progress.resume.stale_revision`, `progress.resume.stale_hash`, `progress.resume.double_resume`를 다른 이름이나 성공 상태로 치환하지 않는다. 상세 실패는 `오류 reason=<reason> detail=<detail>` 형식을 유지한다.

## Go 전제와 source topology

- module은 `github.com/WonderRabbit/wonder-sensai2`다.
- `go.mod` directive는 `go 1.26.0`이고, build toolchain prerequisite는 정확히 Go `1.26.5`다. 자동 다운로드나 시스템 설치는 제품 동작에 포함하지 않는다.
- 제품 source는 `go.mod`와 `cmd/sensai/*.go`다. `main.go`는 signal과 exit 연결만 담당하고 command, runtime, package, mission 책임을 파일별로 나눈다.
- 외부 Go module과 `go.sum`은 없다. stdlib-only는 Go dependency 경계를 뜻하며, 기존 계약에 포함된 `jq`, `git` 실행과 `doctor tools`의 제품 probe를 제거한다는 뜻이 아니다.
- source mode 실행 파일은 Unix `<source>/bin/sensai`, Windows `<source>\bin\sensai.exe`에 있어야 한다. 두 파일은 함께 commit하는 tracked 전달 artifact이며 `stage`와 `install`은 이 layout에서만 허용한다.
- 설치 뒤 runtime은 config와 CLI를 분리한다. 36개 config leaf는 platform home의 `.config/opencode` 아래, CLI는 `.local/bin` 아래 하나만 둔다.
- `cmd/sensai/`와 `go.mod`가 동작과 재현의 semantic authority이고 `bin/sensai`와 `bin/sensai.exe`는 rebuild 가능한 전달 artifact다. artifact를 직접 수정하거나 source와 따로 갱신하지 않는다.
- `dist/`는 사용해도 ignored·noncanonical local scratch다. 그 안의 binary를 source mode, final delivery, commit 대상으로 사용하지 않는다.

## 정확한 build matrix

`CGO_ENABLED=0`과 `-trimpath`를 사용한다. target matrix는 정확히 다음 두 행이다.

| GOOS | GOARCH | 파일 이름 |
| --- | --- | --- |
| `darwin` | `arm64` | `sensai` |
| `windows` | `amd64` | `sensai.exe` |

canonical tracked output은 각각 `bin/sensai`, `bin/sensai.exe`다. 두 target을 같은 source revision과 exact Go `1.26.5`로 함께 재생성한다.

```sh
env CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -trimpath -o bin/sensai ./cmd/sensai
env CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -trimpath -o bin/sensai.exe ./cmd/sensai
```

## 플랫폼 경로와 link/reparse 정책

| 표면 | Unix/macOS | Windows |
| --- | --- | --- |
| home | absolute physical `$HOME` | absolute physical `%USERPROFILE%` |
| source CLI | `<source>/bin/sensai` | `<source>\bin\sensai.exe` |
| installed config | `$HOME/.config/opencode` | `%USERPROFILE%\.config\opencode` |
| installed CLI | `$HOME/.local/bin/sensai` | `%USERPROFILE%\.local\bin\sensai.exe` |
| executable | regular file, mode `0755` | regular file, `.exe` suffix |
| path component | macOS system alias 예외 외 symlink 거부 | symlink, junction, 기타 모든 reparse point 거부 |
| no-replace file publish | same-directory temp와 hard link | same-volume `MoveFileExW`, replace flag 없음 |
| atomic replace | same-directory rename | `MoveFileExW` with replace-existing |

`OPENCODE_CONFIG_DIR`, `XDG_CONFIG_HOME`, platform home 순서의 runtime config 탐색은 설치 위치를 바꾸지 않는다. executable, parent, managed leaf, stage destination과 mission/project 경로는 physical path여야 하며 link/reparse component가 있으면 성공으로 우회하지 않는다.

## 원자 게시와 rollback

- `stage`는 부재한 절대 target의 같은 parent에 temporary tree와 directory lock을 만들고 36개 leaf의 exact-set과 hash를 검증한 뒤 no-replace directory move로 한 번만 공개한다.
- `install`은 managed 36개와 CLI를 쓰기 전·lock 획득 후 두 번 분류한다. absent만 생성하고 byte-equal regular file은 no-op이며 differing regular file, link/reparse point, directory, 비정규 파일은 첫 쓰기 전에 `package.managed_conflict`, exit `73`으로 거부한다.
- install의 각 leaf는 destination과 같은 디렉터리의 temp를 검증한 뒤 no-replace로 게시한다. 전체 install은 단일 rename이 아니라 leaf 단위 atomic publish와 transaction rollback의 조합이다.
- 실패하면 이번 transaction이 만든 파일 중 expected SHA-256이 그대로인 파일과 owned empty directory만 역순으로 제거한다. 기존 파일, 변경된 파일, unmanaged content는 삭제하지 않는다. cleanup 소유권을 증명하지 못하면 `package.rollback_failed`, exit `75`다.
- mission state는 same-directory candidate, revision/hash CAS와 single-writer lock을 거쳐 atomic replace한다. stale·concurrent 상태는 partial write 없이 exit `75`다.

## 검증 예산과 Windows 증명 경계

이 전환은 새 test framework를 만들지 않는다. 구현 전후 직접 관련 selector인 `doctor`, `packaging`, `docs`를 각 최종 입력에서 한 번만 사용하고, Go source에는 `gofmt -l cmd/sensai`, `go test ./...`, `go vet ./...`, `go list -m all`을 한 번 적용한다. 문서-only 동기화는 `./tests/test.sh docs`와 `git diff --check`만 사용한다. `self`, `all`, 반복 selector와 무관한 packaging·fixture 검사는 이 PRD 작업 범위가 아니다.

macOS에서는 `darwin/arm64` binary로 `help`, `stage`, 격리 `install`, `mission init/status`를 직접 실행할 수 있다. Windows 산출물은 macOS에서 cross-compile하고 module metadata와 PE32+ x86-64 형식까지만 확인했다. 실제 Windows에서 `<source>\bin\sensai.exe` 또는 `%USERPROFILE%\.local\bin\sensai.exe`를 직접 실행한 receipt가 없으므로 현재 상태는 `WINDOWS_COMPATIBILITY_UNVERIFIED`다.

## OpenCode slash-command Scope OUT

`output/commands/sensai/{run,resume,status}.md`의 runtime binding은 extension 없는 `"$HOME/.local/bin/sensai"`다. 이번 변경은 payload bytes와 binding을 고치지 않는다. 따라서 Windows에서 `sensai.exe`를 직접 실행하는 CLI 검증만 향후 native receipt 대상이며, Windows OpenCode slash-command가 이 CLI를 호출하는 통합은 **Scope OUT**이다. 별도 payload 계약과 native 검증 없이 slash-command 호환을 주장하지 않는다.

## 수용 조건

- public command, exit와 핵심 `reason`이 보존되고 module source가 stdlib-only다.
- 정확한 Go `1.26.5`로 두 target만 `CGO_ENABLED=0`, `-trimpath` build되며 module identity와 파일 형식이 일치한다.
- macOS direct smoke가 disposable root에서 성공하고 실제 HOME, global config, source payload를 변경하지 않는다.
- source/install 경로, link/reparse 거부, no-replace publish와 owned rollback이 플랫폼 계약과 일치한다.
- `output/`, `manifest.txt`, fixtures는 byte와 diff 모두 불변이다.
- authority 문서가 Go CLI와 두 target을 설명하면서 `WINDOWS_COMPATIBILITY_UNVERIFIED`와 slash-command Scope OUT을 유지한다.
- 문서 검증 예산 안의 명령이 exit `0`이고 evidence에 invocation, exit, observable, cleanup이 남는다.

## 회귀와 rollback

수용 조건이 실패하면 새 artifact를 commit·push·배포·덮어쓰기·업로드하지 않는다. disposable smoke state와 실패한 uncommitted `bin/sensai`, `bin/sensai.exe`를 제거한 뒤 같은 source revision에서 두 target을 함께 다시 build한다. 이미 tracked artifact를 갱신한 경우에는 source와 artifact를 부분 혼합하지 않고 version control의 직전 검증된 쌍으로 복원한다. 설치 도중 실패한 상태는 위 owned-state rollback만 수행하며 사용자 기존 config나 unmanaged content를 강제로 복구 대상으로 삼지 않는다. Windows native receipt가 없거나 거부되면 macOS local 상태는 유지하되 Windows 상태만 `WINDOWS_COMPATIBILITY_UNVERIFIED`로 남긴다.
