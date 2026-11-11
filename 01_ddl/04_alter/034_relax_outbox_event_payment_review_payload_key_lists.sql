-- HU-COM-010 (-db), debt of the audit of 2026-11-06 (decided by default, Fernanda, 2026-11-09): the attempt (proof) id must travel in PaymentValidated and PaymentRejected so a
-- consumer such as Cash can correlate and deduplicate, and the free-text reason of a reviewer, which may hold personal data, must stop being mandatory in PaymentRejected.
-- The two key lists of 04_alter/017 are rewritten. The required keys stay the same, except reason, which is no longer required. attemptId is allowed and not required, and
-- reason stays allowed, so every event already stored (without attemptId, with reason) is still valid and no data is migrated. No other key is allowed.
--   PaymentValidated: required reservationId, amountCents, paymentStatus, pendingBalanceCents, validatorId; allowed besides them attemptId.
--   PaymentRejected: required reservationId, pendingBalanceCents, validatorId; allowed besides them attemptId and reason.
ALTER TABLE commercial_reservation.outbox_event
    DROP CONSTRAINT chk_outbox_event_payload_keys_payment_validated,
    DROP CONSTRAINT chk_outbox_event_payload_keys_payment_rejected,
    ADD CONSTRAINT chk_outbox_event_payload_keys_payment_validated CHECK (
        event_type <> 'PaymentValidated'
        OR (jsonb_exists_all(payload, ARRAY['reservationId', 'amountCents', 'paymentStatus', 'pendingBalanceCents', 'validatorId'])
            AND payload - ARRAY['reservationId', 'amountCents', 'paymentStatus', 'pendingBalanceCents', 'validatorId', 'attemptId'] = '{}'::jsonb)),
    ADD CONSTRAINT chk_outbox_event_payload_keys_payment_rejected CHECK (
        event_type <> 'PaymentRejected'
        OR (jsonb_exists_all(payload, ARRAY['reservationId', 'pendingBalanceCents', 'validatorId'])
            AND payload - ARRAY['reservationId', 'pendingBalanceCents', 'validatorId', 'attemptId', 'reason'] = '{}'::jsonb));
