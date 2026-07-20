# 대상 저장소 preflight와 운영

이 문서는 이미 설치한 `$HOME/.local/bin/sensai`로 실제 저장소를 분석하기 전에 수행할 안전 점검과 F0-F5 운영 절차를 정의한다. 설치와 기본 사용법은 [설치와 대상 저장소 분석 안내서](target-repo-analysis-guide.md)를 먼저 따른다.

현재 결정적 구현 범위와 live 입학 범위를 구분한다.

- installer는 managed config leaf 36개를 기존 `$HOME/.config/opencode`에 배치한다. runtime read root는 `OPENCODE_CONFIG_DIR`, `${XDG_CONFIG_HOME}/opencode`, `$HOME/.config/opencode` 순으로 선택한다.
- 실행 파일은 `$HOME/.local/bin/sensai` 하나다.
- project override는 `<project>/.sensai/{schemas,recipes}`의 요청 파일 단위다.
- `output/`은 source checkout의 packaging source일 뿐 runtime root가 아니다.
- `LOCAL_IMPLEMENTATION`과 별개로 live model과 tool call은 `MODEL_ADMISSION=UNVERIFIED`다. 명시적 비용·credential 승인과 admission receipt 없이 live 분석을 시작하지 않는다.

## 1. 점검할 경계를 고정한다

모든 명령에서 source checkout, 설치 위치와 대상 저장소를 섞지 않는다.

```sh
set -eu

TARGET_REPO="/absolute/path/to/target"
TARGET_SCOPE="services/order"
SENSAI_CLI="$HOME/.local/bin/sensai"

if test -n "${OPENCODE_CONFIG_DIR:-}"; then
  SENSAI_RUNTIME_CONFIG=$OPENCODE_CONFIG_DIR
elif test -n "${XDG_CONFIG_HOME:-}"; then
  SENSAI_RUNTIME_CONFIG=$XDG_CONFIG_HOME/opencode
else
  SENSAI_RUNTIME_CONFIG=$HOME/.config/opencode
fi
```

`TARGET_SCOPE`는 저장소 안에 실제로 존재하는 구체적인 상대 경로여야 한다. 현재 `mission init` 계약은 empty 값과 `.`을 거부하므로 저장소 전체를 암시하는 값으로 우회하지 않는다. 대상 저장소에 `output/`, `bin/sensai` 또는 global config 복사본을 만들지 않는다.

## 2. physical path와 symlink preflight

### 절대 경로와 component 확인

사용자가 입력한 대상 경로는 정규화된 절대 경로여야 한다. filesystem root, trailing slash, 중복 slash, `.`·`..` component와 어느 위치의 symlink component도 허용하지 않는다. 마지막 leaf만 `test ! -L`로 검사하면 parent symlink를 놓치므로 입력 경로와 `pwd -P` 결과를 함께 비교한다.

```sh
case "$TARGET_REPO" in
  /) printf '%s\n' 'STOP: filesystem root는 대상이 될 수 없다' >&2; exit 73 ;;
  /*) ;;
  *) printf '%s\n' 'STOP: TARGET_REPO는 절대 경로여야 한다' >&2; exit 73 ;;
esac

case "$TARGET_REPO" in
  */|*//*|*/./*|*/../*|*/.|*/..)
    printf '%s\n' 'STOP: 정규화되지 않은 TARGET_REPO' >&2
    exit 73
    ;;
esac

TARGET_REPO_CONTROL_FREE=$(printf '%s' "$TARGET_REPO" | LC_ALL=C tr -d '[:cntrl:]') || exit 73
test "$TARGET_REPO_CONTROL_FREE" = "$TARGET_REPO" || {
  printf '%s\n' 'STOP: TARGET_REPO에 control character가 있다' >&2
  exit 73
}

test -d "$TARGET_REPO" || exit 73
test ! -L "$TARGET_REPO" || exit 73
TARGET_REPO_PHYSICAL=$(cd "$TARGET_REPO" && pwd -P) || exit 73
test "$TARGET_REPO" = "$TARGET_REPO_PHYSICAL" || {
  printf '%s\n' 'STOP: TARGET_REPO에 symlink 또는 비정규 component가 있다' >&2
  exit 73
}
```

