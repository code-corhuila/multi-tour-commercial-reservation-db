-- HU-COM-017 (-db) plan D-07, AC-D17.12 (PROPOSED defaults): the sixth widening of outbox_event adds CreditBalanceRecorded and CreditBalanceApplied (domain-events.md),
-- written in the transaction of the recording and of the application. The reservation is the aggregate (the source reservation for the recording, the target for the
-- application). The payloads are closed to identifiers, amounts and codes, so no name, reason or document can travel. The four lists are rewritten as 028 wrote them with
-- the two new events; the actor stays required (both events have a person) and nothing existing is removed.
ALTER TABLE commercial_reservation.outbox_event
    DROP CONSTRAINT chk_outbox_event_event_type,
    DROP CONSTRAINT chk_outbox_event_type_matches_new_condition,
    DROP CONSTRAINT chk_outbox_event_exactly_one_aggregate,
    DROP CONSTRAINT chk_outbox_event_payload,
    ADD CONSTRAINT chk_outbox_event_event_type CHECK (event_type IN (
        'CatalogServiceInactivated', 'CatalogServiceReactivated',
        'EstablishmentAssociationPublished', 'EstablishmentAssociationInactivated',
        'EstablishmentAssociationReactivated', 'DiscountRuleChanged',
        'ReservationModified', 'CustomerRegistered', 'SensitiveDataAccessed',
        'ReservationCreated', 'PaymentEvidenceRegistered', 'CapacityAllocated',
        'PaymentValidated', 'PaymentRejected', 'ReservationConfirmed', 'CapacityReleased',
        'ReservationCancelled', 'ClientNotified', 'RefundAuthorized', 'CreditBalanceRecorded', 'CreditBalanceApplied')),
    ADD CONSTRAINT chk_outbox_event_type_matches_new_condition CHECK (
        event_type IN ('DiscountRuleChanged', 'ReservationModified', 'CustomerRegistered', 'SensitiveDataAccessed',
            'ReservationCreated', 'PaymentEvidenceRegistered', 'CapacityAllocated',
            'PaymentValidated', 'PaymentRejected', 'ReservationConfirmed', 'CapacityReleased', 'ReservationCancelled',
            'ClientNotified', 'RefundAuthorized', 'CreditBalanceRecorded', 'CreditBalanceApplied')
        OR (new_catalog_status IS NOT NULL AND (
        (event_type = 'EstablishmentAssociationPublished'
            AND previous_catalog_status IS NULL AND new_catalog_status = 'ACTIVE')
        OR (event_type IN ('CatalogServiceInactivated', 'EstablishmentAssociationInactivated')
            AND new_catalog_status = 'INACTIVE')
        OR (event_type IN ('CatalogServiceReactivated', 'EstablishmentAssociationReactivated')
            AND new_catalog_status = 'ACTIVE')))),
    ADD CONSTRAINT chk_outbox_event_exactly_one_aggregate CHECK (
        num_nonnulls(service_id, association_id, discount_rule_id, reservation_id, customer_id) = 1 AND (
        (event_type IN ('CatalogServiceInactivated', 'CatalogServiceReactivated')
            AND service_id IS NOT NULL AND previous_catalog_status IS NOT NULL)
        OR (event_type IN ('EstablishmentAssociationPublished',
            'EstablishmentAssociationInactivated', 'EstablishmentAssociationReactivated')
            AND association_id IS NOT NULL)
        OR (event_type = 'DiscountRuleChanged' AND discount_rule_id IS NOT NULL
            AND previous_catalog_status IS NULL AND new_catalog_status IS NULL)
        OR (event_type IN ('ReservationModified', 'ReservationCreated', 'PaymentEvidenceRegistered', 'CapacityAllocated',
            'PaymentValidated', 'PaymentRejected', 'ReservationConfirmed', 'CapacityReleased', 'ReservationCancelled',
            'ClientNotified', 'RefundAuthorized', 'CreditBalanceRecorded', 'CreditBalanceApplied')
            AND reservation_id IS NOT NULL AND previous_catalog_status IS NULL AND new_catalog_status IS NULL)
        OR (event_type IN ('CustomerRegistered', 'SensitiveDataAccessed') AND customer_id IS NOT NULL
            AND previous_catalog_status IS NULL AND new_catalog_status IS NULL))),
    ADD CONSTRAINT chk_outbox_event_payload CHECK (
        (event_type IN ('ReservationModified', 'CustomerRegistered', 'SensitiveDataAccessed',
            'ReservationCreated', 'PaymentEvidenceRegistered', 'CapacityAllocated',
            'PaymentValidated', 'PaymentRejected', 'ReservationConfirmed', 'CapacityReleased', 'ReservationCancelled',
            'ClientNotified', 'RefundAuthorized', 'CreditBalanceRecorded', 'CreditBalanceApplied')
            AND payload IS NOT NULL AND jsonb_typeof(payload) = 'object')
        OR (event_type NOT IN ('ReservationModified', 'CustomerRegistered', 'SensitiveDataAccessed',
            'ReservationCreated', 'PaymentEvidenceRegistered', 'CapacityAllocated',
            'PaymentValidated', 'PaymentRejected', 'ReservationConfirmed', 'CapacityReleased', 'ReservationCancelled',
            'ClientNotified', 'RefundAuthorized', 'CreditBalanceRecorded', 'CreditBalanceApplied')
            AND payload IS NULL)),
    ADD CONSTRAINT chk_outbox_event_payload_keys_credit_balance_recorded CHECK (
        event_type <> 'CreditBalanceRecorded'
        OR (jsonb_exists_all(payload, ARRAY['creditBalanceId', 'reservationId', 'customerId', 'amountCents', 'origin'])
            AND payload - ARRAY['creditBalanceId', 'reservationId', 'customerId', 'amountCents', 'origin'] = '{}'::jsonb)),
    ADD CONSTRAINT chk_outbox_event_payload_keys_credit_balance_applied CHECK (
        event_type <> 'CreditBalanceApplied'
        OR (jsonb_exists_all(payload, ARRAY['creditBalanceId', 'sourceReservationId', 'targetReservationId', 'appliedAmountCents', 'appliedByKind'])
            AND payload - ARRAY['creditBalanceId', 'sourceReservationId', 'targetReservationId', 'appliedAmountCents', 'appliedByKind'] = '{}'::jsonb));