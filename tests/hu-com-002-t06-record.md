# HU-COM-002 T-06 execution record

Date: 2026-11-02 (run started 19:19 UTC, last Liquibase call 19:41 UTC)  
Branch: `test/hu-com-002-dev-db-record-refresh`, from `origin/develop` at `e4c3a0c522ccea8438060396429a805a1e34f6ce`  
Command: `bash tests/db-ci.sh` from the repository root (PostgreSQL 18 in Docker, Liquibase 5.0.4, Java 21.0.11). Exit status: 0. `bash tests/check-structure.sh` printed `OK: structure check passed`.

This record replaces the one of 2026-10-28 (274 lines ok), which is outdated against the current `develop`.

## Result of the whole run

The script printed 1152 lines `ok` and no line `FAIL`, ended with exit status 0 and the line `PASS: database CI entrypoint is green locally; remote GitHub workflow has not been run.` The last check printed `the changeset reapplies to 85 changesets`. The count covers every slice the script runs on this commit, not only HU-COM-002, which owns 7 of the 85 changesets (23 changesets with HU-COM-001). Line numbers are lines of the run output of 2026-11-02; that output is not versioned, so the check names are the durable evidence.

## What the run executed for HU-COM-002

| Task / criterion | Printed check names (abridged) and output lines | Verdict |
|---|---|---|
| T-01 preconditions of HU-COM-001 | lines 72 to 75: four `precondition:` lines (schema, control table, `commercial_reservation_app` without DELETE outside the two technical tables, `outbox_event` and `idempotency_key`) | ok (4) |
| T-02 `associated_establishment` (AC-D2.2 to AC-D2.5) | lines 146 to 166: exactly 8 columns; none of the six forbidden columns; no DEFAULT; HOTEL and RESTAURANT accepted; `typeOutsideHotelAndRestaurantIsRefusedByTheEngine`; `everyRowCarriesANonNullTenantId`; status, `commercial_information` and name-length refusals; `applicationUserCannotDeleteAnAssociation`; index `idx_associated_establishment_tenant_status_created` | ok (21) |
| T-03 `associated_establishment_image` (AC-D2.6, AC-D2.7) | lines 168 to 188: exactly 7 columns; `associationAndImageAreWrittenInOneTransaction` (commit and rollback); PNG, JPEG and WebP accepted; 819200 bytes accepted and 819201 refused; zero bytes, SVG, GIF and PDF refused; bad sha256 refused; one image per association; `fk_associated_establishment_image_association` ON DELETE RESTRICT with its index; DELETE refused by permission | ok (21) |
| T-04 / T-05 transitions and outbox | lines 200 to 288: `EstablishmentAssociationPublished`, `EstablishmentAssociationInactivated` and `EstablishmentAssociationReactivated`, each with rollback (neither event nor change) and commit (exactly one event with the association id and tenant); lines 299 and 310: no trigger writes the outbox, and a change without an application event writes no row | ok (14) |
| T-05 count | line 46 `HU-COM-002 T-05: an empty database applies exactly 23 changesets`; line 485 `the control table holds the 23 changesets` | ok (2) |
| T-05 revert | lines 563 to 564 (the 16 changesets build alone, neither HU-COM-002 table exists); lines 591 and 592 (an update applies exactly the 7 changesets of HU-COM-002); lines 618 to 621 (revert leaves 16, neither table, all HU-COM-001 tables survive, same columns, constraints, indexes and privileges); line 648 `a new update creates them again` | ok (9) |

## The steps of `T-06` (section 8), one by one

| Step | Printed heading | Verdict |
|---|---|---|
| 1 | line 751 `T-06 STEP 1 - apply this slice over HU-COM-001 (16 -> 23)`; the UPDATE SUMMARY printed after it says Run 7, Previously run 16, Filtered out 62, Total 85 (lines 778 to 783) | passed |
| 2 | line 814 `STEP 2 - inspect attributes and forbidden columns` | passed |
| 3 | line 839 `STEP 3 - a third establishment type`: refused | passed |
| 4 | line 851 `STEP 4 - a null tenant`: refused | passed |
| 5 | line 863 `STEP 5 - application DELETE`: permission denied | passed |
| 6 | line 871 `STEP 6 - association with image, without image, and explicit rollback`; line 899 prints `STEP 6 LIMITATION: DP-03 closed by models.md; the engine accepts no image, the API refuses it.` | passed, with the limitation printed by the script itself |
| 7 | line 914 `STEP 7 - inspect image content, type, size, checksum and tenant` | passed |
| 8 | line 925 `STEP 8 - three visibility transitions (same transaction, application role)` | passed |
| 9 | line 1034 `STEP 9`: `Database is up to date, no changesets to execute`, `Run: 0`, then `secondRunAppliesZeroChangesets: T-06 incremental second update applies zero` | passed |
| 10 | line 1067 `STEP 10 - revert exactly seven changesets to HU-COM-001`; lines 1117 to 1119: MD5 `60fed315e4e83d5129ebf5379a3d3815` before and after, `revertRemovesTheTwoTablesAndLeavesTheSchemaAsOneHadIt` | passed |
| 11 | line 1120 `STEP 11 - rule coverage and specification trace`; line 1122 `STEP 11 READY: all engine rule checks pass, including RN-11` | passed |

Also printed: `liquibase validate` answered `No validation errors found.` (line 65).

## What this run does NOT show

- Not verified: the remote GitHub workflow `db-ci.yml`. GitHub Actions is blocked by billing; the script printed `remote GitHub workflow has not been run`. This record is a local run only.
- Not verified: any integration with the real `-api` or `-portal`; the checks use `psql` and Liquibase only.
- Not verified: the limitation printed at step 6: the engine does not require an image for an association; the `-api` does.
