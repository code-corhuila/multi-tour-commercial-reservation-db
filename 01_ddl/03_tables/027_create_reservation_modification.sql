-- HU-COM-012 (-db) plan D-02, DP-D12-2 (PROPOSED default): the history of the changes of a reservation, one whole immutable row per change (RN-RES-004).
-- It keeps the value before and after, the pending balance before and after, the excess, the party, the tour and the departure, the reason, the author and the instant.
-- Money is bigint cents. Nothing has a DEFAULT. The two departures have no foreign key: a cross-domain logical reference (Annex J.3.4).
-- The reason is free text typed by staff and is never copied to the outbox. UPDATE is withdrawn in 03_dcl/01_grants/011; DELETE was never granted.
CREATE TABLE commercial_reservation.reservation_modification (
    reservation_modification_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_reservation_modification_tenant_required NOT NULL,
    reservation_id uuid CONSTRAINT chk_reservation_modification_reservation_required NOT NULL,
    change_type text CONSTRAINT chk_reservation_modification_change_type_required NOT NULL,
    reason text CONSTRAINT chk_reservation_modification_reason_required NOT NULL,
    previous_final_value_cents bigint CONSTRAINT chk_reservation_modification_previous_final_required NOT NULL,
    new_final_value_cents bigint CONSTRAINT chk_reservation_modification_new_final_required NOT NULL,
    previous_pending_balance_cents bigint CONSTRAINT chk_reservation_modification_previous_pending_required NOT NULL,
    new_pending_balance_cents bigint CONSTRAINT chk_reservation_modification_new_pending_required NOT NULL,
    excess_amount_cents bigint CONSTRAINT chk_reservation_modification_excess_required NOT NULL,
    previous_party_size integer CONSTRAINT chk_reservation_modification_previous_party_required NOT NULL,
    new_party_size integer CONSTRAINT chk_reservation_modification_new_party_required NOT NULL,
    previous_service_id uuid CONSTRAINT chk_reservation_modification_previous_service_required NOT NULL,
    new_service_id uuid CONSTRAINT chk_reservation_modification_new_service_required NOT NULL,
    previous_salida_id uuid CONSTRAINT chk_reservation_modification_previous_salida_required NOT NULL,
    new_salida_id uuid CONSTRAINT chk_reservation_modification_new_salida_required NOT NULL,
    registered_by uuid CONSTRAINT chk_reservation_modification_registered_by_required NOT NULL,
    registered_at timestamptz CONSTRAINT chk_reservation_modification_registered_at_required NOT NULL,
    CONSTRAINT pk_reservation_modification PRIMARY KEY (reservation_modification_id),
    CONSTRAINT fk_reservation_modification_reservation FOREIGN KEY (reservation_id)
        REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT,
    CONSTRAINT fk_reservation_modification_previous_service FOREIGN KEY (previous_service_id)
        REFERENCES commercial_reservation.catalog_service (service_id) ON DELETE RESTRICT,
    CONSTRAINT fk_reservation_modification_new_service FOREIGN KEY (new_service_id)
        REFERENCES commercial_reservation.catalog_service (service_id) ON DELETE RESTRICT,
    CONSTRAINT chk_reservation_modification_type CHECK (change_type IN ('MODIFICATION', 'DATE_CHANGE')),
    CONSTRAINT chk_reservation_modification_reason CHECK (btrim(reason) <> ''),
    CONSTRAINT chk_reservation_modification_values CHECK (
        previous_final_value_cents >= 0 AND new_final_value_cents >= 0
        AND previous_pending_balance_cents >= 0 AND new_pending_balance_cents >= 0 AND excess_amount_cents >= 0
        AND previous_party_size >= 1 AND new_party_size >= 1),
    CONSTRAINT chk_reservation_modification_excess CHECK (excess_amount_cents = 0 OR new_pending_balance_cents = 0),
    CONSTRAINT chk_reservation_modification_date_change CHECK (
        change_type <> 'DATE_CHANGE'
        OR (previous_salida_id <> new_salida_id AND previous_party_size = new_party_size AND previous_service_id = new_service_id)),
    CONSTRAINT chk_reservation_modification_changes_something CHECK (
        change_type <> 'MODIFICATION'
        OR (previous_party_size <> new_party_size OR previous_service_id <> new_service_id
            OR previous_salida_id <> new_salida_id OR previous_final_value_cents <> new_final_value_cents))
);
