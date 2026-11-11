-- HU-COM-007 (-db) docs issue #173, plan D-02 and D-04 (PROPOSED, debt DD-3): the reservation, the foundation of the lifecycle.
-- Columns of the logical reservations of models.md plus the three of DP-D7-2 (service_id, party_size, created_by).
-- Money is bigint cents. Nothing has a DEFAULT: the service states every value and the birth trigger requires them.
-- salida_id has no foreign key: a cross-domain logical reference (Annex J.3.4, RN-RES-010). The customer key is simple (DP-D7-4).
-- The closed lists hold English codes (DP-D7-1). There is no permanent CHECK between final_value_cents and projected_value_cents:
-- a modification may raise the final value; the birth relation lives in trg_reservation_birth (09_triggers/001).
-- Default writer privileges give SELECT/INSERT/UPDATE and never DELETE (AC-D7.14).
CREATE TABLE commercial_reservation.reservation (
    reservation_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_reservation_tenant_required NOT NULL,
    customer_id uuid CONSTRAINT chk_reservation_customer_required NOT NULL,
    salida_id uuid CONSTRAINT chk_reservation_salida_required NOT NULL,
    service_id uuid CONSTRAINT chk_reservation_service_required NOT NULL,
    party_size integer CONSTRAINT chk_reservation_party_size_required NOT NULL,
    projected_value_cents bigint CONSTRAINT chk_reservation_projected_value_required NOT NULL,
    final_value_cents bigint CONSTRAINT chk_reservation_final_value_required NOT NULL,
    pending_balance_cents bigint CONSTRAINT chk_reservation_pending_balance_required NOT NULL,
    credit_balance_cents bigint CONSTRAINT chk_reservation_credit_balance_required NOT NULL,
    reservation_status text CONSTRAINT chk_reservation_status_required NOT NULL,
    payment_status text CONSTRAINT chk_reservation_payment_status_required NOT NULL,
    payment_type text CONSTRAINT chk_reservation_payment_type_required NOT NULL,
    payment_method text CONSTRAINT chk_reservation_payment_method_required NOT NULL,
    created_by uuid CONSTRAINT chk_reservation_created_by_required NOT NULL,
    created_at timestamptz CONSTRAINT chk_reservation_created_at_required NOT NULL,
    CONSTRAINT pk_reservation PRIMARY KEY (reservation_id),
    CONSTRAINT fk_reservation_customer FOREIGN KEY (customer_id)
        REFERENCES commercial_reservation.customer (customer_id) ON DELETE RESTRICT,
    CONSTRAINT fk_reservation_service FOREIGN KEY (service_id)
        REFERENCES commercial_reservation.catalog_service (service_id) ON DELETE RESTRICT,
    CONSTRAINT chk_reservation_party_size CHECK (party_size >= 1),
    CONSTRAINT chk_reservation_projected_value CHECK (projected_value_cents >= 0),
    CONSTRAINT chk_reservation_final_value CHECK (final_value_cents >= 0),
    CONSTRAINT chk_reservation_pending_balance CHECK (pending_balance_cents >= 0),
    CONSTRAINT chk_reservation_credit_balance CHECK (credit_balance_cents >= 0),
    CONSTRAINT chk_reservation_status CHECK (
        reservation_status IN ('PENDING_PAYMENT', 'CONFIRMED', 'IN_EXECUTION', 'COMPLETED', 'CANCELLED')),
    CONSTRAINT chk_reservation_payment_status CHECK (
        payment_status IN ('NO_PAYMENT', 'PARTIAL', 'DEPOSIT_RECEIVED', 'BALANCE_PENDING', 'FULLY_PAID')),
    CONSTRAINT chk_reservation_payment_type CHECK (payment_type IN ('FULL_PAYMENT', 'DEPOSIT')),
    CONSTRAINT chk_reservation_payment_method CHECK (payment_method IN ('TRANSFER', 'CASH'))
);
