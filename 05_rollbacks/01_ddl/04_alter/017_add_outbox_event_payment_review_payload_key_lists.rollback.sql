ALTER TABLE commercial_reservation.outbox_event
    DROP CONSTRAINT chk_outbox_event_payload_keys_capacity_released,
    DROP CONSTRAINT chk_outbox_event_payload_keys_reservation_confirmed,
    DROP CONSTRAINT chk_outbox_event_payload_keys_payment_rejected,
    DROP CONSTRAINT chk_outbox_event_payload_keys_payment_validated;
