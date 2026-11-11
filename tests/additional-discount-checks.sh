#!/usr/bin/env bash
# Sourced by db-ci.sh after the HU-COM-003 checks, on the same disposable PostgreSQL instance.
# HU-COM-004 (-db spec 004-hu-com-004-view-and-apply-current-discounts): T-00 and T-02 only.
# Built: the prerequisites probe (T-00) and reservation_additional_discount without the composite
# key (T-02, plan D-02, D-03). NOT built, each waiting on a decision: authorizable_reason and its
# trigger (T-01, T-03: G-C, DP-04-3), the UPDATE revoke (T-05: DP-04-4), the composite foreign key
# (T-06: G-A, no reservations table), traceability (T-07: G-D), the cap column (DP-04-1) and any
# outbox change (DP-04-5). The checks below must not assert any of them.
ad_table="$SCHEMA.reservation_additional_discount"
ad_row() { # id, tenant, reservation, basis points, reason, author, moment, previous cents, amount cents (SQL literals; empty = default)
  echo "insert into $ad_table (additional_discount_id, tenant_id, reservation_id, discount_percentage_bp, reason, applied_by, applied_at, previous_value_cents, amount_cents) values (${1:-gen_random_uuid()}, ${2:-'$tenant'}, ${3:-'$(aid 7001)'}, ${4:-1000}, ${5:-'Fidelizacion'}, ${6:-'$actor'}, ${7:-now()}, ${8:-100000}, ${9:-10000})"
}
ad_refusal() { # SQL, constraint named in the engine answer
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-004 invalid insert is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
ad_not_null_refusal() { # SQL, NOT NULL constraint name, column
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-004 insert without $3 is refused (SQLSTATE 23502)" "$(printf '%s\n' "$answer" | grep -q "ERROR:  23502.*column \"$3\""; echo $?)"
  check "$2 exists in the catalog as a NOT NULL constraint" "$([ "$(sql "select count(*) from pg_constraint where conrelid=to_regclass('$ad_table') and contype='n' and conname='$2'")" = 1 ]; echo $?)"
}
ad_precondition() { # T-00: creates nothing; the first missing prerequisite ends the run there
  if [ "$2" -eq 0 ]; then echo "  ok    HU-COM-004 T-00 precondition: $1"
  else echo "  FAIL  HU-COM-004 T-00 precondition: $1"; echo "        T-00 ends here: HU-COM-001, HU-COM-003 and HU-COM-005 are not applied. Finish them first; this slice creates none of these."; exit 1; fi
}
echo 'HU-COM-004 T-00 - prerequisites left by HU-COM-001 and HU-COM-003 (nothing is created)'
liquibase rollback-count 999 >/dev/null
db_labels='!HU-COM-004 and !HU-COM-006 and !discount-persistence and !discount-rule-codes and !customer-terms and !HU-WRK-007 and !HU-COM-007'
liquibase update >/dev/null
ad_base_snapshot="$(snapshot)"
ad_precondition "the schema $SCHEMA exists" "$([ "$(sql "select count(*) from pg_namespace where nspname='$SCHEMA'")" = 1 ]; echo $?)"
ad_precondition "the control table $CONTROL exists and holds changesets" "$([ "$(sql "select count(*) from $CONTROL" 2>/dev/null || echo 0)" -gt 0 ]; echo $?)"
ad_precondition "the writer role exists and holds no DELETE outside the two technical tables" "$([ "$(sql "select count(*) from pg_roles where rolname='$writer'")" = 1 ] && [ "$(sql "select count(*) from information_schema.tables t where t.table_schema='$SCHEMA' and t.table_name not in ('idempotency_key','outbox_event') and has_table_privilege('$writer',format('%I.%I',t.table_schema,t.table_name),'DELETE')")" = 0 ]; echo $?)"
ad_precondition "idempotency_key and outbox_event are present" "$([ "$(sql "select count(*) from information_schema.tables where table_schema='$SCHEMA' and table_name in ('outbox_event','idempotency_key')")" = 2 ]; echo $?)"
ad_precondition "discount_rule (HU-COM-003) is present" "$([ "$(sql "select to_regclass('$SCHEMA.discount_rule') is not null")" = t ]; echo $?)"
echo "  info  G-A recorded, not closed: reservations table present = $(sql "select count(*) > 0 from pg_tables where schemaname='$SCHEMA' and tablename like 'reservation%' and tablename <> 'reservation_additional_discount'")"
check 'T-00 the prerequisites are exactly the 35 changesets of HU-COM-001..003 and HU-COM-005' "$([ "$(sql "select count(*) from $CONTROL")" = 35 ]; echo $?)"
check 'T-02 the additional-discount table does not exist before its changeset' "$([ "$(sql "select to_regclass('$ad_table') is null")" = t ]; echo $?)"

echo 'HU-COM-004 T-02 - apply the additional-discount changeset'
db_labels='HU-COM-004 and !outbox-widening and !authorizable-reason and !additional-discount-immutable and !HU-COM-006 and !customer-terms and !HU-WRK-007 and !HU-COM-007'
liquibase update
check 'AC-D4.1 the table exists in commercial_reservation and nothing new appears in public' "$([ "$(sql "select count(*) from pg_tables where tablename='reservation_additional_discount' and schemaname='$SCHEMA'")" = 1 ] && [ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasechangelog%'")" = 0 ]; echo $?)"
engine "select column_name, data_type, is_nullable from information_schema.columns where table_schema='$SCHEMA' and table_name='reservation_additional_discount' order by ordinal_position;"
expected='additional_discount_id uuid NO,tenant_id uuid NO,reservation_id uuid NO,discount_percentage_bp integer NO,reason text NO,applied_by uuid NO,applied_at timestamp with time zone NO,previous_value_cents bigint NO,amount_cents bigint NO'
actual="$(sql "select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position) from information_schema.columns where table_schema='$SCHEMA' and table_name='reservation_additional_discount'")"
check 'AC-D4.2 exact columns: identity, tenant, reservation and the six port fields; no cap column (DP-04-1)' "$([ "$actual" = "$expected" ]; echo $?)"
check 'RNF-D6 no foreign key at all yet (reservations does not exist; the author is plain data)' "$([ "$(sql "select count(*) from pg_constraint where conrelid=to_regclass('$ad_table') and contype='f'")" = 0 ]; echo $?)"
check 'RNF-D3 every constraint and index of the table has an explicit name' "$([ "$(sql "select count(*) from pg_constraint where conrelid=to_regclass('$ad_table') and contype in ('p','u','c','f') and conname !~ '^(pk|uq|chk|fk)_'")" = 0 ] && [ "$(sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and tablename='reservation_additional_discount' and indexname !~ '^(pk|uq|idx)_'")" = 0 ]; echo $?)"

