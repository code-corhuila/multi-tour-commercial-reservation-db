-- HU-COM-009 (-db) plan D-13, DP-D9-4 (PROPOSED owner, debt DD-3): the due instants of a reservation. This story creates the table with the initial deadline;
-- HU-COM-011 adds the extension and freeze columns. A reservation has several deadlines over its life, so it is a table of its own and not columns of
-- reservation. The kinds are codes for the three labels of the dictionary. The instant the first row is written is a rule of the -api (OPEN).
-- The key to the reservation is simple (DP-D9-12, debt DD-7). At most one initial deadline per reservation is a partial unique in 10_indexes/025.
CREATE TABLE commercial_reservation.payment_deadline (
    payment_deadline_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_payment_deadline_tenant_required NOT NULL,
    reservation_id uuid CONSTRAINT chk_payment_deadline_reservation_required NOT NULL,
    deadline_kind text CONSTRAINT chk_payment_deadline_kind_required NOT NULL,
    due_at timestamptz CONSTRAINT chk_payment_deadline_due_at_required NOT NULL,
    CONSTRAINT pk_payment_deadline PRIMARY KEY (payment_deadline_id),
    CONSTRAINT fk_payment_deadline_reservation FOREIGN KEY (reservation_id)
        REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT,
    CONSTRAINT chk_payment_deadline_kind CHECK (deadline_kind IN ('INITIAL_PAYMENT', 'BALANCE', 'PENDING_DIFFERENCE'))
);
