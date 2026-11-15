-- HU-COM-004 (-db) closing decisions of 2026-10-28 (PROPOSED), docs issue #170: ONE widening of outbox_event for
-- ReservationModified (HU-COM-004), CustomerRegistered and SensitiveDataAccessed (HU-COM-005). Never editing applied 004/005.
-- Minimum change, as decided:
--  * reservation_id uuid NULL, no foreign key: the reservations table belongs to HU-COM-007 (the key arrives with it).
--  * customer_id uuid NULL, foreign key to customer (ON DELETE RESTRICT, like the other aggregates).
--  * payload jsonb NULL: mandatory object for the three new events, absent for the older ones (they keep their own columns).
--    A guard refuses the sensitive keys of the conventions at the top level; the service still must not put them there.
--  * actor_id stops being NOT NULL, because CustomerRegistered names no actor in domain-events.md; every other event keeps it (CHECK).
--  * the catalog status columns are already nullable since 004 and 005 (service_id too): nothing else to relax.
--  * the aggregate CHECK counts five references, exactly one, and the type says which one; the new events carry no catalog status.
-- No new index: outbox_event is read through its unpublished-events index, and customer rows are never deleted (no DELETE grant).
ALTER TABLE commercial_reservation.outbox_event
    ADD COLUMN reservation_id uuid,
    ADD COLUMN customer_id uuid,
    ADD COLUMN payload jsonb,
    ALTER COLUMN actor_id DROP NOT NULL,
    DROP CONSTRAINT chk_outbox_event_event_type,
    DROP CONSTRAINT chk_outbox_event_type_matches_new_condition,
    DROP CONSTRAINT chk_outbox_event_exactly_one_aggregate,
    ADD CONSTRAINT chk_outbox_event_event_type CHECK (event_type IN (
        'CatalogServiceInactivated', 'CatalogServiceReactivated',
        'EstablishmentAssociationPublished', 'EstablishmentAssociationInactivated',
        'EstablishmentAssociationReactivated', 'DiscountRuleChanged',
        'ReservationModified', 'CustomerRegistered', 'SensitiveDataAccessed')),
    ADD CONSTRAINT chk_outbox_event_type_matches_new_condition CHECK (
        event_type IN ('DiscountRuleChanged', 'ReservationModified', 'CustomerRegistered', 'SensitiveDataAccessed')
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
        OR (event_type = 'ReservationModified' AND reservation_id IS NOT NULL
            AND previous_catalog_status IS NULL AND new_catalog_status IS NULL)
        OR (event_type IN ('CustomerRegistered', 'SensitiveDataAccessed') AND customer_id IS NOT NULL
            AND previous_catalog_status IS NULL AND new_catalog_status IS NULL))),
    ADD CONSTRAINT chk_outbox_event_actor_required CHECK (
        actor_id IS NOT NULL OR event_type = 'CustomerRegistered'),
    ADD CONSTRAINT chk_outbox_event_payload CHECK (
        (event_type IN ('ReservationModified', 'CustomerRegistered', 'SensitiveDataAccessed')
            AND payload IS NOT NULL AND jsonb_typeof(payload) = 'object')
        OR (event_type NOT IN ('ReservationModified', 'CustomerRegistered', 'SensitiveDataAccessed')
            AND payload IS NULL)),
    ADD CONSTRAINT chk_outbox_event_payload_no_sensitive_keys CHECK (
        payload IS NULL OR NOT jsonb_exists_any(payload, ARRAY[
            'document', 'documentNumber', 'document_number', 'birthDate', 'birth_date',
            'birthDateOrAge', 'birth_date_or_age', 'age', 'medicalInformation', 'medical_information',
            'emergencyInformation', 'emergency_information', 'emergencyContact', 'emergency_contact',
            'contactInfo', 'contact_info', 'email', 'phone', 'fullName', 'full_name'])),
    ADD CONSTRAINT fk_outbox_event_customer FOREIGN KEY (customer_id)
        REFERENCES commercial_reservation.customer (customer_id) ON DELETE RESTRICT;
