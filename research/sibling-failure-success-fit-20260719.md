# sibling 실패 원인과 wonder-sensai2 성공 전략

조사일: 2026-07-19
대상: `Tiny-Chu`, `Tiny-Yeah`, `opencode-legacy-kit`, `wonder-sensai2`
판정 기준: 저장소·Git 이력·실행 출력·공식 1차 자료

## 결론

세 sibling을 모두 “기술적으로 실패한 제품”이라고 부를 근거는 없다. 세 프로젝트 모두 실제 구현과 의미 있는 테스트 자산을 갖고 있다. 저장소에서 공통으로 확인되는 문제는 더 좁고 구체적이다.

> 내부 구현·테스트·설치·배포 증거는 많이 남았지만, 실제 대상 환경에서 반복 사용자가 핵심 작업을 끝냈다는 가치 증거는 적거나 없다.

이 문서에서 `실패`는 시장 실패나 사용자 이탈을 뜻하지 않는다. 각 저장소가 스스로 약속한 핵심 가치 경로를 현재 근거로 입증하지 못했거나, 그 가치보다 기능·통제·배포 범위가 먼저 커진 상태를 뜻한다.

`wonder-sensai2`의 성공 가능성을 높이는 최선의 방법은 sibling 전체를 이식하는 것이 아니다. 다음 네 통제만 선택적으로 재구현하고, 가장 작은 실제 가치 경로를 먼저 통과시켜야 한다.

1. `opencode-legacy-kit`의 stack-first 수직 근거 사슬과 single-writer/read-only peer.
2. Tiny-Chu의 evidence gate, SOT close, fingerprint-bound resume packet.
3. Tiny-Yeah의 typed failure, preflight, cleanup receipt 원칙.
4. 본 프로젝트 고유의 `evidence → trace → AS-IS → human gate → TO-BE` 얇은 수직 슬라이스.

이 조합의 설계 적합도는 현재 rubric으로 **96%**다. 운영 조건을 보수적으로 낮춘 stress score는 **92%**다. 이 값은 성공 확률이나 통계적 신뢰구간이 아니라, 아래 가중치와 hard veto를 사용한 설계 호환성 점수다.

## 판정 요약

| 대상 | 방어 가능한 판정 | whole-lineage fit | 그대로 도입 |
| --- | --- | ---: | --- |
| `opencode-legacy-kit` | 테스트된 v1과 미커밋 v2 대전환이 공존하며, 두 세대 모두 실제 Windows·모델·real-repo E2E 가치 증거가 없다. | **76%** | **NO** |
| Tiny-Chu | 광범위하게 구현·테스트됐지만 99-tool 표면이 자체 small-model 실패 임계값 88을 넘는다. | **55%** | **NO** |
| Tiny-Yeah | 안전·설치 공학은 강하지만 실제 OpenCode 표면은 seed/demo/diagnostic 3개이고 성공하는 domain workflow가 없다. | **43%** | **NO** |
| 추천 composite | 계약 정리와 얇은 수직 슬라이스를 먼저 두고 sibling 통제만 shell/CLI로 재구현한다. | **96%** | 조건부 **YES** |

적합도는 가까운 5% 단위로 해석해야 한다. 예를 들어 76.9%와 76.8%의 차이는 의미가 없다. Node/TS 제품 runtime, plugin/MCP/TUI, 전역 설정 직접 수정처럼 현재 계약을 위반하는 항목은 총점으로 보상할 수 없는 binary rejection이다.

## 조사 방법과 한계

- 18개 1차 조사 축과 두 차례 확장 파동, 마지막 반증 파동을 사용했다.
- sibling/current repo의 source, test, docs, ignored `.omo`/`plan`, Git history와 삭제된 파일을 구분해 읽었다.
- 실행 가능한 범위에서 typecheck, test, fixture hash, bundle verifier, doctor, plugin tool call, OpenCode `v1.18.3` isolated binary probe를 수행했다.
- OpenCode, Qwen/Ollama, provenance/verification은 각각 공식 문서·tagged source·표준·원 논문을 30개 이상의 검색 변형으로 교차 확인했다.
- Git commit이나 테스트 PASS는 adoption, 실제 사용자 가치, private 배포를 증명하지 않는다.
- 공개 star/tag/release 부재는 약한 공개 신호일 뿐 “사용자 0명”의 증거가 아니다.
- 원인 판정은 `증상 → 근접 원인 → 구조적 위험 → 미확인 사업 결과`를 분리했다.

## 1. Tiny-Chu

### 확인된 사실

