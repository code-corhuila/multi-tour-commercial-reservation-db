-- HU-COM-012 (-db) plan D-04 (PROPOSED): at most one pending-difference deadline per reservation (RN-RES-004, the difference is one), in the style of the
-- initial-deadline unique of HU-COM-009. The -api moves the due instant when a new difference arises after the previous one was paid.
CREATE UNIQUE INDEX uq_payment_deadline_pending_difference_reservation ON commercial_reservation.payment_deadline (tenant_id, reservation_id)
    WHERE deadline_kind = 'PENDING_DIFFERENCE';
