# CodeGraph 하이브리드 분석 가이드

## 목적과 권위

이 문서는 F1 기술 분석과 F2 비즈니스 분석에서 CodeGraph를 안전하게 조합하는 실전 매뉴얼이다. CodeGraph는 관계 후보를 좁히는 도구이며 source, canonical `trace.json`, schema, validator를 대체하지 않는다. 파일 집합은 `fd`, 직접 문자열과 `path:line`은 `rg`, AST shape는 `sg`, 관계 후보는 CodeGraph, 실제 동작은 가장 작은 runtime scenario가 각각 소유한다.

여러 도구를 조합하는 이유는 도구마다 실패 방식이 다르기 때문이다. graph가 caller edge를 반환해도 index가 오래됐을 수 있고, `rg` hit가 있어도 comment일 수 있으며, AST match가 있어도 runtime에서 실행되지 않을 수 있다. 질문의 결론을 바꿀 수 있는 사각지대가 있을 때만 다른 failure mode의 도구를 더한다. 모든 도구를 의례적으로 순회하지 않는다.

이 문서는 source-owned 문서만 참조한다. ignored `plan/`이나 로컬 `STATUS.md`가 없어도 운용할 수 있다.

CodeGraph는 확장 입학 게이트의 optional candidate lane이다. 현재 `CODEGRAPH_ADMISSION=NOT_ADMITTED`이며 후보 평가 기록은 `REQUIRED_TO_EVALUATE`에서 시작한다. 이 가이드는 후보를 평가하는 절차이지 default·required 분석 경로나 입학 완료 기능의 사용 설명서가 아니다. 5개 확장 gate와 사람 승인을 모두 통과하기 전에는 route-level status PASS나 permission을 제품 admission으로 해석하지 않는다.

## 고정 원칙

1. 모든 graph route는 CLI의 정확한 `codegraph status . --json`으로 repo scope와 freshness admission을 먼저 통과한다.
2. package는 MCP나 CodeGraph server/index를 설치·수정하지 않는다. MCP permission은 unknown `codegraph_*`를 deny하고 exact `codegraph_explore`만 `ask`한다. 사용자가 command 기반 MCP를 구성하고 CLI status admission 뒤 이 요청을 승인한 경우에만 후보 평가에서 MCP를 primary explore route로 사용한다.
3. catalog가 없거나 exact ask가 승인되지 않거나 MCP가 usable response 전에 `timeout`, `deny`, `transport_error`로 실패하면 같은 frozen packet으로 승인된 read-only CLI에 정확히 한 번 failover한다.
4. 한국어 원문은 보존하되 direct source에서 English term과 symbol/file anchor를 확인하고 byte·count cap을 검사한 뒤 첫 graph query 전에 packet을 freeze한다.
5. query, MCP, CLI는 같은 packet만 사용한다. graph 결과로 query, scope나 anchor를 정제하지 않는다.
6. graph 결과는 candidate다. lead가 current source의 direct `path:line`을 다시 확인해야 evidence 후보가 된다.
7. 하네스는 CodeGraph MCP, index나 server를 설치·생성·갱신·동기화·제거하지 않는다.
8. F3와 F4에서는 새 graph discovery나 graph 호출을 실행하지 않는다.

## 1. 질문에 맞는 첫 도구 선택

