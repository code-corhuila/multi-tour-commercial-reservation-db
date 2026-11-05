-- HU-COM-012 (-db) plan D-08, DP-D12-4 (PROPOSED default 2026-11-05): a modification recomputes the discount lines fixed at creation, so the three amount columns
-- must be rewritable. 008 withdrew UPDATE on the whole table; this grants it back on these three columns only, so the type, the value, the rule copy and every
-- other column stay immutable. The application user inherits the writer. Rollback revokes the column privileges.
GRANT UPDATE (base_cents, amount_cents, subtotal_cents) ON commercial_reservation.reservation_fixed_discount TO commercial_reservation_writer;
