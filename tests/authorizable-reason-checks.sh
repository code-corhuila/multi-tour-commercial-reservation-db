#!/usr/bin/env bash
# Sourced by db-ci.sh after the outbox widening checks, on the same disposable PostgreSQL instance.
# HU-COM-004 -db (issue multi-tour-docs#171): authorizable_reason (03_tables/014, label authorizable-reason),
# its partial index of enabled reasons (10_indexes/011) and the UPDATE revoke on
# reservation_additional_discount (03_dcl/01_grants/006, label additional-discount-immutable).
# The last enabled reason of a tenant is protected by the service, not by a trigger. No DELETE for app or writer.
ar_table="$SCHEMA.authorizable_reason"
ar_ad_table="$SCHEMA.reservation_additional_discount"
ar_row() { # id, tenant, reason, status, created_at, updated_at (SQL literals; empty = default)
  echo "insert into $ar_table (authorizable_reason_id, tenant_id, reason, status, created_at, updated_at) values (${1:-gen_random_uuid()}, ${2:-'$tenant'}, ${3:-'Fidelizacion'}, ${4:-'ENABLED'}, ${5:-now()}, ${6:-now()})"
}
ar_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-004 reason: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
ar_accepted() { # SQL, description
  local status=0
  engine "begin; $1; rollback;" || status=$?
  check "HU-COM-004 reason: $2 is accepted" "$status"
}

echo 'HU-COM-004 reasons - base: the 41 changesets (40 and the outbox widening), without the reason table, its index and the revoke'
liquibase rollback-count 999 >/dev/null
db_labels='!authorizable-reason and !additional-discount-immutable'
liquibase update >/dev/null
ar_base="$(snapshot)"
check 'base holds exactly 41 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 41 ]; echo $?)"
check 'on that base the application user can still UPDATE the additional discount (the revoke is not there yet)' "$([ "$(sql "select has_table_privilege('$app','$ar_ad_table','UPDATE')")" = t ]; echo $?)"

echo 'HU-COM-004 reasons - probes written first: red before the changesets, green after'
db_labels='authorizable-reason'
liquibase update >/dev/null
check 'the table and its index bring the control table to 43 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 43 ]; echo $?)"
db_labels='additional-discount-immutable'
liquibase update >/dev/null
check 'the revoke brings the control table to 44 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 44 ]; echo $?)"

echo 'authorizable_reason'
check 'authorizable_reason exists only in the domain schema' "$([ "$(sql "select count(*) from pg_tables where tablename='authorizable_reason' and schemaname='$SCHEMA'")" = 1 ] && [ "$(sql "select count(*) from pg_tables where tablename='authorizable_reason' and schemaname='public'")" = 0 ]; echo $?)"
check 'it holds id, tenant, reason, status and the two moments, with their types' "$([ "$(cols_of authorizable_reason)" = 'authorizable_reason_id uuid NO,tenant_id uuid NO,reason text NO,status text NO,created_at timestamp with time zone NO,updated_at timestamp with time zone NO' ]; echo $?)"
check 'pk_authorizable_reason is the primary key' "$([ "$(sql "select count(*) from pg_constraint where conrelid=to_regclass('$ar_table') and contype='p' and conname='pk_authorizable_reason'")" = 1 ]; echo $?)"
check 'no DEFAULT anywhere: the service states every value' "$([ "$(sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='authorizable_reason' and column_default is not null")" = 0 ]; echo $?)"
ar_accepted "$(ar_row)" 'an enabled reason'
ar_accepted "$(ar_row '' '' '' "'DISABLED'")" 'a disabled reason'
ar_refusal "$(ar_row '' '' '' "'enabled'");" chk_authorizable_reason_status 'a lower-case status'
ar_refusal "$(ar_row '' '' '' "'REMOVED'");" chk_authorizable_reason_status 'a status outside ENABLED and DISABLED'
ar_refusal "$(ar_row '' '' "'   '");" chk_authorizable_reason_text_length 'a blank reason'
ar_refusal "$(ar_row '' '' "repeat('x', 256)");" chk_authorizable_reason_text_length 'a reason of 256 characters'
ar_accepted "$(ar_row '' '' "repeat('x', 255)")" 'a reason of 255 characters'
ar_refusal "$(ar_row '' NULL);" 'ERROR:  23502.*column "tenant_id"' 'a reason without tenant'
ar_refusal "$(ar_row '' '' NULL);" 'ERROR:  23502.*column "reason"' 'a reason without text'
engine "$(ar_row "'$(aid 1701)'" '' "'Fidelizacion'");" >/dev/null || true

echo 'duplicates: same text ignoring case and surrounding spaces, per tenant (AC-D4.7)'
check 'uq_authorizable_reason_tenant_text is a unique index on tenant and the normalized text' "$([ "$(sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and tablename='authorizable_reason' and indexname='uq_authorizable_reason_tenant_text' and indexdef like 'CREATE UNIQUE INDEX%' and indexdef like '%tenant_id, lower(btrim(reason))%'")" = 1 ]; echo $?)"
ar_refusal "$(ar_row);" uq_authorizable_reason_tenant_text 'the same text again'
ar_refusal "$(ar_row '' '' "'  FIDELIZACION '");" uq_authorizable_reason_tenant_text 'the same text in capitals with spaces'
ar_accepted "$(ar_row '' "'00000000-0000-0000-0000-000000000002'")" 'the same text for another tenant'
ar_accepted "$(ar_row '' '' "'Compensacion por inconveniente'")" 'a different text for the same tenant'

