GRANT USAGE ON SCHEMA commercial_reservation TO commercial_reservation_writer;

-- DELETE is withheld on purpose (RN-06, plan.md D-04), except on the two technical tables of 004: physical deletion is not defined, so the
-- engine refuses it instead of trusting that no code path ever asks. The default privileges make
-- the catalog table of T-08 be born without it; see 001 for why ALL TABLES is also needed.
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA commercial_reservation TO commercial_reservation_writer;
ALTER DEFAULT PRIVILEGES IN SCHEMA commercial_reservation GRANT SELECT, INSERT, UPDATE ON TABLES TO commercial_reservation_writer;
