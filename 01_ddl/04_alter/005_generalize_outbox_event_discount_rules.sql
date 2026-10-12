-- PROPUESTO (HU-COM-003 API D-10): extend the same outbox, never edit applied 004.
-- Full previous/new rule snapshots use proposed physical names; status stays unconstrained.
-- Discount updates need not change status. Catalog/association events keep their old rules.
ALTER TABLE commercial_reservation.outbox_event
    ADD COLUMN discount_rule_id uuid,
    ADD COLUMN previous_discount_rule_state jsonb,
    ADD COLUMN new_discount_rule_state jsonb,
    ALTER COLUMN new_catalog_status DROP NOT NULL,
    DROP CONSTRAINT chk_outbox_event_event_type,
    DROP CONSTRAINT chk_outbox_event_condition_changed,
    DROP CONSTRAINT chk_outbox_event_type_matches_new_condition,
    DROP CONSTRAINT chk_outbox_event_exactly_one_aggregate,
    ADD CONSTRAINT chk_outbox_event_event_type CHECK (event_type IN (
        'CatalogServiceInactivated', 'CatalogServiceReactivated',
        'EstablishmentAssociationPublished', 'EstablishmentAssociationInactivated',
        'EstablishmentAssociationReactivated', 'DiscountRuleChanged')),
    ADD CONSTRAINT chk_outbox_event_condition_changed CHECK (
        event_type = 'DiscountRuleChanged' OR previous_catalog_status IS NULL
        OR previous_catalog_status <> new_catalog_status),
    ADD CONSTRAINT chk_outbox_event_type_matches_new_condition CHECK (
        event_type = 'DiscountRuleChanged' OR (new_catalog_status IS NOT NULL AND (
        (event_type = 'EstablishmentAssociationPublished'
            AND previous_catalog_status IS NULL AND new_catalog_status = 'ACTIVE')
        OR (event_type IN ('CatalogServiceInactivated', 'EstablishmentAssociationInactivated')
            AND new_catalog_status = 'INACTIVE')
        OR (event_type IN ('CatalogServiceReactivated', 'EstablishmentAssociationReactivated')
            AND new_catalog_status = 'ACTIVE')))),
    ADD CONSTRAINT chk_outbox_event_exactly_one_aggregate CHECK (
        num_nonnulls(service_id, association_id, discount_rule_id) = 1 AND (
        (event_type IN ('CatalogServiceInactivated', 'CatalogServiceReactivated')
            AND service_id IS NOT NULL AND previous_catalog_status IS NOT NULL)
        OR (event_type IN ('EstablishmentAssociationPublished',
            'EstablishmentAssociationInactivated', 'EstablishmentAssociationReactivated')
            AND association_id IS NOT NULL)
        OR (event_type = 'DiscountRuleChanged' AND discount_rule_id IS NOT NULL
            AND previous_catalog_status IS NULL AND new_catalog_status IS NULL))),
    ADD CONSTRAINT chk_outbox_event_discount_rule_state CHECK (
        (event_type = 'DiscountRuleChanged' AND new_discount_rule_state IS NOT NULL
            AND jsonb_typeof(new_discount_rule_state) = 'object'
            AND (previous_discount_rule_state IS NULL OR jsonb_typeof(previous_discount_rule_state) = 'object'))
        OR (event_type <> 'DiscountRuleChanged'
            AND previous_discount_rule_state IS NULL AND new_discount_rule_state IS NULL)),
    ADD CONSTRAINT fk_outbox_event_discount_rule FOREIGN KEY (discount_rule_id)
        REFERENCES commercial_reservation.discount_rule (discount_rule_id) ON DELETE RESTRICT;
