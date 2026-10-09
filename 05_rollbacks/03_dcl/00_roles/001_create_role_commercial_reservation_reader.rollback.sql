-- Roles belong to the cluster, not to the schema: dropping the schema does not remove them, and
-- without this the next update would fail with "role already exists".
DROP ROLE commercial_reservation_reader;