Tiny-Chu는 `f99276f`에서 10개 source file, 729 LOC, test 1개로 시작했다. 최초 README는 file-backed rule/context, task JSON, checkbox plan, public-job packet, wiki selection을 가진 작은 shell을 설명했고 Team Mode, Hyperplan, 병렬 hook, delegate engine을 제외했다.

8일 뒤 `466d52d`에서는 다음 규모가 됐다.

| 항목 | 최초 | 현재 |
| --- | ---: | ---: |
| source | 10 files / 729 lines | 140 files / 17,583 lines |
| test/support | 1 / 68 | 77 / 12,831 |
| docs | 0 | 31 / 4,716 |
| default tools | 약 10 | 99 / 14 packages |

핵심 모순은 자체 평가 계약에서 나온다.

- `docs/reports/small-model-contribution-evaluation.md:55-69`와 `src/opencode/small-model-contribution.ts:237-242`는 visible tool이 40개를 넘으면 warning, 88개를 넘으면 failure로 본다.
- 실제 default mode는 99개, worker mode는 79개다.
- `9f78455`는 같은 commit에서 evaluator와 93-tool catalog를 함께 도입했다.
- healthy fixture는 실제 79/99 대신 `visibleToolCount: 40`을 hard-code한다: `test/fixtures/small-model-contribution/healthy.json:46-47`.
- default 99 tool에는 명시적 입력 schema가 0개이며 MCP adapter가 generic object schema로 투영한다: `src/opencode/registry-adapter.ts:7,70-89`.

즉 “작은 모델의 선택과 context 부담을 줄인다”는 가치가 실제 shipped surface에서 자체 기준을 위반한다. 이것은 whole-product crash가 아니라 **scope-load inversion**이다.

### 실패 원인의 등급

| 등급 | 판정 | 근거 |
| --- | --- | --- |
| 확인된 운영 결함 | nested release가 `execFile("npm")`를 호출해 child PATH에서 `spawn npm ENOENT` 발생 | `.omo/evidence/tiny-chu-release-offline-npm-enoent/debug-journal-final.md:21-88`, fix `f2b95ef` |
| 현재 해결 | npm path resolution과 typed error가 추가됐고 focused test 6/6 PASS | `scripts/release/npm-runner.mjs:31-109` |
| 구조적 위험 | default 99 tools가 자체 >88 fail 기준 위반 | evaluator/source/registry anchors |
| 확인되지 않음 | 79/99 tool이 실제 Qwen 사용자 이탈이나 실패를 만들었는지 | live repeated trial/telemetry 없음 |
| 반증됨 | “Tiny-Chu는 실행되지 않는다” | typecheck PASS, actual MCP `tools/list` 99, 거의 전체 suite green |

현재 runtime audit은 `tsc --noEmit` PASS, direct suite 383/386 PASS였다. clean tracked HEAD에서는 untracked docs로 생긴 실패가 사라지고 나머지 두 건은 read-only sandbox write 제한이었다. 따라서 구현 품질을 실패 원인으로 단정하면 안 된다.

### 가져올 것과 버릴 것

가져올 것:

- evidence freshness와 strict close gate.
- stable revision/hash를 가진 bounded focus/resume packet.
- path confinement, symlink rejection, stale hash, rollback mutation.
- exact-set과 negative-scope test.

버릴 것:

- Node/TypeScript runtime과 npm 설치 흐름.
- 99-tool registry, MCP/TUI/queue/dashboard.
- generic input schema와 broad capability exposure.
- backlog의 미체크 항목 수를 성공 지표로 삼는 방식.

## 2. Tiny-Yeah

### 확인된 사실

Tiny-Yeah는 안전 kernel과 installer를 훨씬 더 잘 검증했다. 그러나 실제 OpenCode 제품 표면은 다음 세 도구뿐이다.

- `health_check`
- demo `echo_manifest`
- `tiny_yeah_install_check`

`src/core/composer/default-packages.ts:1-40`은 앞의 두 도구를 trivial seed/demo라고 부르고 이후 phase에서 real surface로 교체해야 한다고 적는다. 이후 이 domain surface는 사실상 늘지 않았지만 installer는 production TS의 43.4%인 3,955 LOC, tracked release archive는 약 130 MiB까지 커졌다.

실행 probe는 더 직접적인 문제를 보였다.

