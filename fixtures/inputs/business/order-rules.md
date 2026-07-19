# Order domain rules

- BIZ-RULE-001: stock MUST remain zero or greater when an order is accepted.
- BIZ-RULE-002: legacy notes claim backorders MAY make stock negative; this conflicts with BIZ-RULE-001.
- BIZ-EVENT-001: accepting an order emits `order.created`.
- BIZ-INVARIANT-001: a paid order MUST NOT transition to pending.
