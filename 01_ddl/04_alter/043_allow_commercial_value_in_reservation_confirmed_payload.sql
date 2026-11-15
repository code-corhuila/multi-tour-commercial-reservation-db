-- HU-CSH-003 DP-RM-B3 (PDR v1.9 RF-012, "ventas por dia = reservas cuyo valor comercial quedo confirmado en esa fecha"): the closed key list of ReservationConfirmed (04_alter/017) admits one more key,
-- commercialValueCents, the final value of the reservation at the instant of its confirmation, as a non-negative whole number of cents (the cash report adds it to the confirmed sales of the month).
-- It is allowed and not required, so the rows already stored stay valid and the change is additive; the list stays closed (no name, document, contact or file can travel) and no other event type changes.
-- 017 is not edited: the constraint keeps its name and is rewritten here.
ALTER TABLE commercial_reservation.outbox_event
    DROP CONSTRAINT chk_outbox_event_payload_keys_reservation_confirmed,
    ADD CONSTRAINT chk_outbox_event_payload_keys_reservation_confirmed CHECK (
        event_type <> 'ReservationConfirmed'
        OR (jsonb_exists_all(payload, ARRAY['reservationId', 'paymentStatus'])
            AND payload - ARRAY['reservationId', 'paymentStatus', 'allocatedCapacity', 'commercialValueCents'] = '{}'::jsonb
            AND (NOT jsonb_exists(payload, 'commercialValueCents')
                 OR (jsonb_typeof(payload -> 'commercialValueCents') = 'number' AND (payload ->> 'commercialValueCents') ~ '^[0-9]+$'))));