- `health_check`는 package/release `1.0.0`인데 static `0.2.0`을 반환한다.
- `echo_manifest` preview는 0으로 채운 placeholder hash를 내며 approve 후 `PREVIEW_STALE`로 실패한다.
- OpenCode adapter는 `approvedPreviewId`를 전달하지 않는다: `src/head/opencode/plugin.ts:82-123`.
- empty/default `{}` tool input은 `UNKNOWN_INTENT_FIELD`; 별도 typed intent를 넣어야 health가 통과한다.
- installer shim은 raw `createTinyYeahPlugin`을 export하지만 installed SDK는 `Plugin → Promise<Hooks>`를 요구하고 실제 adapter `TinyYeahOpenCodePlugin`은 그 shim에 연결되지 않는다.

따라서 현재 확인 가능한 성공하는 user domain workflow는 없다.

### offline verifier가 증명하는 것과 증명하지 않는 것

정상 실행:

```sh
npm run verify:offline -- --bundle release/tiny-yeah-offline-v1.0.0.tar.gz
```

결과는 exit 0, `ok:true`, `offlineInstallOk:true`였다. 이것은 archive extraction, standalone copy, offline npm consumer install, module import를 실제 macOS arm64 host에서 증명한다.

그러나 embedded doctor는 `degraded`, pass 6/warn 6이었다. `opencode`가 없어 “runtime plugin load would fail at startup”이라고 직접 기록했다.

결정적인 adversarial 실행:

```sh
DOCTOR_TIMEOUT_MS=1 npm run verify:offline -- --bundle release/tiny-yeah-offline-v1.0.0.tar.gz
```

이 경우 doctor에는 `DOCTOR_TIMEOUT`, `status:"fail"`, `summary.fail:1`이 있었지만 verifier는 여전히 exit 0, `ok:true`였다. `bundle-checks.mjs:238-294`가 doctor subprocess exit만 보고, `bin/tiny-yeah.js:647-648`이 모든 `degraded`를 exit 0으로 매핑하기 때문이다.

따라서 `ok:true`는 local distribution/import verdict이지 strict health, OpenCode startup, Windows readiness, user value verdict가 아니다.

### Windows와 release 경계

- v1 archive에는 `@opentui/core-darwin-arm64`만 있고 win32 native entry가 없다.
- 20개 `.bin` symlink가 삭제된 macOS temp root의 절대 경로를 가리킨다.
- archive를 만든 host는 macOS arm64이며 native Windows run/CI가 없다.
- checked-in v1 artifact는 이후 `3738702` runtime hardening보다 오래됐지만 version은 계속 `1.0.0`이다.
- `package-lock.json` root version은 `0.7.0`, `package.json`은 `1.0.0`이다.
- tampered standalone code가 pre-import integrity gate 전에 실행/복사될 수 있다는 기존 adversarial evidence가 있다.

### 가져올 것과 버릴 것

가져올 것:

- typed failure code와 recovery hint.
- preflight/cleanup receipt.
- preview → checkpoint → human approval → create-only apply 개념.
- managed path hash, backup/rollback, user file preservation.

버리거나 뒤로 미룰 것:

- TypeScript/Zod/plugin/TUI platform.
- generic composer와 3-surface parity.
- domain value 전에 offline bundle/installer/release ceremony 확장.
- `ok:true` 한 필드로 degraded/fail predicate를 덮는 gate.

## 3. opencode-legacy-kit

### 두 제품 세대를 분리해야 한다

현재 remote/HEAD v1은 실제 TypeScript/Bun/PowerShell runtime이다. 10 agents, 10 commands, 8 libraries, 10 tool adapters, 12 PowerShell scripts, 4 test files와 245 lock entries를 가진다.

현재 local v2는 미커밋 대전환이다.

- branch: `Fix-inventory...origin/Fix-inventory [gone]`
- 69 tracked files changed
- `+809/-7,805`
- 기존 runtime/agent/command/state machinery 삭제
- 2 agents, 1 command, 5 deployment leaves로 축소

따라서 “v1이 실패해 폐기됐다”가 아니라 “tested v1과 미커밋 replacement intent가 공존한다”가 정확하다.

### v1의 확인된 결함과 성공

직접 재검증된 v1 결함:

1. `State.ps1:377-396`은 oracle advice를 감지하지만 worker 재dispatch에 advice를 전달하지 않는다.
2. `State.ps1:298-318`의 exposed `init`은 existing state overwrite guard가 없다.
3. `lib/process.ts:3-18`은 timeout/output cap 없이 stdout/stderr 전체를 buffer한다.
4. AST recipe가 validated query를 실제 pattern에 사용하지 않는다.
5. `fd`/`rg`가 VCS ignore를 따라 source를 누락할 수 있다.
6. Mermaid/offline dependency와 설치 계약이 충돌한다.

