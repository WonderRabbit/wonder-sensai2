# 현재 상태와 권위

## 권위 계층

이 프로젝트는 다음 순서로 사실을 판정해야 한다.

1. 현재 fingerprint에 결합된 executable schema·validator·runtime·receipt
2. [docs/PROD.md:91-93](../docs/PROD.md#L91-L93), [docs/harness/contract-freeze.md:30-37](../docs/harness/contract-freeze.md#L30-L37), runtime·verification·release 계약, [r4-mapping](../docs/r4-mapping.md#L1-L16)
3. source-owned 파생 상태
4. ignored `plan/prd/`와 `STATUS.md`

따라서 `plan/prd/`의 “완료”, “지원”, “성공 기준”은 **승인된 제품 의도**일 수는 있어도 구현 사실이 아니다. 반대로 source-owned 계약도 executable reality와 충돌하면 구현 실패다.

## 의도와 실제

| 축 | PRD 의도 | source-owned 권위 | 2026-07-19 실제 |
| --- | --- | --- | --- |
| 제품 | legacy AS-IS→TO-BE 하네스 | mission별 원장, single writer, hard gate | mission runtime 없음 |
| topology | 2 agents / 9 commands / 15 skills | exact-set target | `0 / 0 / 0` |
| 검증 | schema 2.0 + 5-mode provenance + render | local gate 전부 통과 필요 | schema/recipe/render runtime 없음 |
| 모델 | lead GLM + peer Qwen | alias는 load baseline일 뿐 | `opencode.json`만 있으며 admission 없음 |
| 플랫폼 | macOS local gate, Windows final receipt | cross-platform 비주장 | Windows kit/receipt 없음 |
| 배포 | manifest, stage, install, archive | literal payload와 checksum | manifest/CLI/installer 없음 |

현재 비주장은 [README.md:95-112](../README.md#L95-L112), [verification-contract.md:30-45](../docs/harness/verification-contract.md#L30-L45), [release-contract.md:26-40](../docs/harness/release-contract.md#L26-L40)에 맞는다. 다만 [implementation-status.md:27-35](../docs/harness/implementation-status.md#L27-L35)는 `tests/test.sh`와 fixture도 없다고 적어 현재보다 낡았다. 상태 문서는 current receipt에서 다시 생성해야 한다.

## 현재 파일 inventory

- 있음: source-owned 제품·runtime·verification·release 계약, 27개 planning PRD, `opencode.json`, root `fixtures/`, `tests/test.sh`와 cases/libs.
- 없음: `agents/`, `commands/`, `skills/`, `schemas/`, `recipes/`, `manifest.txt`, `bin/sensai`, mission 산출물.
- Git: `git rev-parse --verify HEAD` 실패. 모든 source 파일은 unborn/untracked 상태다. 따라서 tracked diff만으로 검증하면 안 된다는 [verification-contract.md:28](../docs/harness/verification-contract.md#L28)의 경고가 현재 적용된다.

## 현재 테스트 결과

`PATH=/opt/homebrew/bin:/usr/bin:/bin`으로 2026-07-19 재실행했다. 기본 login PATH에서는 `yq`를 찾지 못해 exit `70`이었으므로, tool identity와 resolved path를 receipt에 넣어야 한다.

| selector | exit | 결과 | 해석 |
| --- | ---: | --- | --- |
| `self` | 0 | 1 case / 30 assertions PASS | runner의 fail-closed·signal·stale evidence 동작 |
| `docs` | 0 | 1 / 185 PASS | 현재 문서 catalog/링크/상태 문자열 계약 |
| `fixtures` | 0 | 1 / 68 PASS | fixture inventory·hash·shape 계약 |
| `core-readiness` | 1 | 1 / 8, 7 fail | agents/commands/skills/schemas/recipes/manifest/bin 부재: **정상적인 RED** |
| `expect-fail core-not-ready` | 0 | 1 / 4 PASS | 위 RED가 이름 있는 assertion failure인지 확인 |
| `expect-fail fixture-without-golden` | 0 | 1 / 3 PASS | golden 누락 검출 |
| `expect-fail stale-catalog-doc` | 0 | 1 / 3 PASS | stale 문서 canary 검출 |

`docs`와 `fixtures`의 녹색은 제품 runtime 성공이 아니다. 둘은 각각 문서·fixture bootstrap의 녹색이다.

## false-green 증명

[tests/cases/core-readiness.sh:7-14](../tests/cases/core-readiness.sh#L7-L14)는 디렉터리와 일반 파일의 **존재만** 검사한다. 격리된 임시 root에 여섯 빈 디렉터리, 빈 비실행 `bin/sensai`, 빈 `manifest.txt`, invalid `opencode.json`, junk extra를 두어도 `core-readiness`는 exit 0이 됐다. 즉 현재 selector는 readiness가 아니라 surface-presence probe다.

수정 기준은 exact-set, executable bit, JSON/schema parse, manifest leaf/hash, banned extra/symlink, 최소 semantic invocation, nonzero case count까지 검사하는 것이다. 이 보강 전에는 `core-readiness=0`도 `LOCAL_IMPLEMENTATION_PASS`의 근거가 아니다.
