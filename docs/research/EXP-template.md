# EXP 레코드 양식 — 연구일지 (T2-methodology §1)

> 각 연구 발견을 이 양식으로 기록한다. 근거·출처·근사치/실측을 명시하고, "더 좋아진 것 같다"를 금지한다(측정/근사치로).

## EXP-<YYYYMMDD>-<NNN>

| 항목 | 값 |
| --- | --- |
| id | `EXP-YYYYMMDD-NNN` |
| category | `model` / `test` / `tool` / `mapping` / `topology` / `quality` |
| 질문·가설 | 무엇을 검증하는가 |
| 방법 | 절차·도구·입력 (재현 가능) |
| 근사치(predicted) | 출처 명시: 모델 카드 / 공식 문서 / 경험 |
| 실측(actual) | live 환경 결과 (없으면 `미정`, live에서 보완) |
| delta | predicted vs actual 차이 |
| 결과 | 측정값 (정량) |
| 포스트모템 | 채택 / 폐기 + 사유 |
| 출처 | 문서·카드·경험 링크 |
| 관련 | R 영역 / REQ |

## 발견 처리 (T2-methodology §3)

- **채택** 발견 → harness 옵션 반영(`opencode.json` / agent / skill).
- **폐기** 발견 → 사유 보존(재검토 가능).
- 근사치는 live 환경에서 실측으로 보완.
- 동일 환경(Win10/PS7.6 · 동일 모델/도구 버전)에서 재현 가능해야 한다.