`SENSAI_CLI`와 `SENSAI_RUNTIME_CONFIG`도 같은 원칙으로 검사한다. CLI는 exact physical `$HOME/.local/bin/sensai`인 regular executable이어야 하고 executable 또는 parent symlink를 허용하지 않는다. runtime config root는 위 precedence로 선택한 normalized absolute physical directory여야 한다.

```sh
test -f "$SENSAI_CLI"
test -x "$SENSAI_CLI"
test ! -L "$SENSAI_CLI"
case "$SENSAI_RUNTIME_CONFIG" in
  /|/*//*|*/./*|*/../*|*/.|*/..|*/|'') exit 65 ;;
  /*) ;;
  *) printf '%s\n' 'STOP: runtime config root는 절대 경로여야 한다' >&2; exit 65 ;;
esac
SENSAI_CONFIG_CONTROL_FREE=$(printf '%s' "$SENSAI_RUNTIME_CONFIG" | LC_ALL=C tr -d '[:cntrl:]') || exit 65
test "$SENSAI_CONFIG_CONTROL_FREE" = "$SENSAI_RUNTIME_CONFIG" || {
  printf '%s\n' 'STOP: runtime config root에 control character가 있다' >&2
  exit 65
}
test -d "$SENSAI_RUNTIME_CONFIG"
test ! -L "$SENSAI_RUNTIME_CONFIG"

test "$(cd "$(dirname "$SENSAI_CLI")" && pwd -P)/$(basename "$SENSAI_CLI")" = "$SENSAI_CLI"
test "$(cd "$SENSAI_RUNTIME_CONFIG" && pwd -P)" = "$SENSAI_RUNTIME_CONFIG"
```

### 상대 scope와 내부 symlink 확인

scope는 project root 기준 상대 경로다. 절대 경로, empty 값, `.`·`..` traversal과 control character를 허용하지 않는다. 선택한 scope는 물리적으로 project root 안에 있어야 하며 scope 내부의 symlink도 분석 입력에서 제외한다.

```sh
case "$TARGET_SCOPE" in
  ''|.|..) printf '%s\n' 'STOP: empty, dot 또는 dot-dot scope' >&2; exit 64 ;;
  /*|../*|*/../*|*/..|./*|*/./*|*/.|*//* )
    printf '%s\n' 'STOP: unsafe relative scope' >&2
    exit 64
    ;;
esac

TARGET_SCOPE_CONTROL_FREE=$(printf '%s' "$TARGET_SCOPE" | LC_ALL=C tr -d '[:cntrl:]') || exit 64
test "$TARGET_SCOPE_CONTROL_FREE" = "$TARGET_SCOPE" || {
  printf '%s\n' 'STOP: scope에 control character가 있다' >&2
  exit 64
}

SCOPE_PATH="$TARGET_REPO/$TARGET_SCOPE"
test -e "$SCOPE_PATH" || exit 65
test ! -L "$SCOPE_PATH" || exit 65

SCOPE_PARENT=$(dirname "$SCOPE_PATH")
SCOPE_LEAF=$(basename "$SCOPE_PATH")
SCOPE_PHYSICAL=$(cd "$SCOPE_PARENT" && printf '%s/%s\n' "$(pwd -P)" "$SCOPE_LEAF") || exit 65
test "$SCOPE_PATH" = "$SCOPE_PHYSICAL" || {
  printf '%s\n' 'STOP: scope에 symlink 또는 비정규 component가 있다' >&2
  exit 65
}
case "$SCOPE_PHYSICAL" in
  "$TARGET_REPO"|"$TARGET_REPO"/*) ;;
  *) printf '%s\n' 'STOP: scope가 project root 밖이다' >&2; exit 65 ;;
esac

if ! SCOPE_SYMLINKS=$(find "$SCOPE_PATH" -type l -print -quit); then
  printf '%s\n' 'STOP: scope symlink 검사를 완료하지 못했다' >&2
  exit 69
fi
if test -n "$SCOPE_SYMLINKS"; then
  printf '%s\n' 'STOP: scope 내부에 symlink가 있다' >&2
  exit 65
fi
```

