-- HU-COM-006 (-db) docs issue #172, plan D-03 (PROPOSED, debt DD-1): the departure data the offer needs on the mirror
-- row of salida_capacity: when the departure starts and in which of its four states it is. Both are required (data-dictionary
-- salida_capacities: horaInicio, status). Instants are timestamptz (RFC 3339 UTC). The status holds English codes, like every
-- other status column of this schema; the api maps them to the Spanish display values.
-- NOT NULL without DEFAULT: the service decides the value. The changeset has a precondition that the table has no rows (DP-D6-2),
-- because a NOT NULL column added without a default to a populated table would fail in the middle of a deploy.
-- No end time, no vehicle ceiling and no last-applied marker (DP-D6-3, DP-D6-5). Existing constraints are untouched.
ALTER TABLE commercial_reservation.salida_capacity
    ADD COLUMN hora_inicio timestamptz NOT NULL,
    ADD COLUMN status text NOT NULL,
    ADD CONSTRAINT chk_salida_capacity_status CHECK (status IN ('SCHEDULED', 'IN_EXECUTION', 'FINALIZED', 'CANCELLED'));