| 도구 | 책임과 coverage | 장점 | 단점·겹치는 영역 | 중단 조건 |
| --- | --- | --- | --- | --- |
| `fd` | repo 안 file set, 확장자, 디렉터리, ignore 적용 범위 | index 없이 빠르고 file inventory가 명확하다. | content·AST·relation·runtime은 알 수 없다. `rg`, `sg`, CodeGraph의 실제 corpus 범위와 겹친다. | 질문에 필요한 repo-relative file set과 누락 여부가 확정되면 중단한다. |
| `rg` | literal, identifier, config key, 문서와 source의 direct `path:line` | 현재 worktree를 직접 읽어 stale index가 없다. | comment·string·generated source를 실제 구문과 구분하지 못한다. `sg`의 syntax와 CodeGraph의 identifier를 교차 확인한다. | 주장을 직접 지지하거나 반박하는 줄과 scope를 확보하면 중단한다. |
| `sg` | 지원 언어의 declaration, call, AST shape | formatting과 comment에 덜 민감하다. | parser/grammar 밖 파일, cross-file resolution, runtime은 보지 못한다. `fd`의 scan coverage와 `rg` lexical hit를 교차 확인한다. | scanned/skipped 범위와 bounded AST match set이 확정되면 중단한다. |
| CodeGraph | verified symbol/file의 caller, callee, flow, impact 후보 | cross-file 후보를 작은 source set으로 줄인다. | wrong-scope·stale index와 heuristic edge가 가능하다. `fd` scope, `rg` freshness, `sg` syntax와 겹친다. | admission 뒤 별도 call·file·numeric·consumption cap 안의 relation candidate를 얻으면 중단한다. |
| runtime | build, test, CLI의 observable exit·output·mutation | 실행 여부와 실제 결과를 관찰한다. | 환경·입력·toolchain drift가 있고 원인을 단독 설명하지 못한다. static tool의 설명과 교차한다. | 같은 fingerprint의 exact scenario, exit와 receipt를 확보하면 중단한다. |

첫 도구는 file-set 질문에 `fd`, lexical 질문에 `rg`, structural 질문에 `sg`, relational 질문에 admission된 CodeGraph, behavioral 질문에 최소 runtime scenario를 선택한다. 이미 파일과 줄이 알려진 저위험 질문은 direct read 하나로 끝낸다. 이 선택은 비용을 줄이면서도 필요한 coverage를 잃지 않기 위한 것이다.

## 2. CodeGraph pre-query admission

### 2.1 대상 root 고정

미션이 승인한 대상 저장소의 canonical real path를 먼저 고정한다. `status.projectPath`를 단순 basename이나 parent path와 비교하지 않는다. parent workspace index가 그럴듯한 sibling 결과를 반환할 수 있으므로 exact real path 비교가 필요하다.

### 2.2 status 실행

대상 저장소 root에서 다음 명령을 다른 모든 graph 명령보다 먼저 정확히 한 번 실행한다.

```sh
codegraph status . --json
```

PASS는 다음 조건을 모두 만족할 때뿐이다.

| 필드 | PASS 조건 | 실패 상태 |
| --- | --- | --- |
| `initialized` | boolean `true` | `unsupported` |
| `projectPath` | canonical target real path와 exact match | `out_of_scope` |
| `pendingChanges.added` | nonnegative integer `0` | non-integer/negative는 `unsupported`, 양수는 `stale_graph` |
| `pendingChanges.modified` | nonnegative integer `0` | non-integer/negative는 `unsupported`, 양수는 `stale_graph` |
| `pendingChanges.removed` | nonnegative integer `0` | non-integer/negative는 `unsupported`, 양수는 `stale_graph` |
| `worktreeMismatch` | `null` | `stale_graph` |
| `index.reindexRecommended` | boolean `false` | `stale_graph` |

예를 들어 다음 status는 필드가 모두 있어도 `initialized:false`이므로 `unsupported`다.

```json
{
  "initialized": false,
  "projectPath": "/approved/repo",
  "pendingChanges": {"added": 0, "modified": 0, "removed": 0},
  "worktreeMismatch": null,
  "index": {"reindexRecommended": false}
}
```

이 경우 `query`, `explore`, `node`, `callers`, `impact`를 포함한 graph call은 0회다. MCP catalog나 exact permission ask가 보여도 우회하지 않는다.

JSON이 malformed이거나 required field/type이 없으면 `unsupported`다. built/current version field가 둘 다 존재하고 값이 다르면 `stale_graph`다. optional version field가 없으면 required field만으로 admission하되 `freshness_partial` warning을 남기고 결과를 candidate로만 다룬다.

CLI 자체가 없으면 catalog 존재와 무관하게 `unsupported`로 기록하고 status를 포함한 graph call을 0회로 유지한다. MCP-only로 scope/freshness를 독립 증명하지 못하기 때문이다.

admission 실패 뒤에는 `query`, `explore`, `node`, `callers`, `impact`를 실행하지 않는다. `rg` 또는 `sg`로 현재 source를 조사한다. stale index를 자동 수리하면 읽기 전용 분석이 외부 상태 mutation으로 바뀌므로 하네스는 다음 명령을 실행하지 않는다.

