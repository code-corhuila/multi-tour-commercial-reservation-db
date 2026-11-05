-- HU-COM-012 (-db) plan D-08, DP-D12-5 (PROPOSED default 2026-11-05): a modification replaces the companions of a reservation, which needs a delete. DELETE is
-- granted explicitly and per table, as in 004: the companion and its sensitive row (which holds a foreign key to it). The application filters by tenant; the
-- history row of the change stays as the immutable audit. The application user inherits the writer. Rollback revokes it.
GRANT DELETE ON commercial_reservation.reservation_companion, commercial_reservation.reservation_companion_sensitive_data TO commercial_reservation_writer;
