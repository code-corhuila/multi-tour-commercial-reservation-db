#!/usr/bin/env bash
# Sourced by db-ci.sh after the authorizable reason checks, on the same disposable PostgreSQL instance.
# HU-COM-005 -db (issue multi-tour-docs#171): the acceptance of the terms is stored on customer itself
# (PDR RN-CLI-001), NOT in customer_sensitive_data, which HU-COM-019 purges. Changeset ddl-alter-019,
# label customer-terms. No terms version (declared debt) and no service_id on customer.
# Rows that existed before are backfilled with a temporary DEFAULT that is dropped right after.
ct_table="$SCHEMA.customer"
ct_row() { # terms_accepted, terms_accepted_at (SQL literals; empty = default)
  echo "insert into $ct_table (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status, terms_accepted, terms_accepted_at) values (gen_random_uuid(), '$tenant', 'Terms probe', now(), 'enc:v1:t', 'enc:v1:u', '{}'::jsonb, 'ACTIVE', ${1:-true}, ${2:-now()})"
}
ct_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-005 terms: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
ct_accepted() { # SQL, description
  local status=0
  engine "begin; $1; rollback;" || status=$?
  check "HU-COM-005 terms: $2 is accepted" "$status"
}

echo 'HU-COM-005 terms - base: the 49 changesets without the terms columns, with a customer that already exists'
liquibase rollback-count 999 >/dev/null
db_labels='!customer-terms and !HU-WRK-007 and !HU-COM-007 and !HU-COM-008'
liquibase update >/dev/null
check 'base holds exactly 49 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 49 ]; echo $?)"
sql "insert into $ct_table (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status) values ('$(aid 1901)', '$tenant', 'Existing customer', now(), 'enc:v1:e', 'enc:v1:f', '{}'::jsonb, 'ACTIVE')" >/dev/null 2>&1 || true
check 'the customer that exists before the change is there' "$([ "$(sql "select count(*) from $ct_table where customer_id='$(aid 1901)'")" = 1 ]; echo $?)"
ct_base="$(snapshot)"

echo 'HU-COM-005 terms - probes written first: red before the changeset, green after'
db_labels='customer-terms'
liquibase update >/dev/null
check 'ddl-alter-019 brings the control table to 50 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 50 ]; echo $?)"

echo 'columns'
check 'customer gains terms_accepted boolean NOT NULL and terms_accepted_at timestamptz NOT NULL' "$([ "$(sql "select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by column_name) from information_schema.columns where table_schema='$SCHEMA' and table_name='customer' and column_name like 'terms%'")" = 'terms_accepted boolean NO,terms_accepted_at timestamp with time zone NO' ]; echo $?)"
check 'neither column keeps a DEFAULT: the service states the acceptance and its moment' "$([ "$(sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='customer' and column_name like 'terms%' and column_default is not null")" = 0 ]; echo $?)"
check 'the acceptance is not in customer_sensitive_data (HU-COM-019 purges that table)' "$([ "$(sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='customer_sensitive_data' and column_name like 'terms%'")" = 0 ]; echo $?)"
check 'no terms version and no service_id on customer (declared debt, decision of 2026-10-28)' "$([ "$(sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='customer' and (column_name like '%version%' or column_name = 'service_id')")" = 0 ]; echo $?)"
check 'the customer that existed before is backfilled as accepted, with a moment' "$([ "$(sql "select count(*) from $ct_table where customer_id='$(aid 1901)' and terms_accepted is true and terms_accepted_at is not null")" = 1 ]; echo $?)"

echo 'named constraints'
check 'chk_customer_terms_accepted_required and chk_customer_terms_accepted_at_required are NOT NULL constraints' "$([ "$(sql "select count(*) from pg_constraint where conrelid=to_regclass('$ct_table') and contype='n' and conname in ('chk_customer_terms_accepted_required','chk_customer_terms_accepted_at_required')")" = 2 ]; echo $?)"
check 'chk_customer_terms_accepted_true is a CHECK that terms_accepted is true' "$([ "$(sql "select count(*) from pg_constraint where conrelid=to_regclass('$ct_table') and contype='c' and conname='chk_customer_terms_accepted_true' and pg_get_constraintdef(oid) like '%terms_accepted = true%'")" = 1 ]; echo $?)"

echo 'the engine refuses a customer that did not accept (RN-CLI-001)'
ct_accepted "$(ct_row)" 'a customer that accepted, with the moment'
ct_refusal "$(ct_row false);" chk_customer_terms_accepted_true 'a customer that did not accept'
ct_refusal "$(ct_row NULL);" 'ERROR:  23502.*column "terms_accepted"' 'a null acceptance'
ct_refusal "$(ct_row true NULL);" 'ERROR:  23502.*column "terms_accepted_at"' 'an acceptance without its moment'
ct_refusal "insert into $ct_table (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status) values (gen_random_uuid(), '$tenant', 'No terms', now(), 'enc:v1:t', 'enc:v1:u', '{}'::jsonb, 'ACTIVE');" 'ERROR:  23502.*column "terms_accepted"' 'a customer that says nothing about the terms'

echo 'Idempotence, exact revert, reapply and a build from empty'
ct_second="$(liquibase update 2>&1)"; printf '%s\n' "$ct_second"
check 'a second update applies zero changesets' "$(printf '%s\n' "$ct_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
liquibase rollback-count 1
ct_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$ct_base" "$ct_reverted"
check 'the revert restores columns, constraints, indexes and privileges exactly, and keeps the customer' "$([ -n "$ct_base" ] && [ "$ct_reverted" = "$ct_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 49 ] && [ "$(sql "select count(*) from $ct_table where customer_id='$(aid 1901)'")" = 1 ]; echo $?)"
db_labels='!HU-WRK-007 and !HU-COM-007 and !HU-COM-008'
liquibase update >/dev/null
check 'the changeset reapplies to 50 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 50 ]; echo $?)"
liquibase rollback-count 999 >/dev/null
liquibase update >/dev/null
liquibase validate >/dev/null
check 'a full build from empty without any label filter applies exactly 50 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 50 ]; echo $?)"