- `codegraph init`
- `codegraph index`
- `codegraph sync`
- `codegraph serve`
- `codegraph uninit`
- `codegraph install`
- `codegraph upgrade`

index 변경이 필요하면 사용자가 분석 세션 밖에서 별도로 승인·수행한 뒤 새 `status` admission부터 다시 시작한다.

## 3. 한국어 의도를 English verified-anchor query로 정제

사용자가 한국어 graph query 실패를 관찰했으므로 이 전략은 한국어 query를 operationally `invalid_query_en`으로 거부한다. 이는 현재 별도 회귀 test가 존재한다는 주장이 아니다. 작은 모델이 한국어 의미를 identifier처럼 번역하면 존재하지 않는 symbol을 발명할 위험도 있으므로 원문은 `original_ko`에 그대로 보존하고 query 준비는 direct source에서만 수행한다.

예를 들어 사용자 의도가 “설치 충돌 흐름”이라면 먼저 current source에서 English term과 identifier 후보를 찾는다.

```sh
fd -t f . cmd/sensai
rg -n --no-config 'install|conflict' cmd/sensai
sg --lang go --pattern 'func (transaction *installTransaction) classify() (packageClassification, error) { $$$BODY }' cmd/sensai/package_install_transaction.go
```

이 결과로 `install`, `conflict`는 topical term, `installTransaction.classify`와 `cmd/sensai/package_install_transaction.go`는 direct source 확인 뒤 verified anchor 후보가 된다. `InstallStage`, `ConfigLoader`, `checkConflict`처럼 source에 없는 번역형 이름은 만들지 않는다.

### 3.1 keyword refinement 예시

| 단계 | 값 | 이유 |
| --- | --- | --- |
| 원문 | `설치 충돌 흐름` | 사용자 의도를 잃지 않도록 그대로 보존한다. |
| 넓은 English term | `install`, `conflict` | 먼저 주제 recall을 확보한다. |
| direct source anchor | `installTransaction.classify`, `cmd/sensai/package_install_transaction.go` | 실제 identifier와 scope로 false positive를 줄인다. |
| 첫 query | `install conflict` | source에서 검증된 English term만 사용한다. |
| freeze 전 정제 | current source에서 확인된 symbol/file을 anchor로 추가 | graph 결과가 아니라 direct source로 packet을 완성한다. |
| cap 검증 | query 120 ASCII bytes, symbol 160 bytes, path 240 bytes와 count cap | 첫 query 전에 oversize·과다 입력을 거부한다. |
| freeze | 완성한 one-subject·one-scope packet | 이후 query, MCP, CLI에서 한 바이트도 바꾸지 않는다. |

### 3.2 frozen packet

graph query 전에 one-subject·one-scope packet을 만든다. English term은 `2-4`개, verified symbol은 `1-6`개, verified file은 `0-4`개, Pass 2 source file은 최대 `8`개다. required field/type이 없거나 입력 shape가 malformed이면 입력을 폐기하고 `unsupported`로 중단한다. `query_en`은 ASCII 최대 120바이트, symbol은 각각 최대 160바이트, repo-relative path는 각각 최대 240바이트다. byte·count cap을 하나라도 넘으면 입력을 폐기하고 `ambiguous`로 중단한다. 두 입력 실패 모두 retry하지 않는다.

```json
{
  "original_ko": "설치 충돌 흐름",
  "intent": "technical relation",
  "scope_prefix": "cmd/sensai",
  "topical_terms_en": ["install", "conflict"],
  "framework_terms_en": [],
  "verified_symbols": ["installTransaction.classify"],
  "verified_files": ["cmd/sensai/package_install_transaction.go"],
  "flow": "install entry to managed conflict guard",
  "query_en": "install conflict",
  "route": {"primary": "mcp", "fallback": "cli"},
  "result_state": "ready",
  "recheck_required": true
}
```

