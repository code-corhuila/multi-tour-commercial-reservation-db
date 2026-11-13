-- HU-COM-015 AC-15.5 (docs spec 015 DP-15-04 and DD-6 of spec 018, DP-D15-6 of the db spec, PROPOSED default): the guard chk_outbox_event_client_notified_codes of 027 admits one more trigger code, ReschedulingProposed, so the notice of a rescheduling
-- proposal (notificationType RESCHEDULING_PROPOSED, already admitted) can name the proposal as the fact that triggered it. Nothing else changes: no column, no payload key, no other event type; every row already stored stays valid.
ALTER TABLE commercial_reservation.outbox_event
    DROP CONSTRAINT chk_outbox_event_client_notified_codes,
    ADD CONSTRAINT chk_outbox_event_client_notified_codes CHECK (
        event_type <> 'ClientNotified'
        OR (coalesce(payload ->> 'notificationType' IN (
            'PROOF_APPROVED', 'PROOF_REJECTED', 'RESERVATION_CONFIRMED', 'RESERVATION_CANCELLED_NON_PAYMENT',
            'REFUND_PROCESSED', 'CREDIT_BALANCE_RECORDED', 'DEPARTURE_CANCELLED', 'RESCHEDULING_PROPOSED'), false)
            AND coalesce(payload ->> 'triggeringEventType' IN (
            'PaymentValidated', 'PaymentRejected', 'ReservationConfirmed', 'ReservationCancelled',
            'RefundExecuted', 'CreditBalanceRecorded', 'SalidaCancelled', 'ReservationRescheduled', 'ReschedulingProposed'), false)));