echo 'partial index of enabled reasons, and no trigger for the last one'
check 'idx_authorizable_reason_tenant_enabled is a partial index on tenant_id where status is ENABLED' "$([ "$(sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and indexname='idx_authorizable_reason_tenant_enabled' and indexdef like '%(tenant_id)%' and indexdef like '%ENABLED%'")" = 1 ]; echo $?)"
check 'no trigger on authorizable_reason: the last enabled reason is protected by the service' "$([ "$(sql "select count(*) from pg_trigger t where t.tgrelid=to_regclass('$ar_table') and not t.tgisinternal")" = 0 ]; echo $?)"
check 'a disabled reason can be written back (status update by the service)' "$([ "$(engine "update $ar_table set status='DISABLED', updated_at=now() where authorizable_reason_id='$(aid 1701)'" >/dev/null 2>&1; echo $?)" = 0 ]; echo $?)"

echo 'no DELETE on authorizable_reason; reader reads'
for ar_role in "$writer" "$app"; do
  check "no DELETE for $ar_role on authorizable_reason" "$([ "$(sql "select has_table_privilege('$ar_role','$ar_table','DELETE')")" = f ]; echo $?)"
  check "$ar_role keeps SELECT, INSERT, UPDATE on authorizable_reason" "$([ "$(sql "select has_table_privilege('$ar_role','$ar_table','SELECT') and has_table_privilege('$ar_role','$ar_table','INSERT') and has_table_privilege('$ar_role','$ar_table','UPDATE')")" = t ]; echo $?)"
done
ar_refusal "delete from $ar_table;" 'permission denied for table authorizable_reason' 'DELETE as the application user'
check 'the reader can read authorizable_reason' "$([ "$(sql "select has_table_privilege('$reader','$ar_table','SELECT')")" = t ]; echo $?)"

echo 'reservation_additional_discount is immutable (AC-D4.9)'
for ar_role in "$writer" "$app"; do
  check "no UPDATE for $ar_role on reservation_additional_discount" "$([ "$(sql "select has_table_privilege('$ar_role','$ar_ad_table','UPDATE')")" = f ]; echo $?)"
  check "$ar_role keeps SELECT and INSERT on reservation_additional_discount" "$([ "$(sql "select has_table_privilege('$ar_role','$ar_ad_table','SELECT') and has_table_privilege('$ar_role','$ar_ad_table','INSERT')")" = t ]; echo $?)"
  check "no DELETE for $ar_role on reservation_additional_discount" "$([ "$(sql "select has_table_privilege('$ar_role','$ar_ad_table','DELETE')")" = f ]; echo $?)"
done
engine "insert into $ar_ad_table (additional_discount_id, tenant_id, reservation_id, discount_percentage_bp, reason, applied_by, applied_at, previous_value_cents, amount_cents) values ('$(aid 1801)', '$tenant', '$(aid 1802)', 1000, 'Fidelizacion', '$actor', now(), 100000, 10000);" >/dev/null || true
check 'INSERT as the application user still works' "$([ "$(sql "select count(*) from $ar_ad_table where additional_discount_id='$(aid 1801)'")" = 1 ]; echo $?)"
ar_refusal "update $ar_ad_table set amount_cents = 1 where additional_discount_id='$(aid 1801)';" 'permission denied for table reservation_additional_discount' 'UPDATE as the application user'
ar_refusal "delete from $ar_ad_table where additional_discount_id='$(aid 1801)';" 'permission denied for table reservation_additional_discount' 'DELETE as the application user'
check 'the reader still reads the additional discount' "$([ "$(sql "select has_table_privilege('$reader','$ar_ad_table','SELECT')")" = t ]; echo $?)"
check 'a table created later still accepts UPDATE for the writer (the revoke is only on this table)' "$([ "$(sql "select count(*) from information_schema.role_table_grants where table_schema='$SCHEMA' and grantee='$writer' and privilege_type='UPDATE' and table_name='authorizable_reason'")" = 1 ]; echo $?)"

echo 'Idempotence, exact revert, reapply and a build from empty'
ar_second="$(liquibase update 2>&1)"; printf '%s\n' "$ar_second"
check 'a second update applies zero changesets' "$(printf '%s\n' "$ar_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "truncate $ar_table, $ar_ad_table" >/dev/null 2>&1 || true
liquibase rollback-count 3
ar_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$ar_base" "$ar_reverted"
check 'the three-change revert restores columns, constraints, indexes and privileges exactly' "$([ -n "$ar_base" ] && [ "$ar_reverted" = "$ar_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 41 ]; echo $?)"
check 'the reason table is gone and the UPDATE privilege is back after the revert' "$([ "$(sql "select to_regclass('$ar_table') is null")" = t ] && [ "$(sql "select has_table_privilege('$app','$ar_ad_table','UPDATE')")" = t ]; echo $?)"
db_labels=''
liquibase update >/dev/null
check 'the three changesets reapply to 44 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 44 ]; echo $?)"
liquibase rollback-count 999 >/dev/null
liquibase update >/dev/null
liquibase validate >/dev/null
check 'a full build from empty without any label filter applies exactly 44 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 44 ]; echo $?)"
