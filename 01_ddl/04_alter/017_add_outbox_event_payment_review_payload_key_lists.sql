-- HU-COM-010 (-db) plan D-07, DP-D10-4 (PROPOSED default, debt DD-5): the names of the four events and the object payload rule are in the second widening of
-- HU-COM-007 (04_alter/012). This changeset only closes the key list of each payload to the fields of domain-events.md, so no name, document, contact
-- or file can travel. The rejection reason is allowed only because the catalog lists it. ReservationConfirmed carries the allocated capacity only when
-- applicable, so that key is allowed but not required. Additive: nothing existing is touched.
--   PaymentValidated: tenant (a column), reservation, amount, payment status, pending balance, validator.
--   PaymentRejected: tenant (a column), reservation, reason, pending balance, validator.
--   ReservationConfirmed: tenant (a column), reservation, payment status, allocated capacity when applicable.
--   CapacityReleased: tenant (a column), resource (the service), salida, reservation, reason.
ALTER TABLE commercial_reservation.outbox_event
    ADD CONSTRAINT chk_outbox_event_payload_keys_payment_validated CHECK (
        event_type <> 'PaymentValidated'
        OR (jsonb_exists_all(payload, ARRAY['reservationId', 'amountCents', 'paymentStatus', 'pendingBalanceCents', 'validatorId'])
            AND payload - ARRAY['reservationId', 'amountCents', 'paymentStatus', 'pendingBalanceCents', 'validatorId'] = '{}'::jsonb)),
    ADD CONSTRAINT chk_outbox_event_payload_keys_payment_rejected CHECK (
        event_type <> 'PaymentRejected'
        OR (jsonb_exists_all(payload, ARRAY['reservationId', 'reason', 'pendingBalanceCents', 'validatorId'])
            AND payload - ARRAY['reservationId', 'reason', 'pendingBalanceCents', 'validatorId'] = '{}'::jsonb)),
    ADD CONSTRAINT chk_outbox_event_payload_keys_reservation_confirmed CHECK (
        event_type <> 'ReservationConfirmed'
        OR (jsonb_exists_all(payload, ARRAY['reservationId', 'paymentStatus'])
            AND payload - ARRAY['reservationId', 'paymentStatus', 'allocatedCapacity'] = '{}'::jsonb)),
    ADD CONSTRAINT chk_outbox_event_payload_keys_capacity_released CHECK (
        event_type <> 'CapacityReleased'
        OR (jsonb_exists_all(payload, ARRAY['serviceId', 'salidaId', 'reservationId', 'reason'])
            AND payload - ARRAY['serviceId', 'salidaId', 'reservationId', 'reason'] = '{}'::jsonb));