반면 exported HEAD의 선언된 test suite는 pinned dependency를 제공했을 때 통과했다. v1에는 config/worktree separation, symlink-aware path, argv-only execution, atomic state, expected revision, adversarial fixture라는 좋은 통제가 있다.

### v2가 증명하는 것

현재 `npm test`는 9/9, 414 assertions PASS지만 출력이 스스로 `STATIC-ONLY`라고 선언한다. Windows/Qwen concurrency/durability, 실제 install/rollback, 두 session resume, real fixture analysis를 증명하지 않는다.

게다가 current installer mutation review는 case-insensitive `Copy-Item`, alias, fence, manifest drift 중 18/57을 놓쳤고 rework GREEN이 없다. `tests/installer-contract.mjs:80-112`의 exact-case regex는 그대로다.

삭제된 초기 assessment는 real small-model E2E 0회, business usefulness 미검증을 기록했다. 이것이 가장 직접적인 제품 가치 gap이다.

### 가져올 것과 버릴 것

가져올 것:

- stack/architecture bootstrap을 detailed analysis보다 먼저 수행.
- single writer + independent read-only peer.
- fact/inference/unknown/conflict 분리.
- exact-leaf manifest, staged copy, revision, rollback.
- static/live/platform evidence label 분리.

버릴 것:

- v1 state machine 전체와 245-package runtime.
- global config whole replacement.
- prompt-only permission을 sandbox처럼 취급하는 방식.
- exact Windows/OpenCode/model pin을 실행 영수증 없이 성공 조건으로 쓰는 방식.
- architecture value proof 전에 7개 CLI와 experimental background를 필수화하는 방식.

## 4. 세 프로젝트의 공통 원인

### 강하게 지지되는 공통점

1. 내부 mechanism proof는 많다.
2. 실제 target environment proof는 상대적으로 적다.
3. repeated user outcome, adoption, business result는 거의 기록되지 않았다.
4. scope·delivery·orchestration이 얇은 user-value loop보다 먼저 커진 시점이 있다.
5. 계획과 결정 근거가 ignored `.omo`로 이동하거나 삭제되어 pivot의 이유가 durable history에 남지 않았다.
6. static/config/bundle PASS가 live model/OpenCode/Windows/user value와 혼동될 위험이 반복됐다.

### 단정하면 안 되는 것

- scope growth가 사용자 이탈을 일으켰다.
- star/tag가 적어서 아무도 쓰지 않았다.
- dirty rewrite가 shipped generation의 실패를 증명한다.
- installer/verification 작업 자체가 가치가 없었다.
- 세 프로젝트가 모두 기술적으로 실행 불가능했다.

가장 안전한 원인 문장은 다음이다.

> 제품 가치 증거가 없었다고 단정할 수는 없지만, 저장소에는 내부 공학 증거가 훨씬 더 많이 남았고 실제 사용자 가치 증거는 durable하게 남지 않았다. 이 불균형 때문에 다음 투자와 중단 판단이 mechanism 수와 PASS artifact에 끌려갈 위험이 커졌다.

## 5. wonder-sensai2의 현재 위험

### 5.1 계약 freeze가 실제로 끝나지 않았다

`docs/PROD.md:53-61`은 다음 lowercase taxonomy를 정의한다.

`stack, structure, naming, api_pattern, state, coding_standard, scaffold_pattern`

그러나 `README.md:75`, `tests/cases/docs.sh:640`, `fixtures/expected/trace-v2.json:15-21`은 다음 uppercase taxonomy를 사용한다.

`NAMING, STRUCTURE, COMPONENT, API, STATE, ERROR, TEST`

둘은 단순 case alias가 아니며 의도된 mapping도 없다. 현재 docs selector는 README만 검사해 모순이 있는 `docs/PROD.md` hash로도 T03 PASS를 냈다. schema/runtime authority가 없으므로 현재 상태는 `UNRESOLVED`다.

최소 변경 후보는 uppercase set이다. public README, executable test, golden trace, `CONV-*` stable ID와 일치한다. 다만 구현 전에 사람의 source-owned 결정과 cross-surface mutation이 필요하다.

### 5.2 fingerprint가 product source가 아니라 local churn을 해시한다

`tests/lib/tooling.sh:76-96`은 `.git`과 `.omo/evidence`만 제외하고 모든 regular file을 해시한다. 그 결과 ignored `.omo`, `plan`, `STATUS.md`, `.DS_Store`, hidden tool state가 source fingerprint에 들어간다.

