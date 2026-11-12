#!/usr/bin/env bash
# Sourced by db-ci.sh after decision-resume-checks.sh, on the same disposable PostgreSQL instance, with the 179 changesets that exist before the slice.
# HU-COM-006 -db (docs spec 006, DP-16 and DD-8, answered by the Project Lead): the departure mirror stores the occurredAt of the last event it applied, so an older event never overwrites a newer
# state. One nullable column on salida_capacity, no DEFAULT (a row born before the marker has no value). Every changeset of the slice is labelled departure-order. Probes are written first:
# red before the changeset, green after (Annex J.1). The rows of the probes are removed by the owner at the end.
do_t="$SCHEMA.salida_capacity"
do_svc="$(aid 8403)"; do_s1="$(aid 8420)"; do_s2="$(aid 8421)"
do_sql() { sql "$1" 2>/dev/null || true; }
do_accepted() { # SQL, description
  local status=0
  engine "$1" >/dev/null || status=$?
  check "HU-COM-006 db: $2 is accepted" "$status"
}
do_row() { # departure id, marker literal
  echo "insert into $do_t (salida_capacity_id, tenant_id, salida_id, service_id, effective_capacity, held_seats, hora_inicio, status${3:+, $3}) values (gen_random_uuid(), '$tenant', '$1', '$do_svc', 10, 0, now() + interval '30 days', 'SCHEDULED'${2:+, $2})"
}

echo 'HU-COM-006 db departure order - base: the 179 changesets that exist before the slice, with the probe rows'
liquibase rollback-count 999 >/dev/null
db_labels='!departure-order and !exceptional-access-use and !reservation-confirmed-value and !payment-parameters-changed and !account-session-cutoff and !restricted-access-reason'
liquibase update >/dev/null
do_base="$(snapshot)"
check 'base holds exactly 179 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 179 ]; echo $?)"
sql "insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values ('$do_svc', '$tenant', 'TOUR', 'Order probe tour', 'ACTIVE', 150000, 90000, 12, false, false, now(), now())" >/dev/null 2>&1 || true
engine "$(do_row "$do_s1")" >/dev/null || true
check 'a departure born before the marker exists on the base' "$([ "$(do_sql "select count(*) from $do_t where salida_id = '$do_s1'")" = 1 ]; echo $?)"

echo 'HU-COM-006 db departure order - probes written first: red before the changeset, green after'
db_labels='departure-order'
liquibase update >/dev/null
check 'the changeset of the slice brings the control table to 180' "$([ "$(sql "select count(*) from $CONTROL")" = 180 ]; echo $?)"

echo 'aDepartureKeepsTheOccurredAtOfTheLastEventItApplied (DP-16, DD-8)'
check 'last_event_occurred_at is a nullable timestamptz with no DEFAULT' "$([ "$(do_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='salida_capacity' and column_name='last_event_occurred_at' and data_type='timestamp with time zone' and is_nullable='YES' and column_default is null")" = 1 ]; echo $?)"
check 'the departure born before the marker keeps a null marker' "$([ "$(do_sql "select count(*) from $do_t where salida_id = '$do_s1' and last_event_occurred_at is null")" = 1 ]; echo $?)"
do_accepted "$(do_row "$do_s2" "'2026-11-01T10:00:00Z'" last_event_occurred_at)" 'a departure created with the occurredAt of its SalidaScheduled'
do_accepted "update $do_t set last_event_occurred_at = '2026-11-02T10:00:00Z' where tenant_id = '$tenant' and salida_id = '$do_s2' and (last_event_occurred_at is null or last_event_occurred_at < '2026-11-02T10:00:00Z')" 'the guarded update of a newer event'
check 'the newer marker is stored' "$([ "$(do_sql "select count(*) from $do_t where salida_id = '$do_s2' and last_event_occurred_at = '2026-11-02T10:00:00Z'")" = 1 ]; echo $?)"
check 'the guarded update of an older event changes no row' "$([ "$(do_sql "with u as (update $do_t set last_event_occurred_at = '2026-11-01T12:00:00Z' where tenant_id = '$tenant' and salida_id = '$do_s2' and (last_event_occurred_at is null or last_event_occurred_at < '2026-11-01T12:00:00Z') returning 1) select count(*) from u")" = 0 ]; echo $?)"

echo 'onlyThePlannedColumnIsAddedSecondRunAppliesZeroAndRevertLeavesNoTrace (AC-D16.1)'
check 'nothing new appears in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasechangelog%'")" = 0 ]; echo $?)"
do_second="$(liquibase update 2>&1)"; printf '%s\n' "$do_second"
check 'a second update applies zero changesets' "$(printf '%s\n' "$do_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "delete from $do_t where salida_id in ('$do_s1', '$do_s2'); delete from $SCHEMA.catalog_service where service_id = '$do_svc'" >/dev/null 2>&1 || true
do_n="$(sql "select count(*) from $CONTROL where labels ilike '%departure-order%'" 2>/dev/null || echo 0)"
liquibase rollback-count "$do_n"
do_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$do_base" "$do_reverted"
check 'the revert restores columns, constraints, indexes and privileges exactly and leaves 179 changesets' "$([ -n "$do_base" ] && [ "$do_reverted" = "$do_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 179 ]; echo $?)"
db_labels='departure-order'
liquibase update >/dev/null
check 'the changeset of the slice reapplies to 180' "$([ "$(sql "select count(*) from $CONTROL")" = 180 ]; echo $?)"
