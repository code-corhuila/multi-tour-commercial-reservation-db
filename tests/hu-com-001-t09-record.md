# HU-COM-001 T-09 execution record

Date: 2026-10-28 (run started 16:51 UTC, ended 17:01 UTC)  
Branch: `test/hu-com-001-dev-db-ci-record`, from `origin/develop` at `97acbef4d6acfb1602f30ac317ca667a6d19dc9d`  
Command: `bash tests/db-ci.sh` from the repository root (PostgreSQL 18 in Docker, Liquibase 5.0.4, Java 21.0.11). Exit status: 0.

## Result of the whole run

The script printed 364 lines `ok` and 0 lines `FAIL`, and ended with exit status 0 and the line `PASS: HU-COM-004 T-00 and T-02 checks are green locally; remote workflow not run.` The count covers every slice the script runs on this commit (HU-COM-001, 002, 003, 004 and 005, 36 changesets in the full build), not only HU-COM-001. The lines below are copied from the script output.

## What the run executed for HU-COM-001

| Task / criterion | Script section and printed check names (abridged) | Verdict |
|---|---|---|
| T-02 and AC-D1.9, AC-D1.10 (the four steps of `db-ci.yml`) | `step 1 - update builds everything`; `step 2 - update again applies nothing`: `no changeset ran the second time`; `step 3 - rollback-count 999 leaves the database empty`: `the reader and the writer roles are gone`, `the application user, created by CI, is left alone`; `step 4 - update rebuilds`: `the schema commercial_reservation exists again` | ok |
| T-03 and AC-D1.1 (schema, nothing in `public`) | `the schema commercial_reservation exists`; `no object of the domain lives in public` | ok (2) |
| T-04 and AC-D1.11 (own control table) | `the control table databasechangelog_commercial_reservation exists`; `the default control table databasechangelog does not exist`; `a second domain with its own control table migrates without collision`; `this domain's control table is untouched by it` | ok (4) |
| T-05 and AC-D1.12 (runner only) | `T-05 - deploy/compose.yml holds only the runner`: `composed with the instance, the only service besides postgres is the runner`, runner points at the single instance, passes the control and lock tables of this domain, sits on the external `platform` network | ok (9) |
| T-06 and AC-D1.6 (roles, DELETE withheld) | `T-06 - roles, grants and DELETE withheld`: roles exist, `neither role can log in nor holds a password (Annex A rule 10)`, the application user inherits the writer, a later table accepts INSERT and UPDATE and `refuses DELETE by permission`, `no table but the two technical ones lets the writer or the application user DELETE` | ok (7) |
| T-07 and AC-D1.7 (idempotency key) | `T-07 - idempotency key and outbox`: `a 7 character key is refused by the engine`; `a 129 character key is refused by the engine`; `an 8 and a 128 character key are accepted`; `the same key inserted again is refused as a duplicate`; `the same key in the same tenant leaves a single row`; `the same key in two tenants leaves two rows` | ok |
| T-07 and AC-D1.8 (outbox) | outbox fields of the two catalog events, inactivation event accepted and unpublished, unknown event type refused, event that changes nothing refused, partial index for the relay; with the catalog: `activeChangeWritesItsOutboxRowInTheSameTransaction` for rollback (neither status nor event) and for commit (both) | ok |
| T-08 and AC-D1.2 to AC-D1.4 (`catalog_service`) | `T-08 - catalog_service`: `catalogTableHoldsTheStoryAttributes: the 12 columns exist...`; `catalogTableHoldsTheHighRiskMark`; `insertWithoutValueOrCostIsRefusedByTheEngine` (`no base_rate_cents` and `no base_operational_cost_cents`, both by NOT NULL); `closedValueSetsRefuseUnknownValues` (unknown `service_type`, unknown `catalog_status`); negative rate and negative cost refused; capacity rules; name length 0, 255 and 256; the application user INSERT and UPDATE accepted | ok (about 20) |
| T-08 and AC-D1.6 (DELETE on the catalog) | `the application user's DELETE on the catalog is refused by permission` | ok |
| T-10 (`salida_capacity`) | `capacityEntityHoldsCapacityAndNonNegativeHeldSeats` (6 columns, zero accepted, negative refused); one row per tenant and departure; `fk_salida_capacity_service` ON DELETE RESTRICT and its index; INSERT and UPDATE accepted, DELETE refused by permission. `step 5 - the service_id changesets roll back to the table as it was`: five original columns after the rollback, then `a new update brings the sixth column back` | ok |
| AC-D1.5 (tenant mandatory and indexed) | `everyTableCarriesAMandatoryIndexedTenantId: every table has a mandatory uuid tenant_id`; `...every table has an index that starts with tenant_id` | ok (2) |
| Annex A rules (names, ENUM, foreign keys) | `every constraint has an explicit name`; `every index has an explicit name`; `no closed value set is an ENUM and no foreign key leaves the schema` | ok (3) |

Also printed: `HU-COM-002 T-06 - liquibase validate` answered `No validation errors found.` After the HU-COM-002 revert the script printed `the 16 changesets of HU-COM-001 build alone, without the label HU-COM-002` (ok) and `HU-COM-002 T-05: all HU-COM-001 tables survive the seven-change revert` (ok).

## What this run does NOT show

- Not verified: the remote GitHub workflow `db-ci.yml` (GitHub Actions is blocked by billing; the script itself printed `remote workflow not run`). This record is a local run only.
- Not verified: any integration with the real `-api` or `-portal`; the checks use `psql` and Liquibase only.
- Not verified: the 14-changeset reading of `tasks.md` "T-09 evidence" (2026-10-09, `c88affa`). This run reflects 16 changesets for HU-COM-001 and 36 in total at the commit above; the old table is not replaced.
- Not verified: the two open items of `tasks.md` that are documentary (`models.md` marks of RN-02 to RN-05 and `modeling-conventions.md` names); this run reads no `06-data` file.
- Not verified: RN-10, because the column does not exist in the engine (blocked by G-E).