같은 product bytes에서 두 번 실행한 결과:

| 실행 | files | ignored inputs | fingerprint |
| --- | ---: | ---: | --- |
| 1 | 160 | 94 | `f6a46646…` |
| 2 | 168 | 103 | `f9759d32…` |

차이는 team/research `.omo` artifact였다. receipt는 ignored input inventory를 보존하지 않아 사후 재구성도 불가능하다. 이는 주로 false-green보다 false-stale/availability defect다.

해결은 source-owned manifest fingerprint와 optional local-context fingerprint를 분리하는 것이다. exact sorted `path<TAB>sha256` 목록도 receipt와 함께 보존해야 한다.

### 5.3 test preflight가 selector보다 넓다

현재 `./tests/test.sh self|docs|fixtures|core-readiness`는 모두 stdout 없이 다음으로 끝난다.

```text
INFRA_ERROR missing_command command=yq
exit 70
```

`yq`를 임시 neutralize하면 다음 blocker는 `rg`다. `tests/test.sh:93-112`가 모든 selector에 전체 tool list를 먼저 요구하기 때문이다. evidence setup은 그 뒤라 이 infrastructure failure receipt도 남지 않는다.

selector별 필요한 tool만 preflight하고, global doctor는 별도의 typed report로 분리해야 한다. 도구 자동 설치는 하지 않는다.

### 5.4 fixture는 integrity-ready지만 semantic-validator-ready가 아니다

현재 37 physical fixture files, 28 unique cases, 14 happy/14 adversarial, checksum과 Mermaid syntax는 강하다. 그러나 `tests/cases/fixtures.sh`는 duplicate ID/route, dangling reference, hidden conflict, provenance mismatch, output escape, stale progress를 실제 validator에 넣지 않는다.

즉 corpus registry는 존재하지만 adversarial reason의 semantic rejection은 아직 증명되지 않았다. schema/recipe/validator가 생길 때 각 reason을 named failure code로 실행해야 한다.

### 5.5 첫 가치 증명이 너무 늦다

local PRD/todo는 smallest E2E before expansion을 요구하지만 active plan은 15 skills와 9 commands를 만든 뒤 T23에서 첫 AS-IS E2E를 실행한다. 이 순서는 sibling의 scope-before-value 위험을 되풀이한다.

`LOCAL_IMPLEMENTATION_PASS`는 exact 2/9/15를 요구하므로 얇은 slice를 그 이름으로 부르면 안 된다. 별도 `VERTICAL_SLICE_PASS`를 정의해야 한다.

### 5.6 unborn/untracked 상태와 stale docs

- Git `HEAD`가 없고 intended source files가 전부 untracked다.
- `git diff --check`는 이 파일들을 보지 못해 vacuous green이다.
- source docs는 runner/fixture가 없다고 적지만 실제로 test runner와 37-file corpus가 있다.
- frozen `AGENTS.md`는 `tests/test.sh`가 없다고 적어 contributor guidance가 의도적으로 stale하다.
- source `docs` test가 ignored `plan/`과 `STATUS.md`에 의존해 future clean clone에서 재현되지 않는다.

## 6. 추천 메커니즘과 fit

점수 공식은 다음과 같다.

`Fit = Σ(weight × rating / 5)`

| 차원 | weight |
| --- | ---: |
| user value-path alignment | 25 |
| architecture constraints | 20 |
| verification/evidence | 18 |
| operational portability | 12 |
| complexity containment | 12 |
| reversibility | 8 |
| uncertainty control | 5 |

| 순위 | 추천 메커니즘 | fit | 입학 판정 |
| ---: | --- | ---: | --- |
| 1 | legacy stack-first vertical evidence + single-writer/read-only peer | **89%** | P0 pattern |
| 2 | Tiny-Chu evidence gate + workflow SOT close | **86%** | shell/CLI 재구현 후 P0 |
| 3 | Tiny-Chu bounded focus/resume packet | **84%** | shell/JSON 재구현 후 P0 |
| 4 | Tiny-Yeah typed failure boundary | **81%** | error taxonomy만 P0 |
| 5 | legacy exact-leaf manifest + backup/rollback | **77%** | P1 stage/release |
| 6 | native OpenCode primitive, no custom runtime | **77%** | pinned behavior 검증 후 P0 |
| 7 | Tiny-Yeah preview/checkpoint/approval/apply | **75%** | P1 concept |
| 8 | Tiny-Chu safe patch precondition/rollback | **70%** | source write가 범위에 들어올 때만 |
| 9 | Tiny-Yeah offline bundle/doctor/receipt | **65%** | useful E2E 이후 |
| 10 | Tiny-Chu feature registry/three-surface parity | **60%** | 현재 reject |
| 11 | Tiny-Yeah composer/TUI parity | **60%** | 현재 reject |

