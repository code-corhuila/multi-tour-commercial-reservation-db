#!/usr/bin/env bash
# Sourced by db-ci.sh after discount-rule-checks.sh, on the same disposable PostgreSQL instance.
# HU-COM-005 (-db), tasks T-01, T-02 and the decided part of T-03 (issue multi-tour-docs#171).
# RULE OF THIS SLICE: a column whose decision is open is NOT built, and no probe here judges it.
# Built: customer(customer_id, tenant_id, full_name, created_at) and
#        reservation_companion(reservation_companion_id, tenant_id, reservation_id, full_name).
# Blocked, so absent: document, birth date or age, e-mail and hashes (DP-D5-1,2,3,5), terms
# acceptance (DP-D5-1), status (DP-D5-6), account link (DP-D5-4), companion contact (DP-D5-9),
# sensitive tables (DP-D5-7), outbox columns (DP-D5-8), retention (DP-D5-10), companion key to the
# reservation table (HU-COM-007). Probes of AC-D5.4, 6, 7, 8, 10, 11 wait for those decisions.
cust_table="$SCHEMA.customer"; comp_table="$SCHEMA.reservation_companion"
cust_total=29 # 27 of HU-COM-001..003 plus the two tables of this slice

echo 'HU-COM-005 T-01 - preconditions of HU-COM-001..003 (nothing is created; the first failure ends the run)'
precondition "schema, control table, outbox and idempotency key of HU-COM-001 are present" "$([ "$(sql "select (to_regnamespace('$SCHEMA') is not null and to_regclass('$CONTROL') is not null and to_regclass('$SCHEMA.outbox_event') is not null and to_regclass('$SCHEMA.idempotency_key') is not null)")" = t ]; echo $?)"
precondition "catalog_service, associated_establishment and discount_rule of HU-COM-001..003 are present" "$([ "$(sql "select count(*) from pg_tables where schemaname = '$SCHEMA' and tablename in ('catalog_service','associated_establishment','discount_rule')")" = 3 ]; echo $?)"
precondition "both roles exist and hold no DELETE outside the two technical tables" "$([ "$(sql "select count(*) from pg_roles where rolname in ('$reader','$writer')")" = 2 ] && [ "$(sql "select count(*) from information_schema.tables t where t.table_schema = '$SCHEMA' and t.table_name not in ('idempotency_key','outbox_event') and (has_table_privilege('$writer', format('%I.%I', t.table_schema, t.table_name), 'DELETE') or has_table_privilege('$app', format('%I.%I', t.table_schema, t.table_name), 'DELETE'))")" = 0 ]; echo $?)"
precondition "HU-COM-001..003 applied exactly 27 changesets" "$([ "$(sql "select count(*) from $CONTROL")" = 27 ]; echo $?)"
cust_base="$(snapshot)"

cust_insert() { # table, columns, values
  echo "insert into $1 ($2) values ($3)"
}
cust_row() { # tenant expression, name expression
  cust_insert "$cust_table" 'customer_id, tenant_id, full_name, created_at' "gen_random_uuid(), ${1:-'$tenant'}, ${2:-'Ana Perez'}, now()"
}
comp_row() { # tenant expression, name expression
  cust_insert "$comp_table" 'reservation_companion_id, tenant_id, reservation_id, full_name' "gen_random_uuid(), ${1:-'$tenant'}, gen_random_uuid(), ${2:-'Luis Gomez'}"
}
cust_not_null_refusal() { # SQL, constraint name, table, column
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-005 AC-D5.3 insert is refused for a null $4 (SQLSTATE 23502)" "$(printf '%s\n' "$answer" | grep -q "ERROR:  23502.*column \"$4\""; echo $?)"
  check "HU-COM-005 AC-D5.3 $2 exists in the catalog as a NOT NULL constraint" "$([ "$(sql "select count(*) from pg_constraint where conrelid = to_regclass('$3') and contype = 'n' and conname = '$2'" 2>/dev/null || true)" = 1 ]; echo $?)"
}

echo 'HU-COM-005 T-02 - probes written first: seen red before the changesets, green after'
db_labels='HU-COM-005 and customer-tables'
liquibase update
check "HU-COM-005 the two tables brought the control table to $cust_total changesets" "$([ "$(sql "select count(*) from $CONTROL")" = "$cust_total" ]; echo $?)"