cap 검증이 끝난 packet을 유일한 graph query 직전에 freeze한다. query, MCP explore, CLI failover 직전의 canonical packet hash는 모두 같아야 한다. graph가 반환한 name/path는 candidate와 direct-source 재확인 대상으로만 쓰고 packet 정제에는 사용하지 않는다. 어느 단계에서든 hash가 달라지면 `ambiguous`로 중단한다. 실패 뒤 질문을 슬쩍 넓혀 다른 답을 받는 route drift를 막기 위한 규칙이다. packet과 raw graph dump는 ephemeral 비교 자료이며 canonical trace property로 추가하지 않는다.

## 4. primary MCP와 CLI failover

### 4.1 query와 MCP primary

route-level admission 뒤 frozen `query_en`으로 query를 정확히 1회 실행한다. 0회는 근거 없는 explore, 2회 이상은 독립 목적 없는 반복이므로 `ambiguous`다. 결과의 name/path는 candidate로만 보관한다.

unknown `codegraph_*` MCP는 deny한다. status admission을 통과하고 사용자 설정의 command 기반 MCP catalog에서 exact `codegraph_explore`가 발견되며 `ask`가 승인된 경우에만 frozen packet으로 MCP explore를 한 번 실행한다. package는 이 MCP를 설치·수정하지 않는다. MCP가 성공하면 CLI explore는 실행하지 않는다. MCP는 전송 편의와 structured tool surface를 제공하지만 별도 사실 권위는 아니기 때문이다.

### 4.2 같은 packet으로 CLI failover

catalog가 없거나 exact ask가 승인되지 않거나 MCP가 usable response 전에 `timeout`, `deny`, `transport_error`로 끝나면 원래 packet, scope, `query_en`, verified anchor를 바꾸지 않고 CLI explore를 정확히 한 번 실행한다. 같은 질문의 transport만 바꿔 두 결과를 비교 가능하게 유지하기 위해서다.

usable response를 받은 뒤의 실패는 transport failover가 아니다.

| 결과 | 판정과 다음 행동 |
| --- | --- |
| MCP usable response 전 `timeout`, `deny`, `transport_error` | 동일 packet으로 CLI explore 1회 |
| MCP response가 schema-invalid 또는 `malformed` | 전체 폐기, `unsupported`, CLI failover·retry·merge 금지 |
| MCP raw response가 65536바이트 초과 | 전체 폐기, `ambiguous`, CLI failover·retry·merge 금지 |
| CLI response가 schema-invalid 또는 `malformed` | 전체 폐기, `unsupported`, retry·merge 금지 |
| CLI raw response가 65536바이트 초과 | 전체 폐기, `ambiguous`, retry·merge 금지 |

persistent read-only permission이 대상으로 삼는 CLI command shape 예시는 다음과 같다. lead/skill은 각 명령을 별도로 실행하며 pipe, redirect, command substitution, 추가 flag를 붙이지 않는다. 이는 behavioral budget이며 아래 glob만으로 강제되는 security boundary가 아니다.

```sh
codegraph query --path . --limit 5 --json 'install conflict'
codegraph explore --path . --max-files 5 'install conflict'
codegraph node --path . 'installTransaction.classify'
codegraph callers --path . --limit 10 --json 'installTransaction.classify'
codegraph impact --path . --depth 2 --json 'installTransaction.classify'
```

각 command의 allow pattern은 다음 argv shape와 numeric flag 범위를 대상으로 한다.

- `query`: `--path .`, `--limit 1..10`, `--json`, single-quoted query 하나
- `explore`: `--path .`, `--max-files 1..8`, single-quoted query 하나
- `node`: `--path .`, single-quoted verified symbol 하나
- `callers`: `--path .`, `--limit 1..20`, `--json`, single-quoted verified symbol 하나
- `impact`: `--path .`, `--depth 1..3`, `--json`, single-quoted verified symbol 하나

OpenCode `1.18.3`은 shell AST의 각 command를 독립적으로 permission 평가한다. 따라서 이 glob은 각 command의 argv shape·numeric flag와 기존 secret·redirect 방어를 투영하지만, 개별 허용 command를 `|`, `;`, `&&`, `||`, `&`로 조합하는 일이나 per-turn·per-mission call count를 기계적으로 막지 못한다. persistent read-only permission은 capability projection일 뿐 CodeGraph extension admission이나 OS sandbox가 아니다. 각 명령 별도 실행, pipe 금지, query 최대 1회는 lead/skill behavioral budget이다. 이를 기계적으로 강제하려면 CodeGraph bash pattern을 `ask`/`deny`로 바꾸거나 외부 sandbox/wrapper를 사용해야 하지만 현재 package는 이를 설치하지 않는다.

