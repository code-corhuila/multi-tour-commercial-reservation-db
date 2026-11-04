#!/usr/bin/env bash
# Sourced by db-ci.sh after the customer-search checks, on the same disposable PostgreSQL instance.
# HU-COM-001 -db, gap G-E closed by default (docs 06-data, 2026-11-02): catalog_service.transport_rate_per_person_cents,
# nullable bigint, CHECK >= 0, NULL meaning not parametrized (RN-TRA-002, RN-10). Label transport-rate on the single changeset.
# Probes are written first: red before the changeset, green after (Annex J.1).
tr_t="$SCHEMA.catalog_service"
tr_sql() { sql "$1" 2>/dev/null || true; }
tr_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-001 transport rate: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}

echo 'HU-COM-001 transport rate - base: the changesets that exist before the column'
liquibase rollback-count 999 >/dev/null
db_labels='!transport-rate and !HU-COM-011 and !discount-rule-stackable and !HU-COM-016'
liquibase update >/dev/null
tr_base="$(snapshot)"
check 'base holds exactly 86 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 86 ]; echo $?)"
check 'on that base catalog_service has no transport_rate_per_person_cents' "$([ "$(tr_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='catalog_service' and column_name='transport_rate_per_person_cents'")" = 0 ]; echo $?)"

echo 'HU-COM-001 transport rate - probes written first: red before the changeset, green after'
db_labels='transport-rate'
liquibase update >/dev/null
check 'the column brings the control table to 87 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 87 ]; echo $?)"

echo 'the column (RN-10, gap G-E)'
check 'transport_rate_per_person_cents is bigint and nullable' "$([ "$(tr_sql "select data_type || ' ' || is_nullable from information_schema.columns where table_schema='$SCHEMA' and table_name='catalog_service' and column_name='transport_rate_per_person_cents'")" = 'bigint YES' ]; echo $?)"
check 'the column has no DEFAULT: NULL means not parametrized, nobody chose a value' "$([ "$(tr_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='catalog_service' and column_name='transport_rate_per_person_cents' and column_default is not null")" = 0 ]; echo $?)"
check 'the CHECK is named chk_catalog_service_transport_rate_per_person_cents and states >= 0' "$([ "$(tr_sql "select pg_get_constraintdef(oid) from pg_constraint where conname='chk_catalog_service_transport_rate_per_person_cents' and conrelid='$tr_t'::regclass")" = 'CHECK (((transport_rate_per_person_cents IS NULL) OR (transport_rate_per_person_cents >= 0)))' ]; echo $?)"

echo 'the rows'
tr_a="$(aid 5001)"; tr_b="$(aid 5002)"; tr_c="$(aid 5003)"
engine "$(catalog_insert TRANSPORTATION "'Rate probe none'" ACTIVE 80000 50000 null false false "'$tr_a'")" >/dev/null || true
check 'a row that states no transport rate keeps NULL' "$([ "$(sql "select transport_rate_per_person_cents is null from $tr_t where service_id='$tr_a'")" = t ]; echo $?)"
engine "update $tr_t set transport_rate_per_person_cents = 25000 where service_id='$tr_a';" >/dev/null || true
check 'a positive rate is stored as whole cents' "$([ "$(sql "select transport_rate_per_person_cents from $tr_t where service_id='$tr_a'")" = 25000 ]; echo $?)"
engine "update $tr_t set transport_rate_per_person_cents = 0 where service_id='$tr_a';" >/dev/null || true
check 'a zero rate (transport at no charge) is accepted' "$([ "$(sql "select transport_rate_per_person_cents from $tr_t where service_id='$tr_a'")" = 0 ]; echo $?)"
tr_refusal "update $tr_t set transport_rate_per_person_cents = -1 where service_id='$tr_a';" chk_catalog_service_transport_rate_per_person_cents 'a negative rate'

echo 'Idempotence, exact revert and reapply'
tr_second="$(liquibase update 2>&1)"; printf '%s\n' "$tr_second"
check 'a second update applies zero changesets' "$(printf '%s\n' "$tr_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "delete from $tr_t where service_id in ('$tr_a','$tr_b','$tr_c')" >/dev/null 2>&1 || true
liquibase rollback-count 1
tr_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$tr_base" "$tr_reverted"
check 'the one-change revert restores the schema exactly and leaves 86 changesets' "$([ -n "$tr_base" ] && [ "$tr_reverted" = "$tr_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 86 ]; echo $?)"
db_labels='transport-rate'
liquibase update >/dev/null
check 'the changeset reapplies to 87 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 87 ]; echo $?)"
