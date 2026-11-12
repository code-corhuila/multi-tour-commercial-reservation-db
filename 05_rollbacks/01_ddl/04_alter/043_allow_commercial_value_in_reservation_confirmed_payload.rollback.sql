-- HU-CSH-003 DP-RM-B3 (-db): the closed list of 017, without commercialValueCents. A database that already holds a ReservationConfirmed row with the key refuses this revert on purpose: the outbox rows are never rewritten by a migration; the owner decides.
ALTER TABLE commercial_reservation.outbox_event
    DROP CONSTRAINT chk_outbox_event_payload_keys_reservation_confirmed,
    ADD CONSTRAINT chk_outbox_event_payload_keys_reservation_confirmed CHECK (
        event_type <> 'ReservationConfirmed'
        OR (jsonb_exists_all(payload, ARRAY['reservationId', 'paymentStatus'])
            AND payload - ARRAY['reservationId', 'paymentStatus', 'allocatedCapacity'] = '{}'::jsonb));
