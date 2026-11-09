-- Restores the two closed lists of 04_alter/017. It fails on purpose if an event written with attemptId, or without reason, is still stored: such rows must be removed first.
ALTER TABLE commercial_reservation.outbox_event
    DROP CONSTRAINT chk_outbox_event_payload_keys_payment_rejected,
    DROP CONSTRAINT chk_outbox_event_payload_keys_payment_validated,
    ADD CONSTRAINT chk_outbox_event_payload_keys_payment_validated CHECK (
        event_type <> 'PaymentValidated'
        OR (jsonb_exists_all(payload, ARRAY['reservationId', 'amountCents', 'paymentStatus', 'pendingBalanceCents', 'validatorId'])
            AND payload - ARRAY['reservationId', 'amountCents', 'paymentStatus', 'pendingBalanceCents', 'validatorId'] = '{}'::jsonb)),
    ADD CONSTRAINT chk_outbox_event_payload_keys_payment_rejected CHECK (
        event_type <> 'PaymentRejected'
        OR (jsonb_exists_all(payload, ARRAY['reservationId', 'reason', 'pendingBalanceCents', 'validatorId'])
            AND payload - ARRAY['reservationId', 'reason', 'pendingBalanceCents', 'validatorId'] = '{}'::jsonb));