permission glob은 query·symbol·path byte나 raw response 크기도 강제하지 않는다. lead의 별도 consumption gate는 MCP와 CLI raw response를 최대 65536바이트까지만 소비한다. schema-invalid·`malformed` response는 `unsupported`, 초과 response는 `ambiguous`로 전체 폐기한다. 잘라낸 일부를 근거로 사용하거나 다른 transport로 failover하거나 retry·merge하지 않는다.

focused operation은 `node`, `callers`, `impact` 중 하나만 한 번 실행한다. query 최대 1회, MCP 1회, CLI explore 1회, focused 1회, source file 최대 8개와 입력·응답 consumption cap을 각각 적용한다. 어느 cap이든 소진되거나 모호하면 추가 호출하지 않고 `ambiguous`로 끝낸다. 이는 서로 분리된 call·file·numeric·consumption 제한이며 단일 permission glob이 모두를 보장한다는 뜻이 아니다.

## 5. direct source 재확인과 교차 검증

graph candidate를 받으면 lead가 현재 worktree에서 정확한 source 줄을 한 번 다시 확인한다.

```sh
rg -n --no-config 'func \(transaction \*installTransaction\) classify' cmd/sensai/package_install_transaction.go
```

graph path, symbol과 direct source가 일치해야 `lead_recheck=true`와 `comparison_state=consistent` 후보가 된다. line number는 문서에 고정 복사하지 않고 실행 시점 결과를 receipt에 기록한다. source edit로 줄이 이동해도 stale 문서가 사실처럼 남지 않게 하기 위해서다.

| 조합 | 추가할 때 | 확인하는 gap | 생략할 때 |
| --- | --- | --- | --- |
| `fd` + `rg` | inventory completeness가 lexical 결론에 영향 | ignore·file-set drift | known file 한 개의 exact 줄 질문 |
| `fd` + `sg` | AST 0건을 전체 부재로 해석하기 전 | parser scan/skip coverage | known file의 bounded shape |
| `fd` + CodeGraph | parent index나 missing file 의심 | graph scope·corpus freshness | direct read로 끝나는 질문 |
| `rg` + `sg` | lexical hit가 실제 node인지 중요 | comment/string 대 AST | 문서·JSON·shell text |
| `rg` + CodeGraph | graph identifier와 current source 비교 | stale edge·renamed symbol | relation이 필요 없는 direct claim |
| `sg` + CodeGraph | resolved edge와 실제 syntax가 모두 중요 | heuristic edge 대 AST shape | single-file AST-only 질문 |
| CodeGraph + runtime | exit, write, security, public behavior 주장 | graph hypothesis 대 observable behavior | relation 후보만 보고할 때 |

저위험 주장은 direct evidence 하나가 충분하면 종료한다. 중위험 주장은 결론을 바꿀 gap이 있을 때 다른 failure mode 하나를 더한다. 고위험 또는 behavioral 주장은 서로 다른 static channel 둘 이상과 같은 fingerprint의 최소 runtime receipt가 있어야 확정한다.

## 6. F1/F2에서 F3/F4로 넘기는 경계

- F1은 기술 relation, F2는 선택한 domain document와 code business flow 비교에만 graph candidate를 사용한다.
- lead는 candidate마다 direct `path:line`을 다시 확인하고 canonical trace를 직렬 병합한다.
- F3는 검증된 F1/F2 원장만 AS-IS 4종으로 투영한다. 새 query, explore, `node`, `callers`, `impact`는 모두 금지한다.
- F4는 사람이 승인한 AS-IS 원장만 requirement와 binding 설계에 사용한다. 새 graph discovery와 graph 호출은 모두 금지한다.
- 대상 요소에 `unsupported`, `unresolved`, `ambiguous`, `conflict` 또는 document↔source disagreement가 남으면 F3/F4를 중단한다.

