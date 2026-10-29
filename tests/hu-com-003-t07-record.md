# HU-COM-003 T-07 execution record

Date: 2026-10-28 (run started 03:34 UTC)  
Branch: `test/hu-com-002-dev-db-ci-record-and-hu-com-003-record`, from `origin/develop` at `458de1e86f11362f91352b805967991a09921bc1`  
Command: `bash tests/db-ci.sh` from the repository root (PostgreSQL 18 in Docker, Liquibase 5.0.4, Java 21.0.11). Exit status: 0.

This record replaces the one of 2026-10-11, which said `NOT RUN` because `spec.md` was missing and the Docker CLI stopped responding. Both reasons are gone: the run reached the end.

## Result of the whole run

274 lines `ok`, 0 lines `FAIL`, exit status 0 (all slices the script runs on this commit, including HU-COM-001, 002 and 005). The lines below are copied from the script output.

## Section 8 steps

| Step | Script section | What it printed | Verdict |
|---|---|---|---|
| 1 | `HU-COM-003 T-07 STEP 1 - rebuild prerequisite HU-COM-001 + HU-COM-002 (23)` | `Already ran: 23`; `T-01 prior stories applied exactly 23 changesets` | ok |
| 2 | `T-07 STEP 2` | `AC-D3.1 discount_rule exists only in commercial_reservation` | ok |
| 3 | `T-07 STEP 3` | 11 columns listed from `information_schema` (`discount_percentage_bp` and `discount_amount_cents` nullable, the rest `NO`); `AC-D3.2/6 exact confirmed columns and mandatory UUID tenant; open decisions absent`; `DP-07 status has no CHECK; DP-08 priority has no UNIQUE` | ok |
| 4 | `T-07 STEP 4 - six invalid inserts rejected by their named constraints` | refused by `chk_discount_rule_starts_on_required`, `..._ends_on_required`, `chk_discount_rule_validity`, `chk_discount_rule_calculation_base`, `chk_discount_rule_value`, `chk_discount_rule_percentage`, `chk_discount_rule_amount`, `chk_discount_rule_type`, `chk_discount_rule_priority`, `chk_discount_rule_tenant_required` | ok |
| 5 | `T-07 STEP 5` | `AC-D3.7` DELETE denied by privilege for `commercial_reservation_writer` and `commercial_reservation_app` | ok |
| 6 | `T-07 STEP 6 - EXPLAIN real tenant validity query` | `AC-D3.9 planner uses idx_discount_rule_tenant_validity without disabling sequential scan`; `T-03 tenant-only index exists with its declared columns` | ok |
| 7 | `T-07 STEP 7` | `AC-D3.10 second full update applies zero changesets`; `HU-COM-003 adds exactly four changesets (23 -> 27)`; protected outbox rollback refused while events remain; `AC-D3.11 four-change revert restores exact columns/constraints/indexes/privileges` (MD5 `9f78d67e3320d1258794dad9fe1ed534`); `HU-COM-003 reapplies to the identical 27-changeset schema` | ok |
| 8 | `T-07 STEP 8 - db-ci.sh / db-ci.yml entrypoint result` | `PASS: database CI entrypoint is green locally; remote GitHub workflow has not been run.` | local only |

## T-05 (outbox for discount rules)

`HU-COM-003 T-05 - application-written full previous/new state and atomicity`: for `DiscountRuleChanged` create, update and inactivate, the ROLLBACK leaves neither rule change nor event, and the COMMIT leaves exactly one correct event with full snapshots, all as the application role. Also `chk_outbox_event_exactly_one_aggregate` and `fk_outbox_event_discount_rule` refuse invalid events, and `D-10 no trigger writes rule events`. All `ok`.

## What this run does NOT show

- Not verified: the integration test of the `-api` with the outbox of discount rules (T-05). The `-api` has no discount code; only the engine side was run, as the application role through `psql`.
- Not verified: the remote GitHub workflow `db-ci.yml` (see step 8).
- Not verified: T-06 (waits for `G-A`, `DP-01`, `DP-04` to `DP-08`); no changeset exists, so nothing was run.
- Not verified: the match of the columns with the portal fields (note of 2026-10-26 in `spec.md`); the run checks the columns of `spec.md` section 3 only.
