-- HU-COM-007 (-db) plan D-03 (PROPOSED): one row per reserved service, with the rates used at creation (DP-D7-3).
-- base_rate_cents is the rate per person used for the tour; transport_rate_cents the fare per person used, null when the tour has none.
-- The transport is not a row (-api DP-03): it is a line of the calculation. scheduled_date is nullable ("when applicable", models.md).
-- One row per tour in a reservation: a looser rule is easy to add later, a tighter one would be a migration over data (DP-11 of the -api).
-- Nothing has a DEFAULT. Default writer privileges give SELECT/INSERT/UPDATE and never DELETE.
CREATE TABLE commercial_reservation.reserved_service (
    reserved_service_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_reserved_service_tenant_required NOT NULL,
    reservation_id uuid CONSTRAINT chk_reserved_service_reservation_required NOT NULL,
    service_id uuid CONSTRAINT chk_reserved_service_service_required NOT NULL,
    party_size integer CONSTRAINT chk_reserved_service_party_size_required NOT NULL,
    scheduled_date date,
    base_rate_cents bigint CONSTRAINT chk_reserved_service_base_rate_required NOT NULL,
    transport_rate_cents bigint,
    CONSTRAINT pk_reserved_service PRIMARY KEY (reserved_service_id),
    CONSTRAINT fk_reserved_service_reservation FOREIGN KEY (reservation_id)
        REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT,
    CONSTRAINT fk_reserved_service_service FOREIGN KEY (service_id)
        REFERENCES commercial_reservation.catalog_service (service_id) ON DELETE RESTRICT,
    CONSTRAINT uq_reserved_service_reservation_service UNIQUE (reservation_id, service_id),
    CONSTRAINT chk_reserved_service_party_size CHECK (party_size > 0),
    CONSTRAINT chk_reserved_service_base_rate CHECK (base_rate_cents >= 0),
    CONSTRAINT chk_reserved_service_transport_rate CHECK (transport_rate_cents >= 0)
);
