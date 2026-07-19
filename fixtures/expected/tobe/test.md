# TO-BE 테스트 시나리오

kind: tobe
provenance: `inputs/change/valid.md:3`

## TEST-TOBE-001

- GIVEN 주문 `42`가 존재한다.
- WHEN 고객이 `/orders/42`를 연다.
- THEN 주문 상세가 표시된다. (`STORY-TOBE-001`, `DESIGN-PAGE-001`)
