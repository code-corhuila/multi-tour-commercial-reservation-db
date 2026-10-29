-- HU-COM-004 (-db) docs issue #171, plan D-06 (PROPOSED): the reasons a tenant can pick for an additional discount.
-- A reason is never deleted: it is DISABLED (the contract's reasonStatus ENABLED/DISABLED). The last enabled reason of a
-- tenant is protected by the service, not by a trigger. No DEFAULT: the service decides every value, like catalog_service.
-- The normalized text (ignoring case and surrounding spaces) is unique per tenant; the table is new and empty, so its unique
-- index is built here and not CONCURRENTLY (norm 5.2.7). Default writer privileges give SELECT/INSERT/UPDATE, never DELETE.
CREATE TABLE commercial_reservation.authorizable_reason (
    authorizable_reason_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_authorizable_reason_tenant_required NOT NULL,
    reason text CONSTRAINT chk_authorizable_reason_reason_required NOT NULL,
    status text NOT NULL,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    CONSTRAINT pk_authorizable_reason PRIMARY KEY (authorizable_reason_id),
    CONSTRAINT chk_authorizable_reason_status CHECK (status IN ('ENABLED', 'DISABLED')),
    CONSTRAINT chk_authorizable_reason_text_length CHECK (btrim(reason) <> '' AND char_length(reason) <= 255)
);
CREATE UNIQUE INDEX uq_authorizable_reason_tenant_text ON commercial_reservation.authorizable_reason (tenant_id, lower(btrim(reason)));
