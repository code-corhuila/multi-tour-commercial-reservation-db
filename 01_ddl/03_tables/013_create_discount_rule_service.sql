-- HU-COM-003 DP-01 (default 2026-10-28, PROPOSED, pending the Project Lead): the catalog services a
-- discount rule covers when covers_all_services is false (06-data/models.md coverage option B).
-- The pair (rule, service) is the primary key: a service is never listed twice for one rule, and the
-- key also serves as the index of the rule foreign key. The service foreign key gets its own index (10_indexes).
-- Simple foreign keys, as outbox_event and salida_capacity do: catalog_service and discount_rule carry no UNIQUE with
-- tenant_id, so a link across tenants is checked by the -api, not by the engine (declared gap).
-- No trigger forces "no rows when covers_all_services is true, at least one when false": none is proposed.
-- Default writer privileges give SELECT/INSERT/UPDATE, never DELETE.
CREATE TABLE commercial_reservation.discount_rule_service (
    tenant_id uuid CONSTRAINT chk_discount_rule_service_tenant_required NOT NULL,
    discount_rule_id uuid NOT NULL,
    service_id uuid NOT NULL,
    CONSTRAINT pk_discount_rule_service PRIMARY KEY (discount_rule_id, service_id),
    CONSTRAINT fk_discount_rule_service_rule FOREIGN KEY (discount_rule_id)
        REFERENCES commercial_reservation.discount_rule (discount_rule_id) ON DELETE RESTRICT,
    CONSTRAINT fk_discount_rule_service_service FOREIGN KEY (service_id)
        REFERENCES commercial_reservation.catalog_service (service_id) ON DELETE RESTRICT
);
