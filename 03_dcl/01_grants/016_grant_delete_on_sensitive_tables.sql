-- HU-COM-019 (-db) plan D-02, AC-D19.2 (DP-D19-1, PROPOSED default): the retention run deletes the sensitive rows of a reservation (PDR section 17, final deletion, not an overwrite with nulls).
-- DELETE is granted explicitly and per table, as in 004, so a table created later is still born without it. The companion sensitive table already holds it since 014 (HU-COM-012 replaces
-- companions), so only the customer sensitive table gains it here. The reader keeps no SELECT on either (005). The rule "only when due" needs the clock and the closing, so it is the
-- application's, not a trigger. The application user inherits the writer. Rollback revokes only what this changeset granted.
GRANT DELETE ON commercial_reservation.customer_sensitive_data TO commercial_reservation_writer;
