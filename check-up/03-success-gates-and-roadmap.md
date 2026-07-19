# 성공 게이트와 로드맵

## 운영 원칙

- 현재 전체 빌드는 NO-GO다. 다음 stage를 통과하기 전 뒤 stage를 구현하지 않는다.
- 숫자 threshold는 모두 **calibration**이다. 3-user pilot은 방향성 근거이지 통계적 일반화가 아니다.
- 동일 gate가 원인 수정 후 두 번 실패하면 해당 접근을 `KILL` 또는 `PIVOT`한다.
- owner가 비어 있는 gate는 시작하지 않는다.

## Stage gates

| Gate | 범위·owner | 통과 metric (calibration) | kill/pivot 기준 |
| --- | --- | --- | --- |
| G0 문제/채택 | Product owner | 3명/3 repo, `>=2/3` 재사용 의향, accepted decision까지 active human time `>=30%` 단축 | 같은 gate 2회 실패 또는 사용자가 결과를 기존 방식보다 선호하지 않음 |
| G1 F1 concierge 품질 | Evidence lead | atomic claim entailment `>=95%`, critical precision/recall `100%`, correction rate `<=20%`, critical fabrication `0` | critical fabrication 1건 또는 재검 후 critical recall 누락 |
| G2 evidence kernel | Runtime owner | frozen digest/span, schema+semantic mutation 전부 검출, invalid/extra/symlink/stale receipt 0 false-pass | shape-only false-green 재발 |
| G3 `M0_UI_PROOF` | Projection owner | 1 UI projection, semantic provenance, render, blind gold 일치 | render만 통과하고 claim 품질 gate 실패 |
| G4 OpenCode shell | Harness owner | disposable HOME/XDG/neutral CWD, exact 2/9/15 resolved, inherited surface 0, source/global hash 불변 | config inheritance/hidden extra 또는 source mutation |
| G5 F0-F5 state machine | Mission owner | F0/F3/F5/violation receipt, CAS single writer, interrupt/resume/stale/corrupt/double-writer tests | gate bypass·partial write·stale approval 수용 |
| G6 model admission | Model owner | exact tuple의 response/stream/JSON/single+multi tool call, argument accuracy·critical evidence gate 통과 | 두 admission run 연속 미달; deterministic fallback 없이 필수 경로화 |
| G7 release | Release owner | manifest/install/archive checksum, local preflight, cleanup, rollback | payload drift·unclean environment·non-reproducible archive |
| G8 Windows | Windows user + release owner | current release/kit hash, native OS/PS/OpenCode/tool identities, full receipt | WSL/static 검사로 대체하거나 Windows 10 lifecycle 조건 불명 |

## 권장 순서

### Phase A — 10영업일, 제품 가치 확인

G0/G1 concierge pilot만 수행한다. runtime catalog, peer, installer, Windows는 제외한다. 결과는 [04-concierge-pilot.md](04-concierge-pilot.md)에 따라 측정한다.

### Phase B — evidence kernel

pilot이 통과했을 때만 schema와 validator를 구현한다. 먼저 evidence/claim/receipt/fingerprint 최소 schema와 semantic mutations를 만든다. [verification-contract.md:18-28](../docs/harness/verification-contract.md#L18-L28)의 failing-first 원칙을 적용하고, 현재 presence-only `core-readiness`도 semantic readiness로 교체한다.

### Phase C — 한 경로 자동화

`M0_UI_PROOF`를 구현한다. 이 이름으로 canonical F3와 혼동을 없앤다. deterministic extraction → atomic claims → semantic verifier → UI projection → render 한 경로만 만든다. G2/G3 통과 전 새 skill을 추가하지 않는다.

### Phase D — OpenCode와 mission runtime

OpenCode는 shell로 붙이고 독립 CLI가 path, exact-set, CAS, receipt를 강제한다. 이후에만 F0-F5와 mission continuity를 구현한다. F1/F2 worker는 read-only 결과만 반환하고 lead serial merge가 canonical state를 쓴다.

### Phase E — model, packaging, platform

deterministic core가 먼저 green일 때 exact model/runtime tuple을 admission한다. model 실패가 provenance/validator를 우회하지 못하게 한다. local package가 current fingerprint로 통과한 뒤 Windows native receipt를 받는다.

## 최소 owner 정의

- Product owner: 대상 사용자·업무·중단 판단 소유.
- Evidence lead: atomic gold, entailment, criticality, blind review 소유.
- Runtime owner: schema, validator, receipt, CAS, false-green 방지 소유.
- Harness owner: OpenCode exact-set·permission·isolation 소유.
- Release owner: manifest, install, archive, platform receipt 소유.

한 사람이 여러 역할을 맡을 수 있지만 각 gate의 승인자와 구현자는 가능한 한 분리한다.

## 전체 빌드 재개 조건

다음을 모두 만족하기 전 2/9/15 전체 exact-set을 목표로 삼지 않는다.

1. G0/G1 통과 및 사용자 2명 이상 재사용.
2. critical fabrication 0, semantic provenance gate green.
3. 자동화가 concierge 대비 추가로 시간을 절감한다는 증거.
4. OpenCode를 제거해도 evidence kernel과 mission state가 독립 실행됨.
5. model/Windows 상태를 local deterministic PASS와 분리해 보고함.