이 제한은 projection·design 단계에서 새로운 candidate가 조용히 canonical fact로 섞이는 것을 막고, 사람 승인이 어떤 exact 원장에 결합됐는지 보존한다.

## 7. 문제 해결

### `out_of_scope`

증상은 `projectPath`가 target canonical real path가 아니거나 sibling/parent 결과가 보이는 것이다. graph query를 실행하지 말고 repo-local `fd`, `rg`, `sg`로 fallback한다. 사용자가 올바른 index를 별도 준비하기 전에는 graph 결론을 채택하지 않는다.

### `stale_graph`

증상은 pending count 양수, `worktreeMismatch` non-null, `reindexRecommended=true`, version mismatch다. 현재 source와 graph 시점이 다르므로 graph call을 열지 않는다. 자동 index mutation은 금지하고 direct source 분석으로 완료하거나 사용자 갱신 뒤 새 admission을 시작한다.

### `unsupported`

증상은 CLI 부재, invalid status JSON, required field/type·값 누락, 빈 `query_en`, malformed 입력, `initialized=false`, usable MCP/CLI response의 schema-invalid·`malformed`다. MCP catalog가 있어도 readiness로 대체하지 않는다. usable response 이후 실패에는 다른 transport로 failover하거나 retry·merge하지 않고 `rg` 또는 `sg`가 소유한 direct/structural 질문으로 축소한다.

### `ambiguous`

증상은 한국어 query, invented symbol, 여러 scope, packet hash 변경, 입력 byte/count 또는 MCP/CLI raw response 65536바이트 초과, query 0회·2회 이상 또는 budget 소진 뒤 복수 후보다. 빈 query와 malformed 입력은 `unsupported`, cap 초과 입력은 `ambiguous`로 구분한다. 초과 response는 전체 폐기하고 failover·retry·merge하지 않는다. query를 더 반복하거나 graph 결과로 packet을 정제하지 않으며 verified anchor가 없으면 `UNKNOWN` 또는 `unresolved`로 남긴다.

### document↔source 또는 graph↔source disagreement

문서와 코드, graph와 current source가 다르면 어느 쪽도 자동 승자로 정하지 않는다. `document_only`, `code_only`, `runtime_only`, `ambiguous`, `conflict` 중 관찰 상태를 보존하고 양쪽 direct `path:line`을 기록한다. lead가 해소할 수 없으면 canonical merge와 F3/F4를 중단한다.

## 완료 체크리스트

- [ ] target canonical real path와 `codegraph status . --json` admission을 먼저 확인했다.
- [ ] `CODEGRAPH_ADMISSION=NOT_ADMITTED`와 `REQUIRED_TO_EVALUATE` 후보 상태를 제품 admission으로 과장하지 않았다.
- [ ] unknown `codegraph_*`는 deny하고 exact `codegraph_explore` ask가 승인된 경우만 MCP를 사용했다.
- [ ] 한국어 원문은 `original_ko`에 보존하고 direct source에서 English verified anchor를 준비했다.
- [ ] malformed 입력은 `unsupported`, cap 초과 입력은 `ambiguous`로 폐기하고 packet을 유일한 graph query 전에 freeze했다.
- [ ] frozen query를 정확히 1회만 실행했다.
- [ ] 각 명령 별도 실행, pipe 금지, query 1회가 behavioral budget이며 permission glob의 security boundary가 아님을 구분했다.
- [ ] query, MCP, CLI에서 같은 packet을 사용하고 graph 결과로 정제하지 않았다.
- [ ] usable response 전 `timeout`, `deny`, `transport_error`에서만 같은 packet으로 CLI에 한 번 failover했다.
- [ ] schema-invalid·`malformed` 또는 65536바이트 초과 MCP/CLI response를 폐기하고 failover·retry·merge하지 않았다.
- [ ] graph candidate의 current source `path:line`을 lead가 직접 재확인했다.
- [ ] 결론을 바꿀 gap에만 다른 failure mode의 도구를 추가했다.
- [ ] stale·scope mismatch·ambiguity·disagreement를 성공으로 덮지 않았다.
- [ ] index/server mutation 명령을 실행하지 않았다.
- [ ] F3/F4에서 새 graph 호출을 실행하지 않았다.