echo 'HU-COM-004 T-02 - valid rows accepted, invalid rows refused by their named constraint'
ad_ok=0; engine "begin; $(ad_row); $(ad_row '' '' "'$(aid 7002)'" 10000 '' '' '' 100000 100000); rollback;" || ad_ok=$?
check 'a valid discount and a full 100 percent discount are accepted' "$ad_ok"
ad_refusal "$(ad_row '' '' '' 0);" chk_reservation_additional_discount_percentage
ad_refusal "$(ad_row '' '' '' 10001);" chk_reservation_additional_discount_percentage
ad_refusal "$(ad_row '' '' '' '' '' '' '' '' 0);" chk_reservation_additional_discount_amount
# PostgreSQL reports the first violated CHECK by name: with amounts that make previous_value fail, the amount checks fail first, so previous_value is also asserted from the catalog.
ad_refusal "$(ad_row '' '' '' '' '' '' '' 0 0);" chk_reservation_additional_discount_amount
ad_refusal "$(ad_row '' '' '' '' '' '' '' -5 10);" chk_reservation_additional_discount_amount_within_previous
check 'chk_reservation_additional_discount_previous_value exists as a CHECK on previous_value_cents > 0' "$([ "$(sql "select count(*) from pg_constraint where conrelid=to_regclass('$ad_table') and contype='c' and conname='chk_reservation_additional_discount_previous_value' and pg_get_constraintdef(oid) like '%previous_value_cents > 0%'")" = 1 ]; echo $?)"
ad_refusal "$(ad_row '' '' '' '' '' '' '' 100 101);" chk_reservation_additional_discount_amount_within_previous
ad_refusal "$(ad_row '' '' '' '' "'   '");" chk_reservation_additional_discount_reason_not_blank
ad_refusal "$(ad_row '' '' '' '' "''");" chk_reservation_additional_discount_reason_not_blank
ad_not_null_refusal "$(ad_row '' '' '' '' NULL);" chk_reservation_additional_discount_reason_required reason
ad_not_null_refusal "$(ad_row '' '' '' '' '' NULL);" chk_reservation_additional_discount_author_required applied_by
ad_not_null_refusal "$(ad_row '' '' '' '' '' '' NULL);" chk_reservation_additional_discount_moment_required applied_at
ad_not_null_refusal "$(ad_row '' NULL);" chk_reservation_additional_discount_tenant_required tenant_id
ad_not_null_refusal "$(ad_row '' '' NULL);" chk_reservation_additional_discount_reservation_required reservation_id

