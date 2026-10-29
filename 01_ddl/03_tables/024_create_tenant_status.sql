-- HU-WRK-007 -db spec 021 (PROPOSED): the local copy of the tenants of identity-audit that this service keeps from the
-- tenant events (ADR-004 D4, D5). tenant_id is the key and has no foreign key: tenants belongs to another domain (ADR-003).
-- No DEFAULT: the service states every instant. The rows are written only by the -api event route; nothing is seeded.
CREATE TABLE commercial_reservation.tenant_status (
    tenant_id uuid NOT NULL,
    identifier text NOT NULL,
    status text NOT NULL,
    time_zone text NOT NULL,
    country text NOT NULL,
    last_event_occurred_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    CONSTRAINT pk_tenant_status PRIMARY KEY (tenant_id),
    -- also the index that serves the lookup of a public path /t/{identifier}
    CONSTRAINT uq_tenant_status_identifier UNIQUE (identifier),
    CONSTRAINT chk_tenant_status_tenant_id_required CHECK (tenant_id IS NOT NULL),
    CONSTRAINT chk_tenant_status_identifier_required CHECK (identifier IS NOT NULL),
    CONSTRAINT chk_tenant_status_status_required CHECK (status IS NOT NULL),
    CONSTRAINT chk_tenant_status_time_zone_required CHECK (time_zone IS NOT NULL),
    CONSTRAINT chk_tenant_status_country_required CHECK (country IS NOT NULL),
    CONSTRAINT chk_tenant_status_last_event_occurred_at_required CHECK (last_event_occurred_at IS NOT NULL),
    CONSTRAINT chk_tenant_status_created_at_required CHECK (created_at IS NOT NULL),
    CONSTRAINT chk_tenant_status_updated_at_required CHECK (updated_at IS NOT NULL),
    -- the pattern and the bounds of TenantIdentifier in identity-audit.yaml
    CONSTRAINT chk_tenant_status_identifier_format CHECK (identifier ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND char_length(identifier) BETWEEN 3 AND 40),
    -- PENDING and FAILED tenants never reach this service (DP-D21-3)
    CONSTRAINT chk_tenant_status_status CHECK (status IN ('ACTIVE', 'INACTIVE')),
    CONSTRAINT chk_tenant_status_country_format CHECK (country ~ '^[A-Z]{2}$'),
    -- the list of IANA names is validated by the application, not by the engine
    CONSTRAINT chk_tenant_status_time_zone_length CHECK (char_length(time_zone) BETWEEN 1 AND 64)
);
