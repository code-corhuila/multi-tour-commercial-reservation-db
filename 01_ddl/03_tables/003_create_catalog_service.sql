-- The offer a tenant sells. Rows are never deleted (RN-06): a service leaves the offer by becoming
-- INACTIVE, which is why the writer role holds no DELETE on this table.
--
-- Nothing here has a DEFAULT, on purpose (plan.md DD-8, DD-16): the service decides the id, the
-- status and the risk mark, so a row that forgets one is refused by the engine instead of silently
-- taking a value nobody chose.
-- Money is bigint cents, never a decimal, so a rate can never carry a rounding error.
-- The foreign key from outbox_event arrives in 04_alter, and the closed value sets are CHECKs and
-- not ENUMs because a new value must be a migration of one constraint, not of a type.
CREATE TABLE commercial_reservation.catalog_service (
    service_id                  uuid        NOT NULL,
    tenant_id                   uuid        NOT NULL,
    service_type                text        NOT NULL,
    commercial_name             text        NOT NULL,
    catalog_status              text        NOT NULL,
    base_rate_cents             bigint      NOT NULL,
    base_operational_cost_cents bigint      NOT NULL,
    -- null for a service that has no seats to count; the capacity rules of T-10 build on this column
    configured_capacity         integer,
    transport_required          boolean     NOT NULL,
    high_risk                   boolean     NOT NULL,
    created_at                  timestamptz NOT NULL,
    updated_at                  timestamptz NOT NULL,
    CONSTRAINT pk_catalog_service PRIMARY KEY (service_id),
    CONSTRAINT chk_catalog_service_service_type CHECK (service_type IN ('TOUR', 'TRANSPORTATION')),
    CONSTRAINT chk_catalog_service_commercial_name_length CHECK (char_length(commercial_name) BETWEEN 1 AND 255),
    CONSTRAINT chk_catalog_service_catalog_status CHECK (catalog_status IN ('ACTIVE', 'INACTIVE')),
    CONSTRAINT chk_catalog_service_base_rate_cents CHECK (base_rate_cents >= 0),
    CONSTRAINT chk_catalog_service_base_operational_cost_cents CHECK (base_operational_cost_cents >= 0),
    CONSTRAINT chk_catalog_service_configured_capacity CHECK (configured_capacity IS NULL OR configured_capacity > 0),
    -- a tour is sold by seats, so it cannot exist without the capacity to count them against
    CONSTRAINT chk_catalog_service_tour_requires_capacity CHECK (service_type <> 'TOUR' OR configured_capacity IS NOT NULL),
    -- transportation is itself the transport, so it cannot also require one
    CONSTRAINT chk_catalog_service_transportation_not_requiring_transport CHECK (service_type <> 'TRANSPORTATION' OR transport_required = false)
);