이 점검과 실제 실행 사이에 경로 소유자나 파일이 바뀌면 preflight 결과를 재사용하지 않는다.

## 3. secret-like path를 content 없이 검사한다

mission fingerprint는 선택한 regular file의 내용을 읽을 수 있다. 따라서 `mission init`, OpenCode 또는 model을 실행하기 전에 pathname만 검사하고 민감할 가능성이 있는 파일을 scope에서 제외한다. scope 자체가 아래 보호 경계와 같거나 그 하위이면 즉시 거부한다.

```sh
case "/$TARGET_SCOPE/" in
  */.git/*|*/.omo/*|*/.ssh/*|*/.aws/*|*/.config/opencode/*|*/.local/share/opencode/*|*/docs/analysis/missions/*)
    printf '%s\n' 'STOP: protected subtree는 scope가 될 수 없다' >&2
    exit 65
    ;;
esac

if ! SENSITIVE_PATHS=$(find "$SCOPE_PATH" \
  \( -type d \
     \( -name '.git' -o -name '.omo' -o -name '.ssh' -o -name '.aws' \
        -o -path '*/.config/opencode' -o -path '*/.local/share/opencode' \
        -o -path '*/docs/analysis/missions' \) \
     -print -prune \) -o \
  \( -type f \
     \( -name '.env' -o -name '.env.*' -o -name '*.pem' -o -name '*id_rsa*' \
        -o -name '*credentials*' -o -name '*secrets.*' -o -name 'auth.json' \) \
     -print \)); then
  printf '%s\n' 'STOP: secret-like pathname 검사를 완료하지 못했다' >&2
  exit 69
fi

if test -n "$SENSITIVE_PATHS"; then
  printf '%s\n' "$SENSITIVE_PATHS"
  printf '%s\n' 'STOP: protected 또는 secret-like path가 있다' >&2
  exit 65
fi
```

`.ssh/**`, `.aws/**`, `.config/opencode/**`, `.local/share/opencode/**`, `.git/**`, `.omo/**`와 기존 `docs/analysis/missions/**`는 발견한 directory에서 traversal을 중단하고 subtree 전체를 거부한다. 파일을 열어 false positive 여부를 확인하지 않는다. 소유자가 scope를 좁히거나 비밀을 제거한 안전한 별도 입력 사본을 준비한 뒤 처음부터 점검한다. 출력이 없다는 사실은 secret 부재 증명이 아니다. 실제 credential, `.env`, auth config와 raw model transcript를 config, mission receipt 또는 evidence에 복사하지 않는다.

## 4. OpenCode merge surface를 보존하고 검토한다

OpenCode는 global config와 project-local surface를 자체 규칙으로 합칠 수 있다. 다음 항목의 존재 여부를 content 변경 없이 확인한다.

```sh
for TARGET_PATH in \
  "$TARGET_REPO/opencode.json" \
  "$TARGET_REPO/opencode.jsonc" \
  "$TARGET_REPO/.opencode" \
  "$TARGET_REPO/AGENTS.md" \
  "$TARGET_REPO/CLAUDE.md"
do
  if test -e "$TARGET_PATH" || test -L "$TARGET_PATH"; then
    printf '%s\n' "$TARGET_PATH"
  fi
done
```

발견된 파일은 지우거나 이름을 바꾸거나 자동 merge하지 않는다. 다음 항목을 사람이 검토하고 현재 target에 결합된 결정을 남기기 전에는 live 분석을 시작하지 않는다.

- instruction 우선순위와 상충 규칙
- agent·command·skill 이름 충돌
- tool, shell, network와 write permission의 확대 여부
- project-local provider/model 또는 plugin 설정의 영향
- global config의 unmanaged content가 함께 로드되는지 여부