# AC-D5.1
check 'AC-D5.1 customer and reservation_companion exist in the domain schema' "$([ "$(sql "select count(*) from pg_tables where schemaname = '$SCHEMA' and tablename in ('customer','reservation_companion')" 2>/dev/null || true)" = 2 ]; echo $?)"
check 'AC-D5.1 nothing of them appears in public' "$([ "$(sql "select count(*) from pg_tables where schemaname = 'public' and tablename in ('customer','reservation_companion')")" = 0 ]; echo $?)"
# AC-D5.2 (the decided part): exact columns, so that a column of an open decision fails this probe
cust_columns() { sql "select string_agg(column_name || ' ' || data_type || ' ' || is_nullable || ' ' || coalesce(column_default, '-'), ',' order by ordinal_position) from information_schema.columns where table_schema = '$SCHEMA' and table_name = '$1'" 2>/dev/null || true; }
check 'AC-D5.2 customer holds exactly the decided columns, none for an open decision' "$([ "$(cust_columns customer)" = 'customer_id uuid NO -,tenant_id uuid NO -,full_name text NO -,created_at timestamp with time zone NO -' ]; echo $?)"
check 'AC-D5.2 reservation_companion holds exactly the decided columns, none for an open decision' "$([ "$(cust_columns reservation_companion)" = 'reservation_companion_id uuid NO -,tenant_id uuid NO -,reservation_id uuid NO -,full_name text NO -' ]; echo $?)"
check 'AC-D5.2 primary keys pk_customer and pk_reservation_companion are named' "$([ "$(sql "select count(*) from pg_constraint where contype = 'p' and conname in ('pk_customer','pk_reservation_companion') and connamespace = '$SCHEMA'::regnamespace" 2>/dev/null || true)" = 2 ]; echo $?)"
check 'AC-D5.2 no CHECK, UNIQUE or foreign key exists yet: they wait for DP-D5-2, 3, 6 and HU-COM-007' "$([ "$(sql "select count(*) from pg_constraint where conrelid in (to_regclass('$cust_table'), to_regclass('$comp_table')) and contype in ('c','u','f')")" = 0 ]; echo $?)"
# AC-D5.3 (the decided part): tenant and name are mandatory, through psql as the application user
cust_not_null_refusal "$(cust_row NULL);" chk_customer_tenant_required "$cust_table" tenant_id
cust_not_null_refusal "$(cust_row "'$tenant'" NULL);" chk_customer_full_name_required "$cust_table" full_name
cust_not_null_refusal "$(comp_row NULL);" chk_reservation_companion_tenant_required "$comp_table" tenant_id
cust_not_null_refusal "$(comp_row "'$tenant'" NULL);" chk_reservation_companion_full_name_required "$comp_table" full_name
# AC-D5.5 (the decided part): the same name in two tenants is accepted and a scoped query sees one
iso_status=0
iso_answer="$(engine "begin; $(cust_row "'$tenant'" "'Same Name'"); $(cust_row "'$other_tenant'" "'Same Name'"); select count(*) as scoped from $cust_table where tenant_id = '$tenant' and full_name = 'Same Name'; rollback;" 2>&1)" || iso_status=$?
printf '%s\n' "$iso_answer"
check 'AC-D5.5 two tenants accept the same name' "$iso_status"
check 'AC-D5.5 a query scoped to tenant A returns exactly one of the two rows' "$(printf '%s\n' "$iso_answer" | grep -Eq '^ +1$'; echo $?)"
# AC-D5.9: the application user never deletes
for t in "$cust_table" "$comp_table"; do
  for r in "$writer" "$app"; do
    check "AC-D5.9 $r has no DELETE grant on ${t#$SCHEMA.}" "$([ "$(sql "select has_table_privilege('$r', '$t', 'DELETE')" 2>/dev/null || true)" = f ]; echo $?)"
  done
  del_answer="$(engine "delete from $t;" "$app" 2>&1 || true)"; printf '%s\n' "$del_answer"
  check "AC-D5.9 DELETE as the application user on ${t#$SCHEMA.} is denied by privilege" "$(printf '%s\n' "$del_answer" | grep -q "permission denied for table ${t#$SCHEMA.}"; echo $?)"
done
# AC-D5.12 / AC-D5.13: idempotent update, exact revert, reapply
cust_second="$(liquibase update 2>&1)"; printf '%s\n' "$cust_second"
check 'AC-D5.12 a second update applies zero changesets and the count is still 29' "$(printf '%s\n' "$cust_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets' && [ "$(sql "select count(*) from $CONTROL")" = "$cust_total" ]; echo $?)"
if [ "$(sql "select count(*) from $CONTROL")" = "$cust_total" ]; then
  liquibase rollback-count 2
  cust_reverted="$(snapshot)"
  printf 'HU-COM-001..003 schema MD5: %s\nAfter HU-COM-005 revert MD5: %s\n' "$cust_base" "$cust_reverted"
  check 'AC-D5.13 the revert removes both tables and leaves the schema exactly as 001-003 had it' "$([ -n "$cust_base" ] && [ "$cust_reverted" = "$cust_base" ] && [ "$(sql "select count(*) from pg_tables where schemaname = '$SCHEMA' and tablename in ('customer','reservation_companion')")" = 0 ] && [ "$(sql "select count(*) from $CONTROL")" = 27 ]; echo $?)"
  liquibase update
  check 'AC-D5.13 the slice applies again to the same 29 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = "$cust_total" ]; echo $?)"
else
  check 'AC-D5.13 the revert cannot be judged: the slice is not applied (no rollback is run, so 001-003 stay untouched)' 1
fi
db_labels=''
