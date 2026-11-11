-- HU-COM-012 (-db) plan D-03, DP-D12-1 (PROPOSED default): the terms per tenant, tour and change type that decide whether a change is allowed (RN-RES-004).
-- change_type is free text: its values are NO DEFINIDO in the dictionary, so no CHECK list is written. The lead time is required when the change is allowed
-- and absent when it is not. Nothing has a DEFAULT and no row is seeded: a tenant without a row has every change refused by the -api.
CREATE TABLE commercial_reservation.service_change_policy (
    service_change_policy_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_service_change_policy_tenant_required NOT NULL,
    service_id uuid CONSTRAINT chk_service_change_policy_service_required NOT NULL,
    change_type text CONSTRAINT chk_service_change_policy_change_type_required NOT NULL,
    change_allowed boolean CONSTRAINT chk_service_change_policy_allowed_required NOT NULL,
    request_lead_minutes integer,
    changed_by uuid CONSTRAINT chk_service_change_policy_changed_by_required NOT NULL,
    changed_at timestamptz CONSTRAINT chk_service_change_policy_changed_at_required NOT NULL,
    CONSTRAINT pk_service_change_policy PRIMARY KEY (service_change_policy_id),
    CONSTRAINT fk_service_change_policy_service FOREIGN KEY (service_id)
        REFERENCES commercial_reservation.catalog_service (service_id) ON DELETE RESTRICT,
    CONSTRAINT uq_service_change_policy_tenant_service_type UNIQUE (tenant_id, service_id, change_type),
    CONSTRAINT chk_service_change_policy_change_type CHECK (btrim(change_type) <> ''),
    CONSTRAINT chk_service_change_policy_lead CHECK (
        (change_allowed AND request_lead_minutes IS NOT NULL AND request_lead_minutes >= 0)
        OR (NOT change_allowed AND request_lead_minutes IS NULL))
);
