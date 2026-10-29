# HU-COM-002 T-06 execution record

Date: 2026-10-28 (run started 03:34 UTC)  
Branch: `test/hu-com-002-dev-db-ci-record-and-hu-com-003-record`, from `origin/develop` at `458de1e86f11362f91352b805967991a09921bc1`  
Command: `bash tests/db-ci.sh` from the repository root (PostgreSQL 18 in Docker, Liquibase 5.0.4, Java 21.0.11). Exit status: 0.

## Result of the whole run

The script printed 274 lines `ok` and 0 lines `FAIL`, and ended with exit status 0. The count covers every slice the script runs on this commit (HU-COM-001, 002, 003 and 005), not only HU-COM-002. The lines below are copied from the script output.

## What the run executed for HU-COM-002

| Task / criterion | Script section and printed check names (abridged) | Verdict |
|---|---|---|
| T-01 preconditions of HU-COM-001 | `HU-COM-002 T-01`: four `precondition:` lines (schema, control table, `commercial_reservation_app` without DELETE, `outbox_event` and `idempotency_key` present) | ok (4) |
| T-02 `associated_establishment` (AC-D2.2 to AC-D2.5) | `associationTableHoldsTheStoryAttributes: exactly the 8 columns...`; `none of the six forbidden columns ...`; `typeOutsideHotelAndRestaurantIsRefusedByTheEngine`; `everyRowCarriesANonNullTenantId`; status, name-length and `commercial_information` refusals; `applicationUserCannotDeleteAnAssociation` (`permission denied for table associated_establishment`); `the management listing has its index: idx_associated_establishment_tenant_status_created` | ok (20) |
| T-03 `associated_establishment_image` (AC-D2.6, AC-D2.7) | `imageRowHoldsContentTypeSizeChecksumAndTenant: exactly the 7 columns...`; `associationAndImageAreWrittenInOneTransaction`; `sizeAbove800KbOrTypeOutsidePngJpegWebpIsRefusedByTheEngine`; one image per association; `fk_associated_establishment_image_association` ON DELETE RESTRICT and its index; no DELETE for the application user | ok (21) |
| T-04 / T-05 association transitions and outbox | `visibilityChangeWritesItsOutboxRowInTheSameTransaction` for `EstablishmentAssociationPublished`, `EstablishmentAssociationInactivated` and `EstablishmentAssociationReactivated`, each with rollback (neither event nor change) and commit (exactly one event) as `commercial_reservation_app` | ok (12) |
| T-05 count | `HU-COM-002 T-05: an empty database applies exactly 23 changesets`; `HU-COM-002 T-05: all HU-COM-001 tables survive the seven-change revert` | ok (2) |
| T-06 steps 1 to 11 | `T-06 STEP 1` (16 -> 23: 7 changesets run, 6 filtered by label); `STEP 2` to `STEP 5` (attributes, third type, null tenant, DELETE); `STEP 6`, `STEP 7` (image); `STEP 8` (three transitions); `STEP 9` `secondRunAppliesZeroChangesets: T-06 incremental second update applies zero`; `STEP 10` `revertRemovesTheTwoTablesAndLeavesTheSchemaAsOneHadIt: T-06 MD5 matches HU-COM-001` (MD5 `60fed315e4e83d5129ebf5379a3d3815`); `STEP 11` `STEP 11 READY: all engine rule checks pass, including RN-11` | executed; verdicts are the `ok` lines above |

Also printed at the start: `liquibase validate` answered `No validation errors found.`

## What this run does NOT show

- Printed by the script itself at `T-06 STEP 6`: `STEP 6 LIMITATION: the engine accepts no image. DP-03 is open in the supplied spec; no closed decision is asserted here.`
- Not verified: the remote GitHub workflow `db-ci.yml` (the script printed `remote GitHub workflow has not been run`); this record is a local run only.
- Not verified: any integration with the real `-api` or `-portal`; the checks use `psql` and Liquibase only.
- Not verified: T-01 as a separate query recorded in a pull request; the four `precondition:` lines above are the only evidence.
