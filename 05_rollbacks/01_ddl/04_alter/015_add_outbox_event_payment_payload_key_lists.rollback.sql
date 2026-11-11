ALTER TABLE commercial_reservation.outbox_event
    DROP CONSTRAINT chk_outbox_event_payload_keys_capacity_allocated,
    DROP CONSTRAINT chk_outbox_event_payload_keys_payment_evidence_registered;
