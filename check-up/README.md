# wonder-sensai 성공 가능성 점검

조사일: 2026-07-19
판정 기준: `plan/prd/*.md`의 제품 의도, source-owned 계약, 실제 파일·테스트, 공식 기술 문서

## 판정

| 범위 | 판정 | 이유 |
| --- | --- | --- |
| exact 2 agents / 9 commands / 15 skills 전체 빌드 | **NO-GO** | 제품 가치는 아직 실사용으로 검증되지 않았고, runtime 핵심은 0개 상태다. 전체 빌드는 검증되지 않은 수요와 기술 위험을 동시에 확대한다. |
| 10영업일 F1 기술분석 concierge pilot | **조건부 GO** | 설치형 제품을 만들지 않고 실제 유지보수 작업에서 시간 절감·근거 정확성·재사용 의향을 측정할 수 있다. |

지금 성공에 가장 필요한 것은 더 많은 카탈로그 구현이 아니라 **실제 사용자가 근거가 결합된 기술 분석을 다시 사용할지 검증하는 것**이다. pilot이 통과하기 전 F2 비즈니스 분석, 전체 F0-F5, peer 모델, installer, continuity, Windows 지원, 9/15 catalog 구현을 시작하지 않는다.

## 핵심 결론

1. `plan/prd/`는 **의도와 가설**이다. 실제 권위는 실행 가능한 schema/runtime/receipt, 그다음 source-owned 계약이다. 이 우선순위는 [제품 계약](../docs/PROD.md#L91-L93)과 [contract freeze](../docs/harness/contract-freeze.md#L30-L37)에 명시돼 있다.
2. 현재 checkout은 문서·fixture·fail-closed runner만 있다. `agents/`, `commands/`, `skills/`, `schemas/`, `recipes/`, `manifest.txt`, `bin/sensai`는 없고 Git `HEAD`도 없다. [README](../README.md#L3-L7)는 이를 구현 전이라고 정확히 경고한다.
3. 현재 `self`, `docs`, `fixtures`는 각각 30, 185, 68 assertions로 통과하지만 `core-readiness`는 8개 중 7개가 실패한다. 더 중요한 점은 [core-readiness 구현](../tests/cases/core-readiness.sh#L3-L18)이 경로 존재만 검사해 빈 파일·잘못된 JSON도 통과시키는 false-green이라는 것이다.
4. `path:line`과 ID 일치는 **주장이 원문에서 따라 나오는지**를 증명하지 않는다. `trace.json`은 truth 자체가 아니라 검증 가능한 claim/evidence ledger여야 한다.
5. `opencode.json`의 `small_model`은 peer agent를 만들지 않는다. OpenCode의 command/subtask, permission, todo, compaction도 mission DAG·single-writer·복구를 자체 보장하지 않으므로 결정적 CLI와 receipt가 필요하다.
6. Qwen 모델명과 provider 설정은 admission이 아니다. 현재 canonical lead는 GLM이고 Qwen3.6/vLLM 경로는 보류한다. Windows는 native receipt 전까지 미지원이며, Windows 10 일반 지원은 이미 종료됐다.

## 문서 묶음

- [01-current-state-and-authority.md](01-current-state-and-authority.md) — 권위 계층, 실제 inventory, 테스트 판정
- [02-critical-gaps.md](02-critical-gaps.md) — PRD 모순, provenance·runtime·플랫폼의 치명적 간극
- [03-success-gates-and-roadmap.md](03-success-gates-and-roadmap.md) — stage gate, owner, metric, kill/pivot 규칙
- [04-concierge-pilot.md](04-concierge-pilot.md) — 10영업일 F1 pilot 실행안
- [05-research-evidence-and-sources.md](05-research-evidence-and-sources.md) — 외부 1차 출처와 검증 이력

## 즉시 결정할 것

1. 전체 빌드를 중단하고 F1 concierge pilot만 승인한다.
2. pilot owner 한 명과 평가에 참여할 실제 사용자 3명을 지정한다.
3. 각 사용자가 최근 승인된 실제 변경을 가진 서로 다른 repository 1개씩 제공한다.
4. pilot 종료 시 아래 calibration gate로 `GO`, `PIVOT`, `KILL`을 판정한다. 숫자는 보편 기준이 아니라 첫 교정값이다.
