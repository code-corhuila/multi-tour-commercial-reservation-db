# HU-COM-003 T-07 execution record

Date: 2026-11-02 (run started 19:19 UTC, last Liquibase call 19:41 UTC)  
Branch: `test/hu-com-002-dev-db-record-refresh`, from `origin/develop` at `e4c3a0c522ccea8438060396429a805a1e34f6ce`  
Command: `bash tests/db-ci.sh` from the repository root (PostgreSQL 18 in Docker, Liquibase 5.0.4, Java 21.0.11). Exit status: 0. `bash tests/check-structure.sh` printed `OK: structure check passed`.

This record replaces the one of 2026-10-28 (274 lines ok). That one said `T-06 not verified, no changeset`; the changesets of T-06 are now merged (`04_alter/008` coverage and cap, `04_alter/009` codes and dates; see below), so T-06 is covered here.

## Result of the whole run

1152 lines `ok`, no line `FAIL`, exit status 0, final line `PASS: database CI entrypoint is green locally; remote GitHub workflow has not been run.` The full build has 85 changesets (`the changeset reapplies to 85 changesets`); the count covers every slice the script runs, not only HU-COM-003. Line numbers are lines of the run output of 2026-11-02; that output is not versioned, so the check names are the durable evidence.

## Section 8 steps (the base story: 23 -> 27 changesets)

| Step | Printed heading and lines | What it printed | Verdict |
|---|---|---|---|
| 1 | line 1161 `T-07 STEP 1 - rebuild prerequisite HU-COM-001 + HU-COM-002 (23)` | lines 1257 to 1259: `T-01 schema, own control table, outbox, writer and no business DELETE exist`, the application user inherits the writer, `T-01 prior stories applied exactly 23 changesets` | ok |
| 2 | `T-07 STEP 2` | line 1295 `AC-D3.1 discount_rule exists only in commercial_reservation` | ok |
| 3 | `T-07 STEP 3` | lines 1317 and 1318: `AC-D3.2/6 exact confirmed columns and mandatory UUID tenant; open decisions absent`, `DP-07 status has no CHECK; DP-08 priority has no UNIQUE` | ok |
| 4 | `T-07 STEP 4` | lines 1331 to 1465: invalid inserts refused by `chk_discount_rule_starts_on_required`, `..._ends_on_required`, `chk_discount_rule_validity`, `chk_discount_rule_calculation_base`, `chk_discount_rule_value`, `chk_discount_rule_percentage`, `chk_discount_rule_amount`, `chk_discount_rule_type`, `chk_discount_rule_priority`, `chk_discount_rule_tenant_required` | ok |
| 5 | `T-07 STEP 5` | lines 1469 to 1486: `AC-D3.7` no DELETE grant and DELETE denied by privilege for `commercial_reservation_writer` and `commercial_reservation_app` | ok |
| 6 | line 1497 `T-07 STEP 6 - EXPLAIN real tenant validity query with selective fixtures` | line 1513 `AC-D3.9 planner uses idx_discount_rule_tenant_validity without disabling sequential scan`; line 1514 `T-03 tenant-only index exists with its declared columns` | ok |
| 7 | line 1773 `T-07 STEP 7` | line 1806 `AC-D3.10 second full update applies zero changesets`; line 1807 `HU-COM-003 adds exactly four changesets (23 -> 27)`; lines 1835 to 1845: the rollback is refused with `Cannot revert outbox generalization while discount rule events remain`; lines 1944 to 1947: MD5 `9f78d67e3320d1258794dad9fe1ed534` before and after the four-change revert (`AC-D3.11`); line 2244 `full reapply restores all 27 changesets` | ok |
| 8 | line 2245 `T-07 STEP 8 - db-ci.sh / db-ci.yml entrypoint result` | line 2246 `PASS: database CI entrypoint is green locally; remote GitHub workflow has not been run.` | local only; remote not run |

## T-05 (outbox for discount rules)

Lines 1561 to 1649: for `DiscountRuleChanged` create, update and inactivate, the ROLLBACK leaves neither the rule change nor the event, and the COMMIT leaves exactly one correct event with full snapshots, all as `commercial_reservation_app`. All `ok`; lines 1756 and 1772 add `fk_outbox_event_discount_rule` and `D-10 no trigger writes rule events`.

## T-06 (the columns that waited for `G-A`, now merged)

| Decision | Printed check names and lines | Revert and reapply | Verdict |
|---|---|---|---|
| DP-01 coverage, DP-05 cap (`04_alter/008`, `03_tables/013`, `10_indexes/010`) | line 3426 `base holds exactly 36 changesets`; line 3450 `the slice brings the control table to 39 changesets`; line 3452 `covers_all_services boolean NOT NULL and cap_cents bigint NULL`; lines 3466 and 3467 (no coverage refused, SQLSTATE 23502); lines 3489 to 3573 (`discount_rule_service`, primary key, two foreign keys, no DELETE); lines 3575 to 3617 (cap nullable, zero and negative refused by `chk_discount_rule_cap`) | line 3733 second update applies zero; lines 3755 to 3758 MD5 `de1f1ef8f9cd41275cb9317df600e6cf` before and after the three-change revert; line 3781 `the slice reapplies to 39 changesets`; line 3916 `a full build from empty without any label filter applies exactly 39 changesets` | ok |
| DP-02 calendar dates, DP-07 status, DP-08 priority | line 3630 and 3642 (unknown and lower-case status refused by `chk_discount_rule_status`); line 3664 `starts_on and ends_on are date, not timestamp`; line 3685 end before start refused by `chk_discount_rule_validity`; lines 3697 and 3698 equal priority accepted, no UNIQUE | same as above | ok |
| Codes and moments (`04_alter/009`) | line 4033 `base holds exactly 39 changesets`; line 4055 `ddl-alter-009 brings the control table to 40 changesets`; line 4056 old words migrated to the codes; line 4058 `created_at` and `updated_at` NOT NULL; lines 4104 to 4171 (old Spanish words refused by `chk_discount_rule_calculation_base` and `chk_discount_rule_type`) | lines 4273 to 4276 MD5 `2b9e1b77ccc705fef16b5068b01005e5` before and after, and the stored rows get their old words back | ok |

## What this run does NOT show

- Not verified: the integration test of the `-api` with the outbox of discount rules. The `-api` has since added the JDBC persistence of the discount rules and their outbox (`JdbcDiscountRules`), but this run did not use it; only the engine side was run, as the application role through `psql`.
- Not verified: the remote GitHub workflow `db-ci.yml` (step 8). GitHub Actions is blocked by billing.
- Not verified: the match of the columns with the portal fields (note of 2026-10-26 in `spec.md`); the run checks the columns of `spec.md` section 3 only.
- Not verified: that T-06 is complete in the sense of `tasks.md`; this run proves only the coverage, cap, dates, status, priority and codes listed above, and no check judges a decision that has no changeset.
