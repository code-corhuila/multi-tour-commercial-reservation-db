-- HU-COM-016 (-db) plan D-05, DP-D16-3, AC-D16.7 (RN-RES-006C): one treatment decision per cancellation. Modification excesses and refund requests may repeat.
-- The table is new and empty: no CONCURRENTLY.
CREATE UNIQUE INDEX uq_financial_decision_treatment_reservation ON commercial_reservation.financial_decision (tenant_id, reservation_id, decision_kind)
    WHERE decision_kind IN ('PENDING_TREATMENT', 'CUSTOMER_CANCELLATION');
