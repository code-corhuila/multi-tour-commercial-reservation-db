-- HU-COM-009 (-db) plan D-09 (PROPOSED): the event names and the object payload rule are in the second widening of HU-COM-007 (04_alter/012).
-- This changeset only closes the key list of the two payloads of this story to the fields of domain-events.md, so no file, file name,
-- bank datum or account can travel. Required and allowed keys are the same set. Additive: nothing existing is touched.
--   PaymentEvidenceRegistered: tenant (a column), reservation, attempt reference, modality, registered amount, validation condition.
--   CapacityAllocated: tenant (a column), resource (the service), salida, reservation, allocation condition (the kind).
ALTER TABLE commercial_reservation.outbox_event
    ADD CONSTRAINT chk_outbox_event_payload_keys_payment_evidence_registered CHECK (
        event_type <> 'PaymentEvidenceRegistered'
        OR (jsonb_exists_all(payload, ARRAY['reservationId', 'attemptId', 'modality', 'registeredAmountCents', 'validationStatus'])
            AND payload - ARRAY['reservationId', 'attemptId', 'modality', 'registeredAmountCents', 'validationStatus'] = '{}'::jsonb)),
    ADD CONSTRAINT chk_outbox_event_payload_keys_capacity_allocated CHECK (
        event_type <> 'CapacityAllocated'
        OR (jsonb_exists_all(payload, ARRAY['serviceId', 'salidaId', 'reservationId', 'allocationKind'])
            AND payload - ARRAY['serviceId', 'salidaId', 'reservationId', 'allocationKind'] = '{}'::jsonb));