`OPENCODE_CONFIG_DIR` 지정만으로 hermetic isolation을 주장하지 않는다. 의미 검사는 disposable `HOME`, 모든 XDG path, `TMPDIR`, neutral CWD와 inherited sentinel을 갖춘 환경에서 수행한다. `opencode debug`는 초기화 파일을 쓸 수 있으므로 실제 HOME, source checkout과 실제 target에서 acceptance 명령으로 실행하지 않는다.

## 5. dirty worktree와 Git 기준선

secret과 merge 검사를 통과한 뒤, `mission init`이 `docs/analysis/missions/`를 만들기 전에 기준선을 기록한다.

```sh
cd "$TARGET_REPO"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_TOP=$(git rev-parse --show-toplevel) || exit 69
  GIT_TOP_PHYSICAL=$(cd "$GIT_TOP" && pwd -P) || exit 69
  test "$GIT_TOP_PHYSICAL" = "$TARGET_REPO" || {
    printf '%s\n' 'STOP: Git top-level과 TARGET_REPO가 다르다' >&2
    exit 65
  }
  if GIT_HEAD=$(git rev-parse --verify HEAD 2>/dev/null); then
    printf '%s\n' "$GIT_HEAD"
  else
    GIT_HEAD_REF=$(git symbolic-ref -q HEAD 2>/dev/null) || {
      printf '%s\n' 'STOP: HEAD를 해석할 수 없다' >&2
      exit 69
    }
    case "$GIT_HEAD_REF" in
      refs/heads/*) ;;
      *) printf '%s\n' 'STOP: unborn HEAD ref가 올바르지 않다' >&2; exit 69 ;;
    esac
    printf '%s\n' 'UNBORN'
  fi
  git status --short || exit 69
else
  printf '%s\n' 'NO_GIT_BASELINE'
fi
```

기준선에는 최소한 다음을 남긴다.

- project의 physical absolute path와 선택한 relative scope
- Git repository이면 target과 일치하는 physical top-level, HEAD 또는 `UNBORN`, `git status --short`
- dirty file을 현재 입력에 포함할지, 소유자가 만든 별도 clean snapshot을 사용할지에 대한 사람 결정
- preflight 시각과 실행한 CLI의 SHA-256

dirty change를 자동으로 discard, stash, commit 또는 reset하지 않는다. 현재 worktree를 선택하면 sensai의 fingerprint와 근거는 그 시점의 dirty content를 포함한다. clean 기준이 필요하면 저장소 소유자가 먼저 commit하거나 별도 worktree를 준비하고, 새 physical path에서 preflight를 다시 수행한다.

다음은 분석 입력에서 제외한다.

- `.git/`, `.omo/`, 기존 `docs/analysis/missions/`
- `.env`, private key, credential, token과 secret material
- scope 밖 파일
- symlink와 symlink가 가리키는 외부 파일

OpenCode permission은 행동 정책과 승인 UI이며 OS sandbox가 아니다. credential, filesystem과 network 격리는 별도 실행 환경이 담당한다.

## 6. F0-F5 승인과 영수증

### 단계별 hard gate

| 단계 | 산출과 결정 | 다음 단계 조건 |
| --- | --- | --- |
| F0 | lead가 target, scope, goal, dependency와 todo를 draft | 사람이 현재 fingerprint에 결합된 F0 계획을 승인 |
| F1/F2 | 기술·비즈니스 AS-IS 조사 | canonical merge는 primary lead가 직렬 수행 |
| F3 | AS-IS UI, sequence, dataflow, story와 검증 receipt | 사람이 현재 AS-IS를 승인 |
| F4 | 수정요청, design, convention·business binding | violation은 사람 verdict 전까지 hard stop |
| F5 | TO-BE 5종, validator와 render receipt | 사람이 최종 승인해야 mission 종료 |

F0, F3, F5, consistency violation과 candidate admission은 hard gate다. 모델은 `accepted`나 `rejected`를 추정하거나 생성할 수 없다. live model/tool admission 또는 필요한 delivery skill이 아직 입학되지 않았으면 해당 단계에서 `MODEL_ADMISSION_UNVERIFIED`로 중단한다.

### approval receipt 계약

F0/F3/F5 승인 파일은 정확히 다음 경계에 둔다.

