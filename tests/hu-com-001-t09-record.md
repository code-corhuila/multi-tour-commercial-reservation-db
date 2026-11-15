# HU-COM-001 T-09 execution record

Date: 2026-11-02 (run started 19:19 UTC, last Liquibase call 19:41 UTC)  
Branch: `test/hu-com-001-dev-db-record-refresh`, from `origin/develop` at `e4c3a0c522ccea8438060396429a805a1e34f6ce`  
Command: `bash tests/db-ci.sh` from the repository root (PostgreSQL 18 in Docker, Liquibase 5.0.4, Java 21.0.11). Exit status: 0. `bash tests/check-structure.sh` printed `OK: structure check passed`.

This record replaces the one of 2026-10-28 (364 lines ok, 36 changesets), which is outdated against the current `develop`.

## Result of the whole run

The script printed 1152 lines `ok` and no line `FAIL` (the only three lines of the output that contain the word are the failing-row detail of a refused insert with the status `FAILED`, not a check result). It ended with exit status 0 and the line `PASS: database CI entrypoint is green locally; remote GitHub workflow has not been run.` The last check printed `the changeset reapplies to 85 changesets`: the full build has 85 changesets, 16 of them of HU-COM-001. The count covers every slice the script runs on this commit (HU-COM-001 to HU-COM-010, HU-WRK-007 and the collaborator flag), not only HU-COM-001. Line numbers below are lines of the run output of 2026-11-02; that output is not versioned, so the check names are the durable evidence.

## What the run executed for HU-COM-001

| Task / criterion | Printed check names (abridged) and output lines | Verdict |
|---|---|---|
| T-02 and AC-D1.9, AC-D1.10 (the four steps of `db-ci.yml`) | line 3 `step 1 - update builds everything`; line 323 `no changeset ran the second time`; lines 366 to 369 (`the schema commercial_reservation is gone`, `the reader and the writer roles are gone`, `the application user, created by CI, is left alone`); line 413 `the schema commercial_reservation exists again` | ok |
| T-03 and AC-D1.1 (schema, nothing in `public`) | lines 67 and 68: `the schema commercial_reservation exists`, `no object of the domain lives in public` | ok (2) |
| T-04 and AC-D1.11 (own control table) | lines 69, 70, 650, 651: own control table exists, the default one does not, a second domain migrates without collision and leaves this table untouched | ok (4) |
| T-05 and AC-D1.12 (runner only) | lines 653 to 661: runner image carries the migrations, compose validates, only the runner besides postgres, waits for postgres, single instance, control and lock tables of this domain, external `platform` network | ok (9) |
| T-06 and AC-D1.6 (roles, DELETE withheld) | lines 77 to 84: roles exist, neither logs in nor holds a password, the application user inherits the writer, a later table accepts INSERT and UPDATE and `refuses DELETE by permission`, no table but the two technical ones allows DELETE | ok (7) |
| T-07 and AC-D1.7 (idempotency key) | lines 132 to 138: 7 and 129 character keys refused, 8 and 128 accepted, duplicate refused, one row per tenant and key, two tenants two rows, primary key of tenant and key | ok (7) |
| T-07 and AC-D1.8 (outbox) | lines 139 to 144: outbox fields, inactivation event accepted and unpublished, unknown type refused, event that changes nothing refused, partial index for the relay; lines 108 to 110: `activeChangeWritesItsOutboxRowInTheSameTransaction` rollback and commit | ok |
| T-08 and AC-D1.2 to AC-D1.4 (`catalog_service`) | lines 86 to 106: 12 columns, `high_risk`, no defaults, `insertWithoutValueOrCostIsRefusedByTheEngine` (both NOT NULL), `closedValueSetsRefuseUnknownValues`, negative rate and cost, capacity rules, name 0, 255 and 256 characters, INSERT and UPDATE accepted, DELETE refused by permission | ok (21) |
| T-10 (`salida_capacity`) | lines 112 to 129: 6 columns, held seats zero accepted and negative refused, one row per tenant and departure, `fk_salida_capacity_service` ON DELETE RESTRICT with its index, DELETE refused by permission; lines 448, 449, 484: five original columns after the rollback, then `a new update brings the sixth column back` | ok |
| AC-D1.5 (tenant mandatory and indexed) | lines 311 and 312: `everyTableCarriesAMandatoryIndexedTenantId` (mandatory uuid and index that starts with `tenant_id`) | ok (2) |
| Annex A rules (names, ENUM, foreign keys) | lines 313 to 315: explicit constraint names, explicit index names, no ENUM and no foreign key leaving the schema | ok (3) |
| Revert and reapply evidence (HU-COM-002 over HU-COM-001) | line 485 `the control table holds the 23 changesets`; lines 563 to 564 `the 16 changesets of HU-COM-001 build alone, without the label HU-COM-002`; lines 618 to 621: after the seven-change revert the 16 changesets and every HU-COM-001 table remain, with the same columns, constraints, indexes and privileges; line 1119 MD5 `60fed315e4e83d5129ebf5379a3d3815` before and after | ok |

Also printed: `HU-COM-002 T-06 - liquibase validate` answered `No validation errors found.` (line 65).

## The thirteen steps of `spec.md` section 8, one by one

| Step | Verdict | Proof in the log |
|---|---|---|
| 1 to 3 (empty build, second run, full revert and rebuild) | passed locally | lines 3, 323, 366 to 369, 413 |
| 4 (nothing in `public`) | passed | line 68 |
| 5 (RN-01 refused through `psql`) | passed | lines 91 to 102 |
| 6 (DELETE refused by permission) | passed | lines 82, 84, 106 |
| 7 (tenant mandatory and indexed) | passed | lines 311, 312 |
| 8 (idempotency key) | passed | lines 132 to 137 |
| 9 (own control tables) | passed | lines 69, 70, 650, 651 |
| 10 (no instance, no volume, no extension in this repository) | passed for `deploy/compose.yml`: only the runner; not verified for "no extension" in the migration set (no check prints it) | lines 653 to 661 |
| 11 (no ENUM, no foreign key to another domain) | passed | line 315 |
| 12 (every rule marked engine is in the engine) | passed for the rules the `tests/db-ci.sh` section `HU-COM-002 T-06 STEP 11` maps (line 1122 `STEP 11 READY`); the mapping of the marks in `06-data/models.md` is documentary and was not checked | line 1122 |
| 13 (Annex A list) | partly: the script covers names, ENUM, foreign keys, tenant, roles, own control table and the four steps; the eight boxes of Annex A were not ticked by a separate check | lines 67 to 84, 313 to 315 |

## What this run does NOT show

- Not verified: the remote GitHub workflow `db-ci.yml`. GitHub Actions is blocked by billing; the script itself printed `remote GitHub workflow has not been run`. This record is a local run only.
- Not verified: any integration with the real `-api` or `-portal`; the checks use `psql` and Liquibase only.
- Not verified: the instance of `multi-tour-infra-postgres` brought up from zero (the script uses its own throwaway container).
- Not verified: the two documentary items of `tasks.md` (`models.md` marks and `modeling-conventions.md` names); this run reads no `06-data` file.
- Not verified: RN-10, because the column does not exist in the engine (blocked by G-E).
