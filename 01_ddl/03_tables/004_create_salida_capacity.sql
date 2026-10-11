-- The capacity of a departure and the seats already held on it. It exists so that RN-05 (AC-5) has
-- something to compare against: the capacity of a departure may never be set below its held seats.
-- It is the minimal entity of plan.md DD-19, built in this story because the acceptance criterion
-- needs it. The allocations table and the reconciliation are not defined yet and are not built here.
--
-- RN-05 cannot be a CHECK, because it compares a value in this row with the capacity being written,
-- and a CHECK sees one row after the change. It is a protected update of the service, in one
-- transaction. What the engine can keep is that held_seats is never negative.
--
-- The table name and its columns are PROPOSED in 06-data, not yet confirmed. The lower bound of
-- effective_capacity is also only proposed, and 06-data orders not to implement it, so it has no CHECK.
-- No DEFAULT anywhere: the service decides every value. salida_id has no foreign key because the
-- departure belongs to operations-cost, another domain (Annex J.3.4).
CREATE TABLE commercial_reservation.salida_capacity (
    salida_capacity_id uuid    NOT NULL,
    tenant_id          uuid    NOT NULL,
    salida_id          uuid    NOT NULL,
    effective_capacity integer NOT NULL,
    held_seats         integer NOT NULL,
    CONSTRAINT pk_salida_capacity PRIMARY KEY (salida_capacity_id),
    CONSTRAINT chk_salida_capacity_held_seats CHECK (held_seats >= 0),
    -- one row per departure (ADR-004 D4); it is also the index that starts with tenant_id
    CONSTRAINT uq_salida_capacity_tenant_id_salida_id UNIQUE (tenant_id, salida_id)
);