5점 이내 차이는 tie로 취급한다. 추천 상위 집합은 weight 변경에도 유지됐지만, 이는 author-chosen rubric 내부의 robustness일 뿐 통계적 calibration이 아니다.

## 7. 성공 로드맵

### G1 — 계약과 증거 baseline

진입: runtime 구현 전.

산출:

- canonical 7-category enum 1개.
- `source set`, `OpenCode staged payload`, `fixture corpus`, `release bundle` exact-set 분리.
- `.omo/**`, ignored plan/status, OS file을 제외한 source manifest fingerprint.
- current runner/fixture 상태로 docs 갱신.

검증:

- enum이 PROD/README/schema/golden/test에서 동일.
- unrelated `.omo` 변경 전후 source fingerprint 동일.
- source file 한 byte 변경 시 fingerprint 변화.

중단: source-owned contradiction이 하나라도 남으면 schema/recipe/agent 구현 금지.

### G2 — host와 fail-closed bootstrap

산출:

- selector-scoped preflight.
- independent CLI identity/version/hash.
- current `self`, `docs`, `fixtures`, expected-failure, named core-not-ready receipts.

필수 실행:

```sh
./tests/test.sh self
./tests/test.sh docs
./tests/test.sh fixtures
./tests/test.sh expect-fail stale-catalog-doc
./tests/test.sh expect-fail fixture-without-golden
./tests/test.sh core-readiness
./tests/test.sh expect-fail core-not-ready
```

중단: unrelated missing tool이 selector를 막거나 exit 70/zero-case/stale receipt를 PASS로 바꾸면 중단.

### G3 — offline deterministic vertical slice

이 단계가 첫 제품 성공 단위 `VERTICAL_SLICE_PASS`다.

최소 산출:

1. minimal trace schema/validator.
2. 한 React/business input에서 convention fact 1개와 business fact 1개.
3. 직접 `path:line`과 source hash/quote anchor.
4. AS-IS UI projection 1개.
5. 사람이 승인한 change request와 binding.
6. TO-BE UI projection 1개.
7. normalized repeat hash와 receipt.

필수 mutation:

- missing/duplicate stable ID.
- stale anchor.
- invented fact/glossary.
- hidden conflict.
- binding violation.
- output/symlink escape.
- corrupted golden.
- PASS text + nonzero exit.
- reused stale approval.

사람 gate: evidence accuracy와 AS-IS 승인 → bounded change 승인 → TO-BE 승인.

중단: undocumented manual edit, inferred requirement promotion, hidden ambiguity가 필요하면 `UNKNOWN`/`conflict`로 남기고 가장 작은 실패 layer로 돌아간다.

### G4 — minimal isolated OpenCode와 model admission

G3 이후에만 진행한다.

MVP subset:

- 2 agents.
- 가치 경로에 필요한 6 commands만: analyze, analyze-business, document-asis, change-design, deliver, verify.
- 필요한 evidence/stack/convention/business/change/UI skills만.

OpenCode gate:

- exact `v1.18.3`/commit `127bdb3`.
- disposable HOME/XDG, neutral CWD.
- hostile global/project canary가 inherited surface 0임을 증명.
- nested command ID, skill collision, AGENTS order, explicit permission, child session/resume probe.
- source/global config before/after hash 동일.

모델 gate:

- credential/cost 사용은 별도 사용자 승인.
- alias discovery/load와 actual response/tool/stream/structured output을 분리.
- exact Ollama version/digest/`num_ctx` 기록.
- 20/20 single-tool, 10/10 multi-step, 20/20 strict-schema를 후보 admission 기준으로 사용하고 raw XML, phantom tool, parser error, fallback을 0으로 요구.

중단: permission bypass, evidence fabrication, global mutation, unbounded loop가 하나라도 있으면 model `UNVERIFIED` 유지.

### G5 — real brownfield thin UAT

사용자가 고른 non-fixture repo의 pinned revision과 bounded change request를 사용한다.

측정:

- sampled evidence anchor validity.
- critical invented fact 0.
- UNKNOWN/ambiguous/conflict 보존.
- human correction log와 active labor.
- AS-IS usefulness 승인.
- TO-BE fitness 승인.
- 두 번째 prospective use 의향이 아니라 실제 재사용 관찰.

