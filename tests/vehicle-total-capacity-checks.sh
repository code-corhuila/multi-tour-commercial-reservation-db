#!/usr/bin/env bash
# Sourced by db-ci.sh after rescheduling-proposed-notice-checks.sh, on the same disposable PostgreSQL instance, with every changeset that exists before the slice (counted at run time); the slice is one changeset, 048.
# HU-COM-006 -db, ND-08 and DP-D6-8 (PROPOSED default, owner Fernanda): salida_capacity keeps the total capacity of the vehicles assigned to the departure, as the last SalidaVehiclesChanged reported it (data-dictionary field vehicleCapacityCeiling,
# column vehicle_capacity_ceiling), so the service can recompute effective_capacity when the tour capacity changes (RN-SAL-001, H8) without a call to operations-cost. The column is nullable: a row born before it, or a departure with no vehicle event yet,
# has no total (NULL) and the service then leaves its effective capacity as it is. No DEFAULT and no backfill: the total cannot be derived from effective_capacity, which may be bound by the tour. A negative total is refused. Nothing else changes.
# The probes run as the superuser with the foreign keys switched off (session_replication_role = replica); the CHECK constraints under test still apply. The changeset is labelled vehicle-total-capacity.
# Probes are written first: red before the changeset, green after (Annex J.1).
vt_t="$SCHEMA.salida_capacity"; vt_svc="$(aid 9501)"; vt_key='chk_salida_capacity_vehicle_capacity_ceiling'
vt_row() { # salida id, then optional extra column and value (SQL text starting with a comma)
  echo "set session_replication_role = replica; insert into $vt_t (salida_capacity_id, tenant_id, salida_id, service_id, effective_capacity, held_seats, hora_inicio, status${2:+, vehicle_capacity_ceiling}) values (gen_random_uuid(), '$tenant', '$1', '$vt_svc', 20, 0, now() + interval '1 day', 'SCHEDULED'${3:+, $3})"
}
vt_sql() { sql "$1" 2>/dev/null || true; }
vt_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" postgres 2>&1 || true)"; printf '%s\n' "$answer"
  check "ND-08 db: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
vt_accepted() { # SQL, description
  local status=0
  engine "begin; $1; rollback;" postgres >/dev/null || status=$?
  check "ND-08 db: $2 is accepted" "$status"
}
vt_col() { sql "select data_type || '/' || is_nullable || '/' || coalesce(column_default, 'nodefault') from information_schema.columns where table_schema='$SCHEMA' and table_name='salida_capacity' and column_name='vehicle_capacity_ceiling'" 2>/dev/null || true; }

echo 'ND-08 db vehicle total capacity - base: every changeset that exists before the slice'
liquibase rollback-count 999 >/dev/null
db_labels='!vehicle-total-capacity'
liquibase update >/dev/null
vt_base="$(snapshot)"
vt_n0="$(sql "select count(*) from $CONTROL")"
check "the base holds every changeset except the one of the slice ($vt_n0)" "$([ "$vt_n0" -gt 0 ] && [ "$(sql "select count(*) from $CONTROL where labels ilike '%vehicle-total-capacity%'")" = 0 ]; echo $?)"
check 'on that base salida_capacity has no vehicle_capacity_ceiling column' "$([ -z "$(vt_col)" ]; echo $?)"
sql "set session_replication_role = replica; insert into $vt_t (salida_capacity_id, tenant_id, salida_id, service_id, effective_capacity, held_seats, hora_inicio, status) values (gen_random_uuid(), '$tenant', '$(aid 9511)', '$vt_svc', 20, 3, now() + interval '1 day', 'SCHEDULED')" >/dev/null

echo 'ND-08 db vehicle total capacity - probes written first: red before the changeset, green after'
db_labels='vehicle-total-capacity'
liquibase update >/dev/null
check 'the changeset of the slice adds one changeset (048) to the control table' "$([ "$(sql "select count(*) from $CONTROL")" = "$((vt_n0 + 1))" ]; echo $?)"

echo 'theDepartureKeepsTheTotalCapacityOfItsVehiclesAndItMayBeUnknown'
check 'the column is an integer, nullable and without a default' "$([ "$(vt_col)" = 'integer/YES/nodefault' ]; echo $?)"
check 'a row born before the column has no total (no backfill)' "$([ "$(sql "select count(*) from $vt_t where salida_id = '$(aid 9511)' and vehicle_capacity_ceiling is null and held_seats = 3 and effective_capacity = 20")" = 1 ]; echo $?)"
vt_accepted "$(vt_row "$(aid 9512)")" 'a departure row with no total'
vt_accepted "$(vt_row "$(aid 9513)" x 25)" 'a departure row with a total of 25'
vt_accepted "$(vt_row "$(aid 9514)" x 0)" 'a departure row with a total of zero (mandatory transport, no vehicle yet)'
vt_refusal "$(vt_row "$(aid 9515)" x -1)" "$vt_key" 'a negative total'
check 'the held seats guard stays: held above effective capacity is still refused' "$([ "$(engine "set session_replication_role = replica; insert into $vt_t (salida_capacity_id, tenant_id, salida_id, service_id, effective_capacity, held_seats, hora_inicio, status, vehicle_capacity_ceiling) values (gen_random_uuid(), '$tenant', '$(aid 9516)', '$vt_svc', 5, 6, now() + interval '1 day', 'SCHEDULED', 30)" postgres 2>&1 | grep -c chk_salida_capacity_held_within_effective)" -ge 1 ]; echo $?)"

echo 'onlyTheColumnChangesSecondRunAppliesZeroAndRevertLeavesNoTrace'
check 'nothing new appears in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasecha%'")" = 0 ]; echo $?)"
vt_second="$(liquibase update 2>&1)"; printf '%s\n' "$vt_second"
check 'a second update applies zero changesets' "$(printf '%s\n' "$vt_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
vt_n="$(sql "select count(*) from $CONTROL where labels ilike '%vehicle-total-capacity%'" 2>/dev/null || echo 0)"
sql "delete from $vt_t where salida_id in ('$(aid 9511)','$(aid 9513)','$(aid 9514)')" >/dev/null 2>&1 || true
liquibase rollback-count "$vt_n"
vt_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$vt_base" "$vt_reverted"
check 'the revert restores columns, constraints, indexes and privileges exactly and leaves the base changesets' "$([ -n "$vt_base" ] && [ "$vt_reverted" = "$vt_base" ] && [ "$(sql "select count(*) from $CONTROL")" = "$vt_n0" ]; echo $?)"
db_labels='vehicle-total-capacity'
liquibase update >/dev/null
check 'the changeset of the slice reapplies the one changeset of the slice' "$([ "$(sql "select count(*) from $CONTROL")" = "$((vt_n0 + 1))" ]; echo $?)"