echo 'HU-COM-004 T-02 - one additional discount per reservation'
ad_seed=0; engine "$(ad_row);" || ad_seed=$?
check "the first additional discount of a reservation is accepted" "$ad_seed"
ad_refusal "$(ad_row);" uq_reservation_additional_discount_reservation
ad_refusal "$(ad_row '' "'$other_tenant'");" uq_reservation_additional_discount_reservation
ad_other=0; engine "$(ad_row '' '' "'$(aid 7003)'");" || ad_other=$?
check 'a different reservation still accepts its own additional discount' "$ad_other"

echo 'HU-COM-004 - DELETE stays withheld (inherited from HU-COM-001, plan D-08); UPDATE is NOT asserted (DP-04-4)'
for role in "$writer" "$app"; do
  check "$role holds no DELETE on the table" "$([ "$(sql "select has_table_privilege('$role','$ad_table','DELETE')")" = f ]; echo $?)"
  ad_answer="$(engine "delete from $ad_table;" "$role" 2>&1 || true)"; printf '%s\n' "$ad_answer"
  check "DELETE as $role is denied by privilege" "$(printf '%s\n' "$ad_answer" | grep -q 'permission denied for table reservation_additional_discount'; echo $?)"
done

echo 'HU-COM-004 T-02 - second run, exact revert and reapply (AC-D4.12, AC-D4.13)'
ad_second="$(liquibase update 2>&1)"; printf '%s\n' "$ad_second"
check 'AC-D4.12 a second update applies zero changesets' "$(printf '%s\n' "$ad_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
check 'HU-COM-004 adds exactly one changeset (35 -> 36)' "$([ "$(sql "select count(*) from $CONTROL")" = 36 ]; echo $?)"
liquibase rollback-count 1
check 'AC-D4.13 the table is gone and the 35 earlier changesets remain' "$([ "$(sql "select to_regclass('$ad_table') is null")" = t ] && [ "$(sql "select count(*) from $CONTROL")" = 35 ]; echo $?)"
check 'AC-D4.13 the schema is exactly as HU-COM-005 left it (columns, constraints, indexes, privileges)' "$([ -n "$ad_base_snapshot" ] && [ "$(snapshot)" = "$ad_base_snapshot" ]; echo $?)"
db_labels='!discount-persistence and !discount-rule-codes and !outbox-widening and !authorizable-reason and !additional-discount-immutable and !HU-COM-006 and !customer-terms and !HU-WRK-007 and !HU-COM-007'
liquibase update
check 'full build from the 35 plus HU-COM-004 reaches 36 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 36 ]; echo $?)"
if [ "$fail" -eq 0 ]; then echo 'PASS: HU-COM-004 T-00 and T-02 checks are green locally; remote workflow not run.'
else echo 'FAIL: at least one HU-COM-004 check failed.'; fi