```text
docs/analysis/missions/<mission-id>/approvals/<gate>-approval.json
```

receipt는 `mission_id`, `gate`, `verdict`, `reason`, `actor_role`, `source`, `recorded_at`, `trace_sha256`, `inputs_sha256`만 가진 닫힌 JSON 객체다. `actor_role`은 `human`, `source`는 `elicited`, `verdict`는 `accepted|rejected`여야 한다. `progress.json`의 승인 항목은 같은 결정, receipt 상대 경로와 실제 SHA-256을 가리켜야 한다.

과거 receipt의 trace 또는 input hash가 현재 fingerprint와 다르면 stale이다. 복사, timestamp 수정 또는 hash 재계산으로 재사용하지 않는다. 사람이 현재 자료를 다시 검토해 새 결정을 내려야 한다.

현재 checkout에 승인 의도를 안전하게 수집하고 receipt와 progress transition을 함께 쓰는 admitted interface가 없으면 수기 JSON이나 모델 생성 파일로 우회하지 않고 gate에서 `STOP`한다. `mission init`, `checkpoint`, `status`, `resume`은 사람 승인을 대신하지 않는다.

## 7. 실행 영수증과 운영 기록

설치, preflight와 mission 동작마다 다음을 함께 보존한다.

- 실행한 명령과 exact CLI path
- 시작·종료 시각, exit code와 reason code
- source, installed CLI, config root와 project root의 physical path
- CLI와 선택된 managed/runtime asset의 SHA-256 및 `project|global` provenance
- install이면 config/CLI 각각의 `created|unchanged|conflict` 결과와 PATH 판정
- mission이면 revision, 이전 state hash, current input hash와 필요한 approval receipt hash
- cleanup 또는 rollback 대상, 실제 결과와 남은 수동 조치

영수증은 성공 범위를 확대하지 않는다. 예를 들어 config load 성공은 live model 응답, tool call, TUI delegation 또는 F0-F5 성공의 증거가 아니다.

## 8. 실패 복구

### mission 상태

먼저 검증 가능한 상태만 읽는다.

```sh
cd "$TARGET_REPO"
"$SENSAI_CLI" mission status <mission-id>
```

- `progress.resume.stale_hash` 또는 `progress.resume.stale_revision`이면 최신 status의 revision과 SHA-256을 확인하고 사람이 새 resume 요청을 만든다.
- exit `75`이면 다른 writer, lock 또는 stale precondition을 뜻한다. 덮어쓰기, 자동 retry 또는 다른 process의 lock 삭제를 하지 않는다.
- 손상된 `progress.json`을 추정값으로 고치지 않는다. 마지막 valid `trace.json`, current input hash와 Git 기준선을 보존하고 새 사람 결정을 요청한다.
- primary lead만 canonical mission state를 쓴다. peer 결과는 근거 후보이며 직접 merge하지 않는다.
- F5 `completed` mission은 resume하지 않고 `mission status`로만 확인한다.

### runtime asset과 install

- project override가 present-invalid이면 global fallback을 강제하지 않는다. 소유자가 해당 project file을 수정하거나 명시적으로 제거한 뒤 다시 검증한다.
- `package.managed_conflict`는 기존 managed path 또는 CLI가 source와 다르다는 뜻이다. overwrite, backup rename 또는 symlink 우회를 하지 않고 양쪽 hash와 소유자를 확인한다.
- install 실패 시 CLI가 이번 실행에서 만든 expected-hash 파일과 owned empty directory만 rollback한다. preexisting equal leaf와 unmanaged global content는 복구 대상이 아니다.
- `package.rollback_failed`이면 추가 install을 멈추고 install journal, 실제 남은 path·type·hash를 수동 점검한다.
- actual HOME에서 `opencode debug`나 broad cleanup을 실행해 상태를 복구하려고 하지 않는다.

installer lock은 동시에 실행된 `sensai install`끼리 직렬화한다. 같은 사용자 권한의 외부 프로세스가 lock을 무시하고 설치 중 target namespace를 교체하는 적대적 경쟁까지 막는 보장은 아니다. 그런 경쟁 가능성이 있는 환경에서는 설치를 중단하고 config·CLI target의 소유권, 모든 경로 component와 현재 type을 점검한다.