고정 percentage threshold를 사후에 만들지 않는다. case selection, criticality, claim splitting, evaluator, comparator를 pilot 전에 고정한다. pilot 결과는 다음 투자 decision memo이지 일반화된 제품 성공률이 아니다.

중단: user reject면 기능을 더 추가하지 않는다. 가장 작은 실패 contract/skill로 돌아간다.

### G6 — full expansion, release, Windows receipt

G5의 `REAL_REPO_UAT_ACCEPTED` 뒤에만 exact 2 agents/9 commands/15 skills, AS-IS 4종, TO-BE 5종, run/resume/status, packaging을 확장한다.

검증:

- full happy/adversarial/mutation suite.
- isolated exact-set load.
- fresh-process resume와 same-mission contention.
- reproducible archive hash.
- source/global/secret mutation 0.

그 뒤에만 `LOCAL_IMPLEMENTATION_PASS`를 선언한다. Windows는 current release fingerprint로 사용자가 실행하는 final receipt다. Windows failure는 local PASS를 지우지 않지만 cross-platform success를 금지한다.

## 8. OpenCode와 모델에 관한 현재 공식 결론

OpenCode `v1.18.3`은 2026-07-16 release commit `127bdb30784d508cc556c71a0f32b508a3061517`이다.

- `OPENCODE_CONFIG_DIR`는 isolation이 아니라 overlay다.
- nested command path는 `sensai/foo`로 보존된다.
- official rolling docs의 Scout는 pinned runtime에 존재하지 않는다.
- `.env` default는 docs의 deny가 아니라 tagged source의 ask다.
- Plan은 ordinary edit를 deny하지만 Bash는 inherited allow이므로 이름만으로 read-only가 아니다.
- skill runtime validation은 rolling docs보다 느슨하며 duplicate name이 override될 수 있다.
- permission은 sandbox가 아니다. [OpenCode security policy](https://github.com/anomalyco/opencode/security)는 OS isolation에 container/VM이 필요하다고 명시한다.
- native Windows build target은 있지만 tagged PTY test 일부가 win32에서 skip되므로 parity proof가 아니다.

Qwen/Ollama:

- exact `Qwen/Qwen3.5-9B`와 Ollama `qwen3.5:9b`는 존재한다.
- provider shape `@ai-sdk/openai-compatible` + `http://localhost:11434/v1`는 official docs와 맞다.
- exact Qwen3.5/Ollama/OpenCode tool XML leak가 실제 released Ollama에서 있었고 v0.19.0에 특정 fix가 들어갔다.
- structured JSON + non-thinking regression도 별도로 있었다.
- model card 256K와 actual allocated context는 다르다.
- 이 host에는 `opencode`와 `ollama`가 없어 current tuple은 계속 `MODEL_ADMISSION=UNVERIFIED`다.

## 9. 최종 추천

즉시 해야 할 일:

1. 7-category enum과 payload 용어를 source-owned decision으로 닫는다.
2. source manifest fingerprint와 local-context fingerprint를 분리한다.
3. `docs`와 local plan reconciliation selector를 분리한다.
4. preflight를 selector-scoped로 바꾸고 current receipt를 다시 만든다.
5. semantic validator가 adversarial fixture를 실제로 reject하도록 만든다.
6. active plan을 G1→G3→G5 가치 순서로 재배치한다.

아직 하지 말 것:

- full 2/9/15 catalog 구현.
- Node/TS/Go/plugin/MCP/custom tool.
- dashboard/TUI/queue/team orchestration.
- offline release bundle 확대.
- global OpenCode config 수정.
- 승인 없는 live model call.
- Windows proof를 macOS verifier로 대체.

성공의 한 문장 정의:

> pinned real legacy repository에서 직접 근거와 explicit uncertainty를 가진 AS-IS를 만들고, 사람이 승인한 change를 같은 trace에서 TO-BE로 투영하며, independent validator와 human review가 이를 재현 가능하게 승인할 때 wonder-sensai2의 핵심 가치가 성공한 것이다.

## 주요 로컬 근거

### wonder-sensai2

- `README.md:3-17,71-112`
- `docs/PROD.md:13-93`
- `docs/harness/contract-freeze.md:3-41`
- `docs/harness/runtime-contract.md:3-55`
- `docs/harness/verification-contract.md:18-59`
- `tests/test.sh:93-123`
- `tests/lib/tooling.sh:54-120`
- `tests/cases/docs.sh:49-103,240-343,575-660`
- `tests/cases/fixtures.sh:145-339,423-537`
- `fixtures/expected/trace-v2.json:14-51`

### Tiny-Chu

- `../Tiny-Chu/README.md:1-5,214-261`
- `../Tiny-Chu/src/opencode/small-model-contribution.ts:237-242`
- `../Tiny-Chu/docs/reports/small-model-contribution-evaluation.md:55-69`
- `../Tiny-Chu/test/module-registry.test.mjs:123-173`
- `../Tiny-Chu/src/opencode/registry-adapter.ts:7,70-89`
- `../Tiny-Chu/scripts/release/npm-runner.mjs:31-109`

### Tiny-Yeah

- `../Tiny-Yeah/src/core/composer/default-packages.ts:1-76`
- `../Tiny-Yeah/src/head/opencode/plugin.ts:40-48,74-123`
- `../Tiny-Yeah/scripts/release/verify-offline-bundle/bundle-checks.mjs:238-294`
- `../Tiny-Yeah/bin/tiny-yeah.js:619-648`
- `../Tiny-Yeah/tests/unit/head/opencode/tui-plugin.test.ts:3-40`

### opencode-legacy-kit

- `../opencode-legacy-kit/docs/PROJECT.md:3-74`
- `../opencode-legacy-kit/docs/INSTALL.md:5-200`
- `../opencode-legacy-kit/tests/portable-kit.test.mjs:98-265`
- committed v1: `0ffef9d`
- current v2 diff: `+809/-7,805`

## 주요 외부 근거

### OpenCode

- [OpenCode v1.18.3 release](https://github.com/anomalyco/opencode/releases/tag/v1.18.3)
- [Pinned config implementation](https://github.com/anomalyco/opencode/blob/127bdb30784d508cc556c71a0f32b508a3061517/packages/opencode/src/config/config.ts#L351-L550)
- [Pinned command discovery](https://github.com/anomalyco/opencode/blob/127bdb30784d508cc556c71a0f32b508a3061517/packages/opencode/src/config/command.ts#L13-L38)
- [Pinned instruction loading](https://github.com/anomalyco/opencode/blob/127bdb30784d508cc556c71a0f32b508a3061517/packages/opencode/src/session/instruction.ts#L110-L220)
- [Pinned task depth/resume](https://github.com/anomalyco/opencode/blob/127bdb30784d508cc556c71a0f32b508a3061517/packages/opencode/src/tool/task.ts#L104-L170)
- [Official security boundary](https://github.com/anomalyco/opencode/security)
- [Official skills docs](https://opencode.ai/docs/skills/)
- [Official providers docs](https://opencode.ai/docs/providers/)

### Qwen/Ollama

- [Qwen3.5-9B model card](https://huggingface.co/Qwen/Qwen3.5-9B)
- [Ollama qwen3.5:9b Q4_K_M](https://ollama.com/library/qwen3.5:9b-q4_K_M)
- [Ollama tool-call regression #14745](https://github.com/ollama/ollama/issues/14745)
- [Ollama fix #15022](https://github.com/ollama/ollama/pull/15022)
- [Ollama structured-output regression #14645](https://github.com/ollama/ollama/issues/14645)
- [Ollama structured-output fix #15901](https://github.com/ollama/ollama/pull/15901)
- [Ollama context guidance](https://docs.ollama.com/context-length)

### provenance와 검증

- [W3C PROV-DM](https://www.w3.org/TR/2013/REC-prov-dm-20130430/)
- [W3C Web Annotation](https://www.w3.org/TR/2017/REC-annotation-model-20170223/)
- [RFC 9110 strong validators](https://www.rfc-editor.org/rfc/rfc9110.html)
- [SQLite atomic commit](https://sqlite.org/atomiccommit.html)
- [SLSA provenance](https://slsa.dev/spec/v1.1/provenance)
- [in-toto specification](https://github.com/in-toto/specification/blob/v1.0/in-toto-spec.md)
- [Inspect AI eval logs](https://inspect.aisi.org.uk/eval-logs.html)
- [Inspect AI checkpointing](https://inspect.aisi.org.uk/checkpointing.html)

## 남은 미확인 사항

- sibling pivot의 직접적인 owner/user 결정 이유.
- 실제 private adoption, downloads, repeated use.
- Tiny-Chu 20–40 versus 79/99 tool live Qwen 비교.
- exact OpenCode/Qwen/Ollama admission on target host.
- native Windows 10/PowerShell 7.6 receipt.
- 실제 brownfield user-value pilot.

이 항목은 더 많은 문서 검색으로 닫히지 않는다. 각각 owner record, target host execution, 또는 prospective user pilot이 필요하다.
