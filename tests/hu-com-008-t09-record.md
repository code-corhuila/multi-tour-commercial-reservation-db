# HU-COM-008 T-09 record

Date: 2026-11-04  
Branch: `docs/hu-com-008-t09-record`, from `origin/develop` at `bc054e34f697e9aa400c6e8e2ed151b89b3d548c` (full build of 123 changesets after HU-COM-016 slice 2)  
User story: https://github.com/code-corhuila/multi-tour-docs/issues/174 (Reserve from the digital channel)

This record writes down what the database CI covers for HU-COM-008 and what is known about its last full run. It does not report a new run: no run of `bash tests/db-ci.sh` was made to write it.

## What the story adds in the database

No table. Two changesets of `10_indexes`, both labelled `HU-COM-008`:

- `018_create_customer_account_unique_index.sql`: the partial unique index `uq_customer_tenant_id_account_id` on `(tenant_id, account_id)` where `account_id` is not null (one customer per account and tenant).
- `019_drop_customer_account_index.sql`: drops the old non-unique `idx_customer_tenant_account_id`.

Every other criterion is a probe over objects of HU-COM-001, 005 and 007 (plan D-06).

## What the CI covers

`tests/reserve-digital-checks.sh` is sourced by `tests/db-ci.sh` after the reservation checks, on the same disposable PostgreSQL instance. It prints 28 `check` lines, listed here by AC. The names are the durable evidence.

| AC | What is checked |
|---|---|
| AC-D8.1 | nothing new appears in `public` |
| AC-D8.2 | the same account value in another tenant is accepted; two customers without account in one tenant are accepted; `uq_customer_tenant_id_account_id` has the exact definition (unique, partial); the old index is gone and the new one is valid |
| AC-D8.3 | a reservation inserted through the creation path is `PENDING_PAYMENT` and `NO_PAYMENT` |
| AC-D8.4 | `held_seats` of the departure is unchanged after the reservation; no allocation row exists (that table belongs to HU-COM-009) |
| AC-D8.5 | a request key is accepted; the same key of the same tenant is refused by `pk_idempotency_key`; the same key in another tenant is accepted (these lines use the helpers `rs_accepted` and `rs_refusal`, not `check`) |
| AC-D8.6 | the list "mine" uses `idx_reservation_tenant_customer_created`, with more than one hundred reservations for the planner |
| AC-D8.7 | a query scoped to tenant and customer never returns another customer's reservation, and returns nothing under another tenant |
| AC-D8.8 | a failed transaction after the customer insert leaves no customer, reservation, key or event |
| AC-D8.9 | a committed confirmation leaves the customer, the reservation, the key, `CustomerRegistered` and `ReservationCreated`; no outbox column carries a document, contact or medical value |
| AC-D8.10 | neither the writer nor the application user holds DELETE on `customer` or `reservation` |
| AC-D8.11 | a second update applies zero changesets |
| AC-D8.12 | the two-change revert restores columns, constraints, indexes and privileges exactly; the old index is back and the unique one is gone; the two changesets reapply |

Control counts inside the script, on the staged schema of the story (the labels of later stories are excluded): 65 changesets before the story, 67 after, and 67 again after revert and reapply. These are not the counts of the full build.

## Last full run that can be cited

Full `bash tests/db-ci.sh` against a disposable PostgreSQL 18, as reported in the merged pull requests:

| Pull request | Merge commit | Reported result |
|---|---|---|
| db #63 (HU-COM-015 slice 1) | `24bd9bfce591894cebd4b6e96106be799ff63623` | exit 0, 0 failures, 1449 checks; full build of 112 changesets |
| db #60 (HU-COM-013) | `10946fcc6affa132ce77dfde4569cb6be3a55aee` | exit 0, no failed check; full build of 103 changesets |

At the merge commit of db #63, `tests/db-ci.sh` already sources `tests/reserve-digital-checks.sh`, so that run included the 28 checks of this story. The script has changed since then by two lines (label filters for later stories).

Since that run the branch gained 11 changesets (112 to 123) through the pull requests merged after it, the last being db #66. Db #66 reports a reduced harness (138 ok, 0 FAIL, exit 0) and says the full `db-ci.sh` was not run because of the shared Docker queue. So there is no full run of the 123-changeset tree.

## What is NOT run or NOT shown

- Not run: the remote workflow `db-ci.yml`; GitHub Actions is blocked by billing, so the green of the script is local only.
- Not run: a full `db-ci.sh` on the current 123-changeset tree.
- Not shown: the exact line numbers of the 28 checks in a log; the run output of db #63 is not versioned in this repository.
- Not shown: any integration with the real `-api` or `-portal`; the checks use `psql` and Liquibase only.
- Not shown by these probes: the concurrent registration of the same account; the refusal of the second one is handled in the `-api` (api #179) and tested there against the real schema.