## 9. 안전한 퇴역

### mission 퇴역

퇴역 전에 current `mission status`, trace/progress hash, Git HEAD와 worktree 상태를 기록한다. 미션 경로가 exact physical `docs/analysis/missions/<mission-id>/`인지, symlink가 없는지, 다른 mission과 겹치지 않는지 확인한다.

완료·중단된 mission 기록은 우선 repository history 또는 소유자가 지정한 archive에 보존한다. 자동 recursive delete나 broad glob을 사용하지 않는다. 제거가 필요하면 소유자가 승인한 exact mission directory만 대상으로 하고, root·project·`docs/analysis/missions` 자체는 절대 삭제 대상에 넣지 않는다.

### global 설치 퇴역

현재 CLI에는 global install 전체를 소유한다고 가정하는 `uninstall` 동작이 없다. `$HOME/.config/opencode`에는 기존 unmanaged content가 공존하므로 root를 rename하거나 삭제해서는 안 된다.

퇴역은 다음 순서의 별도 사람 승인 작업이다.

1. 퇴역할 source release와 root `manifest.txt`를 고정하고 source CLI·leaf SHA-256을 기록한다.
2. install root `$HOME/.config/opencode`와 CLI `$HOME/.local/bin/sensai`를 다시 절대 경로로 해석한다. `/`부터 leaf까지 모든 기존 component를 순서대로 검사해 symlink를 거부하고, leaf 전의 component가 모두 physical directory인지 확인한다. preflight 때의 결과나 `pwd -P` 한 번만 재사용하지 않는다.
3. 각 managed config path가 manifest의 normalized relative path인지 확인한 뒤, install root부터 해당 leaf까지 모든 중간 component가 physical directory이고 non-symlink인지 다시 검사한다. leaf 자체도 regular non-symlink file이어야 한다.
4. installed leaf가 승인된 release source와 byte-equal일 때만 그 exact leaf를 제거 후보로 분류한다. differing, missing, symlink, directory와 비정규 path는 건드리지 않고 `STOP`한다.
5. `$HOME/.local/bin/sensai`도 모든 parent component의 physical directory·non-symlink 조건, exact physical path, regular executable과 승인된 source hash가 모두 일치할 때만 제거 후보로 분류한다.
6. config root 자체와 unmanaged file·directory는 항상 보존한다. managed leaf 제거 뒤 비어 있는 directory도 명시적인 소유 증거가 없으면 남긴다.
7. 제거 직전에 같은 component 검사를 반복하고, 제거 전후 exact inventory와 hash, 사람 승인, 결과와 실패 path를 retirement receipt에 기록한다.

source checkout의 `output/` 또는 다른 project의 `.sensai`를 global 퇴역 대상으로 사용하지 않는다. hash가 다른 파일을 강제로 지우거나 현재 release와 다른 manifest를 섞지 않는다.

## 10. 운영 금지선

- `~`, `/`, workspace root, source checkout, project root와 `$HOME/.config/opencode`에 broad recursive delete를 실행하지 않는다.
- target의 `opencode.json`, `opencode.jsonc`, `.opencode/`, `AGENTS.md`, `CLAUDE.md`를 자동 변경하지 않는다.
- dirty change를 자동 commit, stash, reset 또는 discard하지 않는다.
- credential, raw transcript, secret content를 receipt에 기록하지 않는다.
- project override 오류를 global fallback으로 숨기지 않는다.
- 사람이 승인하지 않은 receipt, stable ID, `path:line`과 evidence를 모델이 발명하게 하지 않는다.
- `MODEL_ADMISSION=UNVERIFIED`를 config discovery나 load 결과만으로 PASS로 바꾸지 않는다.

## 관련 계약

- [제품 계약](PROD.md)
- [runtime 계약](harness/runtime-contract.md)
- [검증 계약](harness/verification-contract.md)
- [release 계약](harness/release-contract.md)
