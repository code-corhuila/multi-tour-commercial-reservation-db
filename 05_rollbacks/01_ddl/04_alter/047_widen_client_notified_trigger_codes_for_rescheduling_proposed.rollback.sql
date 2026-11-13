-- HU-COM-015 AC-15.5 (-db): the trigger codes of 027, without ReschedulingProposed. A database that already holds a proposal notice refuses this revert on purpose (the new check cannot be added over that row): the outbox rows are never rewritten by a migration; the owner decides.
ALTER TABLE commercial_reservation.outbox_event
    DROP CONSTRAINT chk_outbox_event_client_notified_codes,
    ADD CONSTRAINT chk_outbox_event_client_notified_codes CHECK (
        event_type <> 'ClientNotified'
        OR (coalesce(payload ->> 'notificationType' IN (
            'PROOF_APPROVED', 'PROOF_REJECTED', 'RESERVATION_CONFIRMED', 'RESERVATION_CANCELLED_NON_PAYMENT',
            'REFUND_PROCESSED', 'CREDIT_BALANCE_RECORDED', 'DEPARTURE_CANCELLED', 'RESCHEDULING_PROPOSED'), false)
            AND coalesce(payload ->> 'triggeringEventType' IN (
            'PaymentValidated', 'PaymentRejected', 'ReservationConfirmed', 'ReservationCancelled',
            'RefundExecuted', 'CreditBalanceRecorded', 'SalidaCancelled', 'ReservationRescheduled'), false)));
