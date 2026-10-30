#!/usr/bin/env bash
# The four steps of Annex A against an empty PostgreSQL, in a throwaway container (norm 5.2.8):
#   1. update               builds everything
#   2. update, again        applies nothing
#   3. rollback-count 999   leaves the database empty
#   4. update               rebuilds
# CI and a developer run this same file. Docker is the only requirement.
set -euo pipefail
cd "$(dirname "$0")/.."

# Git Bash may resolve Docker Desktop's shell wrapper before docker.exe; invoke the CLI directly.
if command -v docker.exe >/dev/null 2>&1; then
  docker() { command docker.exe "$@"; }
fi

POSTGRES_IMAGE="postgres:18"
SCHEMA="commercial_reservation"
CONTROL="databasechangelog_commercial_reservation"
LOCK="databasechangeloglock_commercial_reservation"
db_labels='!HU-COM-003 and !HU-COM-004 and !HU-COM-005 and !HU-COM-006 and !HU-WRK-007 and !HU-COM-007 and !HU-COM-008 and !HU-COM-009' # Keep all 181 existing checks on their original 23-changeset schema.

suffix="$$"
runner_image="cr-db-runner:ci-$suffix"
network="cr-db-ci-$suffix"
container="cr-db-ci-pg-$suffix"
# A throwaway credential for a throwaway container: generated here and never written anywhere. It
# reaches the containers through the environment, so it never shows in a command line.
throwaway="$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
export POSTGRES_PASSWORD="$throwaway" PGPASSWORD="$throwaway" LIQUIBASE_COMMAND_PASSWORD="$throwaway"
host_dir="$(pwd -W 2>/dev/null || pwd)"

cleanup() { docker rm -f "$container" >/dev/null 2>&1 || true; docker network rm "$network" >/dev/null 2>&1 || true; docker rmi "$runner_image" >/dev/null 2>&1 || true; }
trap cleanup EXIT

fail=0
check() { # description, condition result (0 = holds)
  if [ "$2" -eq 0 ]; then echo "  ok    $1"; else echo "  FAIL  $1"; fail=1; fi
}
sql() { docker exec -e PGPASSWORD "$container" psql -U postgres -d postgres -tAc "$1"; }
liquibase() {
  local args=("$@")
  if [ -n "$db_labels" ] && [ "${1:-}" = update ] && [[ "$*" != *--label-filter* ]]; then args+=("--label-filter=$db_labels"); fi
  # no volume: the migrations are inside the image, exactly as the compose file runs it
  docker run --rm --network "$network" -e LIQUIBASE_COMMAND_PASSWORD "$runner_image" \
    --url="jdbc:postgresql://$container:5432/postgres" --username=postgres \
    --changelog-file=changelog/changelog-master.yaml \
    --database-changelog-table-name="$CONTROL" \
    --database-changelog-lock-table-name="$LOCK" "${args[@]}"
}

echo "building the runner image (deploy/Dockerfile)"
docker build -q -t "$runner_image" -f deploy/Dockerfile . >/dev/null
docker network create "$network" >/dev/null
docker run -d --name "$container" --network "$network" -e POSTGRES_PASSWORD "$POSTGRES_IMAGE" >/dev/null

echo "waiting for PostgreSQL"
for _ in $(seq 1 60); do
  docker exec "$container" pg_isready -U postgres -q 2>/dev/null && sql "select 1" >/dev/null 2>&1 && break
  sleep 1
done
sql "select 1" >/dev/null || { echo "PostgreSQL did not start"; exit 1; }

# plan.md D-10: the extension belongs to the instance, so the throwaway database needs it created here
sql "create extension if not exists pgcrypto" >/dev/null
# plan.md D-10, Annex J.7: the application user belongs to the infrastructure, which creates it from
# secrets. This is the only other thing CI does in its place. NOLOGIN is enough: the tests become it
# with SET ROLE, so no password exists anywhere.
sql "create role commercial_reservation_app nologin" >/dev/null

# The literal answer of the engine to a statement run as a role, errors included, so that a refusal
# is recorded as the engine said it and not as a summary of it.
as_role() { # role, statement
  docker exec -e PGPASSWORD "$container" psql -U postgres -d postgres -c "set role $1" -c "$2" 2>&1 || true
}

echo "step 1 - update builds everything"
liquibase update >/dev/null
check "HU-COM-002 T-05: an empty database applies exactly 23 changesets" "$([ "$(sql "select count(*) from $CONTROL")" = 23 ]; echo $?)"
echo "HU-COM-002 T-06 - liquibase validate (literal runner answer)"
liquibase validate
check "the schema $SCHEMA exists" "$([ "$(sql "select count(*) from pg_namespace where nspname='$SCHEMA'")" = 1 ]; echo $?)"
# T-03, AC-D1.1: nothing of this domain lives in public (Annex A rule 9, Annex J.4)
in_public="$(sql "select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasechangelog%'")"
check "no object of the domain lives in public" "$([ "$in_public" = 0 ]; echo $?)"
# T-04, AC-D1.11: the control table is this domain's own, and the default one never appears (Annex J.6)
own="$(sql "select count(*) from information_schema.tables where table_name = '$CONTROL'")"
default_table="$(sql "select count(*) from information_schema.tables where table_name = 'databasechangelog'")"
check "the control table $CONTROL exists" "$([ "$own" = 1 ]; echo $?)"
check "the default control table databasechangelog does not exist" "$([ "$default_table" = 0 ]; echo $?)"

# HU-COM-002 T-01: creates nothing. It records the four preconditions that the -db of HU-COM-001 leaves,
# and the first one that fails ends the run there: the answer is to finish HU-COM-001, never to create
# the missing piece here (two control tables would be two sources of truth).
echo "HU-COM-002 T-01 - preconditions left by HU-COM-001 (nothing is created)"
precondition() { # description, condition result (0 = holds)
  if [ "$2" -eq 0 ]; then echo "  ok    precondition: $1"
  else echo "  FAIL  precondition: $1"; echo "        T-01 ends here: the -db of HU-COM-001 is not applied. Finish it first; this slice creates none of these."; exit 1; fi
}
precondition "the schema $SCHEMA exists" "$([ "$(sql "select count(*) from pg_namespace where nspname = '$SCHEMA'")" = 1 ]; echo $?)"
precondition "the control table $CONTROL exists and holds changesets" "$([ "$(sql "select count(*) from $CONTROL" 2>/dev/null || echo 0)" -gt 0 ]; echo $?)"
precondition "commercial_reservation_app exists and holds no DELETE outside the two technical tables" "$([ "$(sql "select count(*) from pg_roles where rolname = 'commercial_reservation_app'")" = 1 ] && [ "$(sql "select count(*) from information_schema.tables t where t.table_schema = '$SCHEMA' and t.table_name not in ('idempotency_key', 'outbox_event') and has_table_privilege('commercial_reservation_app', format('%I.%I', t.table_schema, t.table_name), 'DELETE')")" = 0 ]; echo $?)"
precondition "outbox_event and idempotency_key are present" "$([ "$(sql "select count(*) from information_schema.tables where table_schema = '$SCHEMA' and table_name in ('outbox_event', 'idempotency_key')")" = 2 ]; echo $?)"

# T-06, AC-D1.6: roles without login, DELETE withheld by the engine (plan.md D-04, D-08)
echo "T-06 - roles, grants and DELETE withheld"
reader="commercial_reservation_reader"; writer="commercial_reservation_writer"; app="commercial_reservation_app"
roles="$(sql "select count(*) from pg_roles where rolname in ('$reader','$writer')")"
check "the reader and the writer roles exist" "$([ "$roles" = 2 ]; echo $?)"
loginable="$(sql "select count(*) from pg_authid where rolname in ('$reader','$writer') and (rolcanlogin or rolpassword is not null)")"
check "neither role can log in nor holds a password (Annex A rule 10)" "$([ "$roles" = 2 ] && [ "$loginable" = 0 ]; echo $?)"
check "the application user inherits the writer" "$([ "$(sql "select pg_has_role('$app','$writer','member')")" = t ]; echo $?)"
# A table born after the grants is the case default privileges exist for: the catalog table of T-08.
# It is created and judged inside one transaction that is rolled back, so nothing stays behind.
probe="$(printf '%s\n' "begin;" \
  "create table commercial_reservation.zz_probe (id int);" \
  "set local role $app;" \
  "insert into commercial_reservation.zz_probe values (1);" \
  "update commercial_reservation.zz_probe set id = 2;" \
  "delete from commercial_reservation.zz_probe;" \
  "rollback;" | docker exec -i -e PGPASSWORD "$container" psql -U postgres -d postgres 2>&1 || true)"
check "a table created later accepts INSERT as the application user" "$(echo "$probe" | grep -q '^INSERT 0 1'; echo $?)"
check "a table created later accepts UPDATE as the application user" "$(echo "$probe" | grep -q '^UPDATE 1'; echo $?)"
check "a table created later refuses DELETE by permission" "$(echo "$probe" | grep -q 'permission denied for table zz_probe'; echo $?)"
echo "      $(echo "$probe" | grep 'permission denied' | head -1)"
over_granted="$(sql "select count(*) from information_schema.tables t where t.table_schema = '$SCHEMA' and t.table_name not in ('idempotency_key', 'outbox_event') and (has_table_privilege('$writer', format('%I.%I', t.table_schema, t.table_name), 'DELETE') or has_table_privilege('$app', format('%I.%I', t.table_schema, t.table_name), 'DELETE'))")"
check "no table but the two technical ones lets the writer or the application user DELETE" "$([ "$roles" = 2 ] && [ "$over_granted" = 0 ]; echo $?)"

# T-08, AC-D1.2 to AC-D1.6 and AC-D1.8: the catalog table (plan.md DD-8, DD-16)
echo "T-08 - catalog_service"
tenant="00000000-0000-0000-0000-000000000001"; actor="00000000-0000-0000-0000-0000000000a1"
refused() { # statement, text the engine must answer with: the refusal has to come from the named rule
  local answer
  # captured first: grep -q closing the pipe early would make psql fail under pipefail
  answer="$(docker exec -e PGPASSWORD "$container" psql -U postgres -d postgres -c "$1" 2>&1 || true)"
  echo "$answer" | grep -q "$2"; echo $?
}
# Every value is spelled out: the table has no DEFAULT on purpose (plan.md DD-8, DD-16), so a row that
# leaves one out is the engine's to refuse. Arguments: type, name expression, status, rate, cost,
# capacity, transport required, high risk, and an optional id expression.
catalog_insert() {
  echo "insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values (${9:-gen_random_uuid()}, '$tenant', '$1', $2, '$3', $4, $5, $6, $7, $8, now(), now())"
}
catalog_row() { catalog_insert TOUR "'Coffee farm route'" ACTIVE 150000 90000 12 false false "${1:-}"; }
expected_columns="service_id uuid NO,tenant_id uuid NO,service_type text NO,commercial_name text NO,catalog_status text NO,base_rate_cents bigint NO,base_operational_cost_cents bigint NO,configured_capacity integer YES,transport_required boolean NO,high_risk boolean NO,created_at timestamp with time zone NO,updated_at timestamp with time zone NO"
actual_columns="$(sql "select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position) from information_schema.columns where table_schema = '$SCHEMA' and table_name = 'catalog_service'" 2>/dev/null || true)"
check "catalogTableHoldsTheStoryAttributes: the 12 columns exist with their type and nullability" "$([ "$actual_columns" = "$expected_columns" ]; echo $?)"
high_risk="$(sql "select data_type || ' ' || is_nullable from information_schema.columns where table_schema = '$SCHEMA' and table_name = 'catalog_service' and column_name = 'high_risk'" 2>/dev/null || true)"
check "catalogTableHoldsTheHighRiskMark: high_risk is boolean NOT NULL" "$([ "$high_risk" = "boolean NO" ]; echo $?)"
# a row count of 0 would also be the answer of a table that does not exist, so the column count is asserted too
defaults_judged="$(sql "select count(*) from information_schema.columns where table_schema = '$SCHEMA' and table_name = 'catalog_service' and column_name in ('service_id','catalog_status','high_risk')" 2>/dev/null || true)"
with_default="$(sql "select count(*) from information_schema.columns where table_schema = '$SCHEMA' and table_name = 'catalog_service' and column_name in ('service_id','catalog_status','high_risk') and column_default is not null" 2>/dev/null || true)"
check "service_id, catalog_status and high_risk have no DEFAULT (the service decides, plan.md DD-8, DD-16)" "$([ "$defaults_judged" = 3 ] && [ "$with_default" = 0 ]; echo $?)"
check "a complete TOUR row is accepted" "$(sql "$(catalog_row)" >/dev/null 2>&1; echo $?)"
check "a complete TRANSPORTATION row without capacity is accepted" "$(sql "$(catalog_insert TRANSPORTATION "'Airport transfer'" ACTIVE 80000 50000 null false true)" >/dev/null 2>&1; echo $?)"
without_rate="insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values (gen_random_uuid(), '$tenant', 'TOUR', 'No rate', 'ACTIVE', 1000, 5, false, false, now(), now())"
without_cost="insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values (gen_random_uuid(), '$tenant', 'TOUR', 'No cost', 'ACTIVE', 1000, 5, false, false, now(), now())"
check "insertWithoutValueOrCostIsRefusedByTheEngine: no base_rate_cents is refused by NOT NULL" "$(refused "$without_rate" 'null value in column "base_rate_cents".*not-null constraint')"
check "insertWithoutValueOrCostIsRefusedByTheEngine: no base_operational_cost_cents is refused by NOT NULL" "$(refused "$without_cost" 'null value in column "base_operational_cost_cents".*not-null constraint')"
check "closedValueSetsRefuseUnknownValues: an unknown service_type is refused" "$(refused "$(catalog_insert LODGING "'Hotel'" ACTIVE 1000 500 5 false false)" 'chk_catalog_service_service_type')"
check "closedValueSetsRefuseUnknownValues: an unknown catalog_status is refused" "$(refused "$(catalog_insert TOUR "'Route'" DELETED 1000 500 5 false false)" 'chk_catalog_service_catalog_status')"
check "a TOUR without configured_capacity is refused" "$(refused "$(catalog_insert TOUR "'Route'" ACTIVE 1000 500 null false false)" 'chk_catalog_service_tour_requires_capacity')"
check "a configured_capacity of zero is refused" "$(refused "$(catalog_insert TOUR "'Route'" ACTIVE 1000 500 0 false false)" 'chk_catalog_service_configured_capacity')"
check "a negative configured_capacity is refused" "$(refused "$(catalog_insert TOUR "'Route'" ACTIVE 1000 500 -3 false false)" 'chk_catalog_service_configured_capacity')"
check "a TRANSPORTATION service requiring transport is refused" "$(refused "$(catalog_insert TRANSPORTATION "'Transfer'" ACTIVE 1000 500 null true false)" 'chk_catalog_service_transportation_not_requiring_transport')"
check "a negative base_rate_cents is refused" "$(refused "$(catalog_insert TOUR "'Route'" ACTIVE -1 500 5 false false)" 'chk_catalog_service_base_rate_cents')"
check "a negative base_operational_cost_cents is refused" "$(refused "$(catalog_insert TOUR "'Route'" ACTIVE 1000 -1 5 false false)" 'chk_catalog_service_base_operational_cost_cents')"
check "an empty commercial_name is refused" "$(refused "$(catalog_insert TOUR "''" ACTIVE 1000 500 5 false false)" 'chk_catalog_service_commercial_name_length')"
check "a commercial_name of 256 characters is refused" "$(refused "$(catalog_insert TOUR "repeat('n', 256)" ACTIVE 1000 500 5 false false)" 'chk_catalog_service_commercial_name_length')"
check "a commercial_name of 255 characters is accepted" "$(sql "$(catalog_insert TOUR "repeat('n', 255)" ACTIVE 1000 500 5 false false)" >/dev/null 2>&1; echo $?)"

# AC-D1.6: the application user writes and updates the catalog, and its DELETE is refused by permission
app_catalog_insert="$(as_role "$app" "$(catalog_row)")"
app_catalog_update="$(as_role "$app" "update $SCHEMA.catalog_service set high_risk = true where commercial_name = 'Coffee farm route'")"
app_catalog_delete="$(as_role "$app" "delete from $SCHEMA.catalog_service")"
check "the application user can INSERT into the catalog" "$(echo "$app_catalog_insert" | grep -q '^INSERT 0 1'; echo $?)"
check "the application user can UPDATE the catalog" "$(echo "$app_catalog_update" | grep -q '^UPDATE [1-9]'; echo $?)"
check "the application user's DELETE on the catalog is refused by permission" "$(echo "$app_catalog_delete" | grep -q 'permission denied for table catalog_service'; echo $?)"
echo "      $(echo "$app_catalog_delete" | grep -i 'permission denied' | head -1)"

# AC-D1.8: the status change and its event are one transaction, so neither exists without the other
svc="00000000-0000-0000-0000-0000000000b1"
sql "$(catalog_row "'$svc'")" >/dev/null 2>&1 || true
tx() { # commit or rollback
  printf '%s\n' "begin;" \
    "update $SCHEMA.catalog_service set catalog_status = 'INACTIVE', updated_at = now() where service_id = '$svc';" \
    "insert into $SCHEMA.outbox_event (tenant_id, event_type, service_id, previous_catalog_status, new_catalog_status, actor_id, occurred_at) values ('$tenant', 'CatalogServiceInactivated', '$svc', 'ACTIVE', 'INACTIVE', '$actor', now());" \
    "$1;" | docker exec -i -e PGPASSWORD "$container" psql -U postgres -d postgres -v ON_ERROR_STOP=1 >/dev/null 2>&1
}
state() { sql "select catalog_status || '/' || (select count(*) from $SCHEMA.outbox_event where service_id = '$svc') from $SCHEMA.catalog_service where service_id = '$svc'" 2>/dev/null || true; }
tx rollback || true
check "activeChangeWritesItsOutboxRowInTheSameTransaction: a rolled back change leaves neither the status nor the event" "$([ "$(state)" = "ACTIVE/0" ]; echo $?)"
tx commit || true
check "activeChangeWritesItsOutboxRowInTheSameTransaction: a committed change leaves both" "$([ "$(state)" = "INACTIVE/1" ]; echo $?)"
check "an outbox event for a service that does not exist is refused by fk_outbox_event_service" "$(refused "insert into $SCHEMA.outbox_event (tenant_id, event_type, service_id, previous_catalog_status, new_catalog_status, actor_id, occurred_at) values ('$tenant', 'CatalogServiceInactivated', gen_random_uuid(), 'ACTIVE', 'INACTIVE', '$actor', now())" 'fk_outbox_event_service')"
# the T-07 tests below count outbox rows, so this section leaves none behind
sql "delete from $SCHEMA.outbox_event" >/dev/null 2>&1 || true

# T-10, AC-5: the minimal capacity entity of a departure (plan.md DD-19). Held seats are set by the
# test itself, because holding them belongs to the reservations story, HU-COM-007.
echo "T-10 - salida_capacity"
cap_table="$SCHEMA.salida_capacity"
cap_insert() { # tenant, departure, capacity, held seats, and the service (default: the catalog service of the outbox section)
  echo "insert into $cap_table (salida_capacity_id, tenant_id, salida_id, service_id, effective_capacity, held_seats) values (gen_random_uuid(), '$1', '$2', '${5:-$svc}', $3, $4)"
}
salida="00000000-0000-0000-0000-0000000000c1"
other_tenant_cap="00000000-0000-0000-0000-000000000002"
expected_cap_columns="salida_capacity_id uuid NO,tenant_id uuid NO,salida_id uuid NO,effective_capacity integer NO,held_seats integer NO,service_id uuid NO"
actual_cap_columns="$(sql "select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position) from information_schema.columns where table_schema = '$SCHEMA' and table_name = 'salida_capacity'" 2>/dev/null || true)"
check "capacityEntityHoldsCapacityAndNonNegativeHeldSeats: exactly the 6 columns exist with their type and nullability" "$([ "$actual_cap_columns" = "$expected_cap_columns" ]; echo $?)"
check "a complete capacity row is accepted, with the held seats set by the fixture" "$(sql "$(cap_insert "$tenant" "$salida" 20 3)" >/dev/null 2>&1; echo $?)"
check "capacityEntityHoldsCapacityAndNonNegativeHeldSeats: zero held seats are accepted" "$(sql "$(cap_insert "$tenant" 00000000-0000-0000-0000-0000000000c2 20 0)" >/dev/null 2>&1; echo $?)"
check "capacityEntityHoldsCapacityAndNonNegativeHeldSeats: a negative held seat count is refused" "$(refused "$(cap_insert "$tenant" 00000000-0000-0000-0000-0000000000c3 20 -1)" 'chk_salida_capacity_held_seats')"
check "a second row for the same tenant and departure is refused" "$(refused "$(cap_insert "$tenant" "$salida" 30 0)" 'uq_salida_capacity_tenant_id_salida_id')"
check "the same departure under another tenant is accepted" "$(sql "$(cap_insert "$other_tenant_cap" "$salida" 20 0)" >/dev/null 2>&1; echo $?)"
cap_defaults="$(sql "select count(*) from information_schema.columns where table_schema = '$SCHEMA' and table_name = 'salida_capacity' and column_name in ('salida_id','effective_capacity') and column_default is not null" 2>/dev/null || true)"
cap_judged="$(sql "select count(*) from information_schema.columns where table_schema = '$SCHEMA' and table_name = 'salida_capacity' and column_name in ('salida_id','effective_capacity')" 2>/dev/null || true)"
check "salida_id and effective_capacity have no DEFAULT" "$([ "$cap_judged" = 2 ] && [ "$cap_defaults" = 0 ]; echo $?)"
# the departure belongs to operations-cost, so it is a logical reference only (Annex J.3.4); the one
# foreign key of the table points inside this schema, at the catalog service (spec.md DD-6)
cap_foreign_keys="$(sql "select string_agg(c.conname || '->' || n.nspname || '.' || r.relname || '(' || c.confdeltype::text || ')', ',' order by c.conname) from pg_constraint c join pg_class r on r.oid = c.confrelid join pg_namespace n on n.oid = r.relnamespace where c.conrelid = '$cap_table'::regclass and c.contype = 'f'" 2>/dev/null || true)"
check "the only foreign key of salida_capacity is fk_salida_capacity_service, to catalog_service, ON DELETE RESTRICT; none to another domain" "$([ "$cap_foreign_keys" = "fk_salida_capacity_service->$SCHEMA.catalog_service(r)" ]; echo $?)"
cap_salida_fk="$(sql "select count(*) from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any(c.conkey) where c.conrelid = '$cap_table'::regclass and c.contype = 'f' and a.attname = 'salida_id'" 2>/dev/null || true)"
check "salida_id still has no foreign key" "$([ "$cap_salida_fk" = 0 ]; echo $?)"
cap_service_default="$(sql "select count(*) from information_schema.columns where table_schema = '$SCHEMA' and table_name = 'salida_capacity' and column_name = 'service_id' and data_type = 'uuid' and is_nullable = 'NO' and column_default is null" 2>/dev/null || true)"
check "service_id is uuid NOT NULL with no DEFAULT: the service decides it" "$([ "$cap_service_default" = 1 ]; echo $?)"
cap_service_index="$(sql "select count(*) from pg_indexes where schemaname = '$SCHEMA' and tablename = 'salida_capacity' and indexname = 'idx_salida_capacity_tenant_id_service_id' and indexdef like '%(tenant_id, service_id)%'" 2>/dev/null || true)"
check "the capacity check has its index: idx_salida_capacity_tenant_id_service_id on (tenant_id, service_id)" "$([ "$cap_service_index" = 1 ]; echo $?)"
cap_without_service="insert into $cap_table (salida_capacity_id, tenant_id, salida_id, effective_capacity, held_seats) values (gen_random_uuid(), '$tenant', '00000000-0000-0000-0000-0000000000c5', 10, 0)"
check "a capacity row without service_id is refused by NOT NULL" "$(refused "$cap_without_service" 'null value in column "service_id".*not-null constraint')"
check "a capacity row for a service that does not exist is refused by fk_salida_capacity_service" "$(refused "$(cap_insert "$tenant" 00000000-0000-0000-0000-0000000000c6 10 0 00000000-0000-0000-0000-00000000dead)" 'fk_salida_capacity_service')"
check "a catalog service that has capacity rows cannot be deleted (RESTRICT)" "$(refused "delete from $SCHEMA.catalog_service where service_id = '$svc'" 'fk_salida_capacity_service')"
# the lower bound of the capacity is only PROPOSED in 06-data, which orders not to implement it
cap_checks="$(sql "select string_agg(conname, ',' order by conname) from pg_constraint where conrelid = '$cap_table'::regclass and contype = 'c'" 2>/dev/null || true)"
check "effective_capacity has no lower bound: the only CHECK is the one on held_seats" "$([ "$cap_checks" = "chk_salida_capacity_held_seats" ]; echo $?)"
app_cap_insert="$(as_role "$app" "$(cap_insert "$tenant" 00000000-0000-0000-0000-0000000000c4 10 0)")"
app_cap_update="$(as_role "$app" "update $cap_table set held_seats = held_seats + 1 where salida_id = '$salida' and tenant_id = '$tenant'")"
app_cap_delete="$(as_role "$app" "delete from $cap_table")"
check "the application user can INSERT into salida_capacity" "$(echo "$app_cap_insert" | grep -q '^INSERT 0 1'; echo $?)"
check "the application user can UPDATE salida_capacity, raising the held seats" "$(echo "$app_cap_update" | grep -q '^UPDATE 1'; echo $?)"
check "the application user's DELETE on salida_capacity is refused by permission" "$(echo "$app_cap_delete" | grep -q 'permission denied for table salida_capacity'; echo $?)"
echo "      $(echo "$app_cap_delete" | grep -i 'permission denied' | head -1)"

# T-07, AC-D1.7 and AC-D1.8: the idempotency key and the outbox (plan.md D-06, D-07)
echo "T-07 - idempotency key and outbox"
insert_key() { echo "insert into $SCHEMA.idempotency_key (key, tenant_id, resource_type, resource_id) values ($1, '${2:-$tenant}', 'catalog_service', gen_random_uuid())"; }
check "a 7 character key is refused by the engine" "$(refused "$(insert_key "repeat('k', 7)")" 'chk_idempotency_key_key_length')"
check "a 129 character key is refused by the engine" "$(refused "$(insert_key "repeat('k', 129)")" 'chk_idempotency_key_key_length')"
check "an 8 and a 128 character key are accepted" "$(sql "$(insert_key "repeat('a', 8)"); $(insert_key "repeat('b', 128)")" >/dev/null 2>&1; echo $?)"
check "the same key inserted again is refused as a duplicate" "$(refused "$(insert_key "repeat('a', 8)")" 'pk_idempotency_key')"
sql "$(insert_key "repeat('a', 8)") on conflict do nothing" >/dev/null 2>&1 || true
check "the same key in the same tenant leaves a single row" "$([ "$(sql "select count(*) from $SCHEMA.idempotency_key where key = repeat('a', 8)")" = 1 ]; echo $?)"
# the key is scoped by tenant (modeling-conventions.md): one tenant must never receive the resource of another
other_tenant="00000000-0000-0000-0000-000000000002"
sql "$(insert_key "repeat('a', 8)" "$other_tenant")" >/dev/null 2>&1 || true
check "the same key in two tenants leaves two rows" "$([ "$(sql "select count(*) from $SCHEMA.idempotency_key where key = repeat('a', 8)")" = 2 ]; echo $?)"
check "the key is the primary key of tenant and key together" "$([ "$(sql "select string_agg(a.attname, ',' order by k.ord) from pg_constraint c cross join unnest(c.conkey) with ordinality k(attnum, ord) join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum where c.conname = 'pk_idempotency_key'")" = "tenant_id,key" ]; echo $?)"

columns="$(sql "select count(*) from information_schema.columns where table_schema = '$SCHEMA' and table_name = 'outbox_event' and column_name in ('outbox_event_id','tenant_id','event_type','service_id','previous_catalog_status','new_catalog_status','actor_id','occurred_at','published_at')")"
check "the outbox carries the fields of the two catalog events, its type and its published mark" "$([ "$columns" = 9 ]; echo $?)"
outbox_insert() { echo "insert into $SCHEMA.outbox_event (tenant_id, event_type, service_id, previous_catalog_status, new_catalog_status, actor_id, occurred_at) values ('$tenant', '$1', '$svc', '$2', '$3', '$actor', now())"; }
check "an inactivation event is accepted and starts unpublished" "$(sql "$(outbox_insert CatalogServiceInactivated ACTIVE INACTIVE)" >/dev/null 2>&1 && [ "$(sql "select count(*) from $SCHEMA.outbox_event where published_at is null")" = 1 ]; echo $?)"
check "an unknown event type is refused" "$(refused "$(outbox_insert CatalogServiceRenamed ACTIVE INACTIVE)" 'chk_outbox_event_event_type')"
check "an event that changes nothing is refused" "$(refused "$(outbox_insert CatalogServiceInactivated ACTIVE ACTIVE)" 'chk_outbox_event_condition_changed')"
check "an inactivation that ends active is refused" "$(refused "$(outbox_insert CatalogServiceInactivated INACTIVE ACTIVE)" 'chk_outbox_event_type_matches_new_condition')"
partial="$(sql "select count(*) from pg_indexes where schemaname = '$SCHEMA' and indexname = 'idx_outbox_event_unpublished' and indexdef like '%WHERE (published_at IS NULL)%'")"
check "the relay's unpublished events have a partial index" "$([ "$partial" = 1 ]; echo $?)"

# HU-COM-002 T-02: associated_establishment (spec.md AC-D2.2 to AC-D2.5). Placed before the checks over every
# table of the schema, so that those judge the new tables too.
echo "HU-COM-002 T-02 - associated_establishment"
ae_table="$SCHEMA.associated_establishment"; img_table="$SCHEMA.associated_establishment_image"
aid() { printf '00000000-0000-0000-0000-%012d' "$1"; }
ae_insert() { # type, name expression, information expression, status, and an optional id expression
  echo "insert into $ae_table (association_id, tenant_id, establishment_type, commercial_name, commercial_information, association_status, created_at, updated_at) values (${5:-gen_random_uuid()}, '$tenant', '$1', $2, $3, '$4', now(), now())"
}
ae_row() { ae_insert HOTEL "'Hotel Andino'" "'Breakfast included, open all year'" ACTIVE "${1:-}"; }
cols_of() { sql "select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position) from information_schema.columns where table_schema = '$SCHEMA' and table_name = '$1'" 2>/dev/null || true; }
privileges_of() { sql "select string_agg(p, ',' order by p) from unnest(array['SELECT','INSERT','UPDATE','DELETE']) p where has_table_privilege('$app', '$1', p)" 2>/dev/null || true; }
expected_ae_columns="association_id uuid NO,tenant_id uuid NO,establishment_type text NO,commercial_name text NO,commercial_information text NO,association_status text NO,created_at timestamp with time zone NO,updated_at timestamp with time zone NO"
check "associationTableHoldsTheStoryAttributes: exactly the 8 columns exist with their type and nullability" "$([ "$(cols_of associated_establishment)" = "$expected_ae_columns" ]; echo $?)"
# RN-02 is held by absence (AC-02.7): no column of a room, a dish, a menu, a seat, a rate or availability, in either table
judged="$(sql "select count(*) from information_schema.columns where table_schema = '$SCHEMA' and table_name like 'associated_establishment%'" 2>/dev/null || true)"
forbidden_found="$(sql "select string_agg(table_name || '.' || column_name, ',') from information_schema.columns where table_schema = '$SCHEMA' and table_name like 'associated_establishment%' and column_name ~ '(room|dish|menu|seat|rate|availab)'" 2>/dev/null || true)"
check "none of the six forbidden columns (room, dish, menu, seat, rate, availability) exists in either table" "$([ "${judged:-0}" -gt 0 ] && [ -z "$forbidden_found" ]; echo $?)"
defaults_found="$(sql "select count(*) from information_schema.columns where table_schema = '$SCHEMA' and table_name like 'associated_establishment%' and column_default is not null" 2>/dev/null || true)"
check "no column of either table has a DEFAULT: the service decides every value" "$([ "${judged:-0}" -gt 0 ] && [ "$defaults_found" = 0 ]; echo $?)"
check "a complete HOTEL row is accepted as the application user" "$(as_role "$app" "$(ae_row)" | grep -q '^INSERT 0 1'; echo $?)"
check "a complete RESTAURANT row is accepted as the application user" "$(as_role "$app" "$(ae_insert RESTAURANT "'Cafe del Valle'" "'Local food, lunch only'" ACTIVE)" | grep -q '^INSERT 0 1'; echo $?)"
check "typeOutsideHotelAndRestaurantIsRefusedByTheEngine: a third type is refused" "$(refused "$(ae_insert LODGING "'Hostel'" "'Info'" ACTIVE)" 'chk_associated_establishment_establishment_type')"
check "a lowercase type is refused: the values are the contract's, in capitals" "$(refused "$(ae_insert hotel "'Hostel'" "'Info'" ACTIVE)" 'chk_associated_establishment_establishment_type')"
check "everyRowCarriesANonNullTenantId: a null tenant is refused" "$(refused "insert into $ae_table (association_id, tenant_id, establishment_type, commercial_name, commercial_information, association_status, created_at, updated_at) values (gen_random_uuid(), null, 'HOTEL', 'No tenant', 'Info', 'ACTIVE', now(), now())" 'null value in column "tenant_id".*not-null constraint')"
check "a status outside ACTIVE and INACTIVE is refused" "$(refused "$(ae_insert HOTEL "'Hostel'" "'Info'" DELETED)" 'chk_associated_establishment_association_status')"
check "a lowercase status is refused" "$(refused "$(ae_insert HOTEL "'Hostel'" "'Info'" active)" 'chk_associated_establishment_association_status')"
check "an INACTIVE row is accepted: the status has exactly two values" "$(sql "$(ae_insert HOTEL "'Closed hotel'" "'Info'" INACTIVE)" >/dev/null 2>&1; echo $?)"
check "a null commercial_information is refused by NOT NULL (PDR RF-018)" "$(refused "$(ae_insert HOTEL "'Hostel'" null ACTIVE)" 'null value in column "commercial_information".*not-null constraint')"
check "an empty commercial_name is refused" "$(refused "$(ae_insert HOTEL "''" "'Info'" ACTIVE)" 'chk_associated_establishment_commercial_name_length')"
check "a commercial_name of 256 characters is refused" "$(refused "$(ae_insert HOTEL "repeat('n', 256)" "'Info'" ACTIVE)" 'chk_associated_establishment_commercial_name_length')"
check "a commercial_name of 255 characters is accepted" "$(sql "$(ae_insert HOTEL "repeat('n', 255)" "'Info'" ACTIVE)" >/dev/null 2>&1; echo $?)"
check "the application user holds SELECT, INSERT and UPDATE on associated_establishment and no DELETE" "$([ "$(privileges_of "$ae_table")" = "INSERT,SELECT,UPDATE" ]; echo $?)"
ae_app_update="$(as_role "$app" "update $ae_table set association_status = 'INACTIVE', updated_at = now() where commercial_name = 'Hotel Andino'")"
ae_app_delete="$(as_role "$app" "delete from $ae_table")"
check "the application user can UPDATE an association" "$(echo "$ae_app_update" | grep -q '^UPDATE 1'; echo $?)"
check "applicationUserCannotDeleteAnAssociation: its DELETE is refused by permission" "$(echo "$ae_app_delete" | grep -Eq 'permission denied for table associated_establishment$'; echo $?)"
echo "      $(echo "$ae_app_delete" | grep -i 'permission denied' | head -1)"
ae_index="$(sql "select count(*) from pg_indexes where schemaname = '$SCHEMA' and tablename = 'associated_establishment' and indexname = 'idx_associated_establishment_tenant_status_created' and indexdef like '%(tenant_id, association_status, created_at DESC)%'" 2>/dev/null || true)"
check "the management listing has its index: idx_associated_establishment_tenant_status_created on (tenant_id, association_status, created_at DESC)" "$([ "$ae_index" = 1 ]; echo $?)"
check "associated_establishment has no foreign key: the image points at it, not the other way round" "$([ "$(sql "select count(*) from pg_constraint where conrelid = '$ae_table'::regclass and contype = 'f'" 2>/dev/null || echo x)" = 0 ]; echo $?)"

# HU-COM-002 T-03: the image in a table of its own (spec.md AC-D2.6, AC-D2.7; RN-08, RN-09)
echo "HU-COM-002 T-03 - associated_establishment_image"
img_insert() { # association id, content type, size_bytes, and an optional sha256 expression
  echo "insert into $img_table (image_id, tenant_id, association_id, content, content_type, size_bytes, sha256) values (gen_random_uuid(), '$tenant', '$1', decode('89504e470d0a1a0a', 'hex'), '$2', $3, ${4:-repeat('a', 64)})"
}
expected_img_columns="image_id uuid NO,tenant_id uuid NO,association_id uuid NO,content bytea NO,content_type text NO,size_bytes integer NO,sha256 character NO"
check "imageRowHoldsContentTypeSizeChecksumAndTenant: exactly the 7 columns exist with their type and nullability" "$([ "$(cols_of associated_establishment_image)" = "$expected_img_columns" ]; echo $?)"
for n in 101 102 103 104 105 106; do sql "$(ae_row "'$(aid $n)'")" >/dev/null 2>&1 || true; done
a1="$(aid 101)"
check "associationAndImageAreWrittenInOneTransaction: association and image commit together as the application user" "$(printf '%s\n' "begin;" "$(ae_row "'$(aid 107)'");" "$(img_insert "$(aid 107)" image/png 1024);" "commit;" | docker exec -i -e PGPASSWORD "$container" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c "set role $app" -f - >/dev/null 2>&1; echo $?)"
check "...and a rolled back transaction leaves neither of them" "$(printf '%s\n' "begin;" "$(ae_row "'$(aid 108)'");" "$(img_insert "$(aid 108)" image/png 1024);" "rollback;" | docker exec -i -e PGPASSWORD "$container" psql -U postgres -d postgres -v ON_ERROR_STOP=1 >/dev/null 2>&1; [ "$(sql "select (select count(*) from $ae_table where association_id = '$(aid 108)') + (select count(*) from $img_table where association_id = '$(aid 108)')" 2>/dev/null || echo x)" = 0 ]; echo $?)"
check "a complete PNG image row is accepted as the application user" "$(as_role "$app" "$(img_insert "$a1" image/png 1024)" | grep -q '^INSERT 0 1'; echo $?)"
check "a JPEG image is accepted" "$(sql "$(img_insert "$(aid 102)" image/jpeg 1024)" >/dev/null 2>&1; echo $?)"
check "a WebP image is accepted" "$(sql "$(img_insert "$(aid 103)" image/webp 1024)" >/dev/null 2>&1; echo $?)"
check "an image of exactly 819200 bytes (800 KB) is accepted" "$(sql "$(img_insert "$(aid 104)" image/png 819200)" >/dev/null 2>&1; echo $?)"
check "sizeAbove800KbOrTypeOutsidePngJpegWebpIsRefusedByTheEngine: an image of 819201 bytes is refused" "$(refused "$(img_insert "$(aid 105)" image/png 819201)" 'chk_associated_establishment_image_size_bytes')"
check "an image of zero bytes is refused" "$(refused "$(img_insert "$(aid 105)" image/png 0)" 'chk_associated_establishment_image_size_bytes')"
check "...image/svg+xml is refused" "$(refused "$(img_insert "$(aid 105)" image/svg+xml 1024)" 'chk_associated_establishment_image_content_type')"
check "...image/gif is refused" "$(refused "$(img_insert "$(aid 105)" image/gif 1024)" 'chk_associated_establishment_image_content_type')"
check "...application/pdf is refused" "$(refused "$(img_insert "$(aid 105)" application/pdf 1024)" 'chk_associated_establishment_image_content_type')"
check "a sha256 that is not 64 lowercase hexadecimal characters is refused" "$(refused "$(img_insert "$(aid 105)" image/png 1024 "repeat('A', 64)")" 'chk_associated_establishment_image_sha256')"
check "a second image for the same association is refused (one image per association)" "$(refused "$(img_insert "$a1" image/png 1024)" 'uq_associated_establishment_image_association_id')"
check "an image for an association that does not exist is refused by fk_associated_establishment_image_association" "$(refused "$(img_insert "$(aid 999)" image/png 1024)" 'fk_associated_establishment_image_association')"
check "an association that has an image cannot be deleted (RESTRICT)" "$(refused "delete from $ae_table where association_id = '$a1'" 'fk_associated_establishment_image_association')"
check "a null tenant on an image is refused" "$(refused "insert into $img_table (image_id, tenant_id, association_id, content, content_type, size_bytes, sha256) values (gen_random_uuid(), null, '$(aid 105)', decode('89', 'hex'), 'image/png', 1, repeat('a', 64))" 'null value in column "tenant_id".*not-null constraint')"
img_foreign_keys="$(sql "select string_agg(c.conname || '->' || n.nspname || '.' || r.relname || '(' || c.confdeltype::text || ')', ',' order by c.conname) from pg_constraint c join pg_class r on r.oid = c.confrelid join pg_namespace n on n.oid = r.relnamespace where c.conrelid = '$img_table'::regclass and c.contype = 'f'" 2>/dev/null || true)"
check "the only foreign key of the image table is fk_associated_establishment_image_association, to associated_establishment, ON DELETE RESTRICT" "$([ "$img_foreign_keys" = "fk_associated_establishment_image_association->$SCHEMA.associated_establishment(r)" ]; echo $?)"
img_index="$(sql "select count(*) from pg_indexes where schemaname = '$SCHEMA' and tablename = 'associated_establishment_image' and indexname = 'idx_associated_establishment_image_tenant_id_association_id' and indexdef like '%(tenant_id, association_id)%'" 2>/dev/null || true)"
check "the foreign key has its index: idx_associated_establishment_image_tenant_id_association_id on (tenant_id, association_id)" "$([ "$img_index" = 1 ]; echo $?)"
check "the application user holds SELECT, INSERT and UPDATE on the image table and no DELETE" "$([ "$(privileges_of "$img_table")" = "INSERT,SELECT,UPDATE" ]; echo $?)"
img_app_delete="$(as_role "$app" "delete from $img_table")"
check "the application user's DELETE on the image table is refused by permission" "$(echo "$img_app_delete" | grep -q 'permission denied for table associated_establishment_image'; echo $?)"
echo "      $(echo "$img_app_delete" | grep -i 'permission denied' | head -1)"

# HU-COM-002 T-04 / AC-D2.8: use the existing outbox, never a parallel table or a
# catalog-service fixture masquerading as an association. These checks were observed
# red before the new outbox generalization changesets made this story possible.
# Every engine answer and statement is printed for T-06; a rejected transaction
# must fail even if the subsequent absence check happens to hold.
engine() { # SQL, role (application by default). One session, fail on SQL errors.
  local statement="$1" role="${2:-$app}" result=0
  printf '\nSQL (SET ROLE %s):\n%s\n' "$role" "$statement"
  printf '%s\n' "set role $role;" "$statement" | docker exec -i -e PGPASSWORD "$container" \
    psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f - || result=$?
  printf 'psql exit status: %s\n' "$result"
  return "$result"
}
association_event() { # event id, association id, event type, previous SQL value, new status
  echo "insert into $SCHEMA.outbox_event (outbox_event_id, tenant_id, event_type, association_id, previous_catalog_status, new_catalog_status, actor_id, occurred_at) values ('$1', '$tenant', '$3', '$2', $4, '$5', '$actor', now())"
}
association_state() { # association id, event id: exact identity/tenant plus total event count
  sql "select coalesce((select association_status from $ae_table where association_id = '$1' and tenant_id = '$tenant'), 'ABSENT') || '/' || (select count(*) from $SCHEMA.outbox_event where outbox_event_id = '$2') || '/' || (select count(*) from $SCHEMA.outbox_event where outbox_event_id = '$2' and association_id = '$1' and tenant_id = '$tenant')"
}
association_transition() { # suffix, event type, previous SQL value, new status
  local association="$(aid "$1")" event="$(aid "$(( $1 + 100 ))")"
  local rollback_event="$(aid "$(( $1 + 200 ))")" change prior status=0
  if [ "$2" = EstablishmentAssociationPublished ]; then
    change="$(ae_row "'$association'")"; prior=ABSENT
  else
    engine "$(ae_insert HOTEL "'Outbox fixture'" "'T-04'" "${3//\'/}" "'$association'");" || return
    change="update $ae_table set association_status = '$4', updated_at = now() where association_id = '$association' and tenant_id = '$tenant'"
    prior="${3//\'/}"
  fi
  engine "begin; $change; $(association_event "$rollback_event" "$association" "$2" "$3" "$4"); rollback;" || status=$?
  check "visibilityChangeWritesItsOutboxRowInTheSameTransaction: $2 rollback executes successfully as $app" "$status"
  check "$2 rollback leaves neither its event nor its association change" "$([ "$(association_state "$association" "$rollback_event")" = "$prior/0/0" ]; echo $?)"
  status=0
  engine "begin; $change; $(association_event "$event" "$association" "$2" "$3" "$4"); commit;" || status=$?
  check "visibilityChangeWritesItsOutboxRowInTheSameTransaction: $2 commits successfully as $app" "$status"
  check "$2 commits the change and exactly one event with the association id and tenant" "$([ "$(association_state "$association" "$event")" = "$4/1/1" ]; echo $?)"
  engine "select outbox_event_id, event_type, tenant_id, service_id, association_id, previous_catalog_status, new_catalog_status from $SCHEMA.outbox_event where outbox_event_id in ('$event', '$rollback_event');"
}
echo "HU-COM-002 T-04 - all three association transitions, not catalog events"
association_transition 201 EstablishmentAssociationPublished NULL ACTIVE
association_transition 202 EstablishmentAssociationInactivated "'ACTIVE'" INACTIVE
# A second tenant makes an accidentally hardcoded tenant observable.
saved_tenant="$tenant"; tenant="$other_tenant"
association_transition 203 EstablishmentAssociationReactivated "'INACTIVE'" ACTIVE
tenant="$saved_tenant"
trigger_writers="$(sql "select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = '$SCHEMA' and not t.tgisinternal and (c.relname in ('associated_establishment', 'associated_establishment_image', 'outbox_event') or pg_get_functiondef(t.tgfoid) ilike '%outbox_event%')")"
check "D-07: no application trigger on the associations or outbox and no trigger function writes outbox_event" "$([ "$trigger_writers" = 0 ]; echo $?)"
events_before="$(sql "select count(*) from $SCHEMA.outbox_event")"
engine "begin; $(ae_row "'$(aid 204)'"); update $ae_table set association_status = 'INACTIVE' where association_id = '$(aid 204)'; update $ae_table set association_status = 'ACTIVE' where association_id = '$(aid 204)'; commit;"
check "D-07: insert, inactivation and reactivation without an application event write no outbox row" "$([ "$(sql "select count(*) from $SCHEMA.outbox_event")" = "$events_before" ]; echo $?)"

# AC-D1.5, RNF-D4, RNF-D5: rules every table of the schema must keep, judged over the catalog so that T-08 inherits them
tables="$(sql "select count(*) from pg_tables where schemaname = '$SCHEMA'")"
no_tenant="$(sql "select count(*) from pg_tables t where t.schemaname = '$SCHEMA' and not exists (select 1 from pg_attribute a where a.attrelid = format('%I.%I', t.schemaname, t.tablename)::regclass and a.attname = 'tenant_id' and a.attnum > 0 and a.attnotnull and a.atttypid = 'uuid'::regtype)")"
no_tenant_index="$(sql "select count(*) from pg_tables t where t.schemaname = '$SCHEMA' and not exists (select 1 from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = i.indkey[0] where i.indrelid = format('%I.%I', t.schemaname, t.tablename)::regclass and a.attname = 'tenant_id')")"
check "everyTableCarriesAMandatoryIndexedTenantId: every table has a mandatory uuid tenant_id" "$([ "$tables" -ge 4 ] && [ "$no_tenant" = 0 ]; echo $?)"
check "everyTableCarriesAMandatoryIndexedTenantId: every table has an index that starts with tenant_id" "$([ "$tables" -ge 4 ] && [ "$no_tenant_index" = 0 ]; echo $?)"
unnamed="$(sql "select count(*) from pg_constraint c join pg_namespace n on n.oid = c.connamespace where n.nspname = '$SCHEMA' and c.contype in ('p','u','c','f') and c.conname !~ '^(pk|uq|chk|fk)_'")"
check "every constraint has an explicit name" "$([ "$tables" -ge 2 ] && [ "$unnamed" = 0 ]; echo $?)"
unnamed_index="$(sql "select count(*) from pg_indexes where schemaname = '$SCHEMA' and indexname !~ '^(pk|uq|idx)_'")"
check "every index has an explicit name" "$([ "$tables" -ge 2 ] && [ "$unnamed_index" = 0 ]; echo $?)"
enums="$(sql "select count(*) from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = '$SCHEMA' and t.typtype = 'e'")"
foreign_keys_out="$(sql "select count(*) from pg_constraint c join pg_class r on r.oid = c.confrelid join pg_namespace n on n.oid = r.relnamespace where c.contype = 'f' and n.nspname <> '$SCHEMA'")"
check "no closed value set is an ENUM and no foreign key leaves the schema" "$([ "$tables" -ge 2 ] && [ "$enums" = 0 ] && [ "$foreign_keys_out" = 0 ]; echo $?)"

# AC-D1.6 and ADR-004 D10 point 6: as the application user, on the two technical tables it may purge, while any other table stays without DELETE (the probe table of T-06)
app_insert="$(as_role "$app" "$(insert_key "repeat('c', 9)")")"
app_update="$(as_role "$app" "update $SCHEMA.idempotency_key set resource_type = 'catalog_service' where key = repeat('c', 9)")"
app_delete="$(as_role "$app" "delete from $SCHEMA.idempotency_key where key = repeat('c', 9)")"
check "the application user can INSERT into the idempotency table" "$(echo "$app_insert" | grep -q '^INSERT 0 1'; echo $?)"
check "the application user can UPDATE the idempotency table" "$(echo "$app_update" | grep -q '^UPDATE 1'; echo $?)"
check "the application user can DELETE from the idempotency table (daily purge, ADR-004 D10)" "$(echo "$app_delete" | grep -q '^DELETE [1-9]'; echo $?)"
app_outbox_insert="$(as_role "$app" "$(outbox_insert CatalogServiceReactivated INACTIVE ACTIVE)")"
app_outbox_delete="$(as_role "$app" "delete from $SCHEMA.outbox_event")"
check "the application user can INSERT into the outbox" "$(echo "$app_outbox_insert" | grep -q '^INSERT 0 1'; echo $?)"
check "the application user can DELETE from the outbox (daily purge, ADR-004 D10)" "$(echo "$app_outbox_delete" | grep -q '^DELETE [1-9]'; echo $?)"
deletable="$(sql "select string_agg(t.table_name, ',' order by t.table_name) from information_schema.tables t where t.table_schema = '$SCHEMA' and has_table_privilege('$app', format('%I.%I', t.table_schema, t.table_name), 'DELETE')")"
check "DELETE is held on those two technical tables and on no other" "$([ "$deletable" = "idempotency_key,outbox_event" ]; echo $?)"
sql "delete from $SCHEMA.outbox_event; delete from $SCHEMA.idempotency_key" >/dev/null 2>&1 || true

echo "step 2 - update again applies nothing"
second="$(liquibase update 2>&1)"
check "no changeset ran the second time" "$(echo "$second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets' ; echo $?)"

echo "step 3 - rollback-count 999 leaves the database empty"
liquibase rollback-count 999 >/dev/null
check "the schema $SCHEMA is gone" "$([ "$(sql "select count(*) from pg_namespace where nspname='$SCHEMA'")" = 0 ]; echo $?)"
left="$(sql "select count(*) from information_schema.tables where table_schema not in ('pg_catalog','information_schema') and table_name not like 'databasechangelog%'")"
check "no table is left besides the control tables" "$([ "$left" = 0 ]; echo $?)"
# Roles belong to the cluster, not to the schema: dropping the schema leaves them behind, and step 4
# would then fail with "role already exists".
leftover="$(sql "select count(*) from pg_roles where rolname in ('$reader','$writer')")"
check "the reader and the writer roles are gone" "$([ "$leftover" = 0 ]; echo $?)"
check "the application user, created by CI, is left alone" "$([ "$(sql "select count(*) from pg_roles where rolname = '$app'")" = 1 ]; echo $?)"

echo "step 4 - update rebuilds"
liquibase update >/dev/null
check "the schema $SCHEMA exists again" "$([ "$(sql "select count(*) from pg_namespace where nspname='$SCHEMA'")" = 1 ]; echo $?)"

# The two changesets of service_id (ddl-alter-002, ddl-indexes-003) must undo cleanly: the table goes
# back to its five columns, with no foreign key to the catalog and no index on the service, and a new
# update brings the sixth column back. Liquibase rolls back whole runs, so the count is taken from the
# control table: everything applied from ddl-alter-002 onward.
echo "step 5 - the service_id changesets roll back to the table as it was"
undo="$(sql "select count(*) from $CONTROL where orderexecuted >= (select orderexecuted from $CONTROL where id = 'ddl-alter-002')")"
liquibase rollback-count "$undo" >/dev/null
cap_cols_now() { sql "select string_agg(column_name || ' ' || data_type || ' ' || is_nullable, ',' order by ordinal_position) from information_schema.columns where table_schema = '$SCHEMA' and table_name = 'salida_capacity'" 2>/dev/null || true; }
check "after the rollback salida_capacity has its five original columns" "$([ "$(cap_cols_now)" = "${expected_cap_columns%,service_id uuid NO}" ]; echo $?)"
check "after the rollback no foreign key and no service index remain on salida_capacity" "$([ "$(sql "select (select count(*) from pg_constraint where conrelid = '$cap_table'::regclass and contype = 'f') + (select count(*) from pg_indexes where schemaname = '$SCHEMA' and tablename = 'salida_capacity' and indexname = 'idx_salida_capacity_tenant_id_service_id')")" = 0 ]; echo $?)"
liquibase update >/dev/null
check "a new update brings the sixth column back" "$([ "$(cap_cols_now)" = "$expected_cap_columns" ]; echo $?)"
check "the control table holds the 23 changesets" "$([ "$(sql "select count(*) from $CONTROL")" = 23 ]; echo $?)"

# HU-COM-002: its seven changesets (label HU-COM-002) go on top of the 16 of HU-COM-001, exactly as they do
# on a database that already has the 16. The label filter rebuilds that database; rolling back the five must
# leave the schema as it was (columns, constraints, indexes and privileges), and a new update brings them back.
echo "step 6 - the seven HU-COM-002 changesets roll back to the 16 of HU-COM-001 and come back"
snapshot() { sql "select md5(string_agg(x, '|' order by x)) from (
    select 'c:' || table_name || '.' || column_name || ' ' || data_type || ' ' || is_nullable || ' ' || coalesce(column_default, '') as x from information_schema.columns where table_schema = '$SCHEMA'
    union all select 'k:' || conrelid::regclass::text || ' ' || conname || ' ' || pg_get_constraintdef(oid) from pg_constraint where connamespace = '$SCHEMA'::regnamespace
    union all select 'i:' || indexdef from pg_indexes where schemaname = '$SCHEMA'
    union all select 'p:' || grantee || ' ' || table_name || ' ' || privilege_type from information_schema.role_table_grants where table_schema = '$SCHEMA') s" 2>/dev/null || true; }
liquibase rollback-count 999 >/dev/null
liquibase update --label-filter='!HU-COM-002 and !HU-COM-003 and !HU-COM-004 and !HU-COM-005 and !HU-COM-006 and !HU-WRK-007 and !HU-COM-007 and !HU-COM-008 and !HU-COM-009' >/dev/null
check "the 16 changesets of HU-COM-001 build alone, without the label HU-COM-002" "$([ "$(sql "select count(*) from $CONTROL")" = 16 ]; echo $?)"
tables_now() { sql "select count(*) from pg_tables where schemaname = '$SCHEMA' and tablename like 'associated_establishment%'" 2>/dev/null || true; }
check "on that base neither HU-COM-002 table exists" "$([ "$(tables_now)" = 0 ]; echo $?)"
before_snapshot="$(snapshot)"
base_tables="$(sql "select string_agg(tablename, ',' order by tablename) from pg_tables where schemaname = '$SCHEMA'")"
liquibase update >/dev/null
new_changesets="$(sql "select count(*) from $CONTROL where labels ilike '%HU-COM-002%'" 2>/dev/null || echo 0)"
check "an update on that base applies exactly the 7 changesets of HU-COM-002" "$([ "$new_changesets" = 7 ] && [ "$(sql "select count(*) from $CONTROL")" = 23 ]; echo $?)"
check "both HU-COM-002 tables exist after it" "$([ "$(tables_now)" = 2 ]; echo $?)"
if [ "$new_changesets" -gt 0 ]; then liquibase rollback-count "$new_changesets" >/dev/null; fi
check "rolling back the HU-COM-002 changesets leaves the control table at the 16" "$([ "$(sql "select count(*) from $CONTROL")" = 16 ]; echo $?)"
check "...neither of its tables remains" "$([ "$(tables_now)" = 0 ]; echo $?)"
check "HU-COM-002 T-05: all HU-COM-001 tables survive the seven-change revert" "$([ "$(sql "select string_agg(tablename, ',' order by tablename) from pg_tables where schemaname = '$SCHEMA'")" = "$base_tables" ]; echo $?)"
check "...and the schema is as it was before them: same columns, constraints, indexes and privileges" "$([ -n "$before_snapshot" ] && [ "$(snapshot)" = "$before_snapshot" ]; echo $?)"
liquibase update >/dev/null
check "a new update creates them again" "$([ "$(tables_now)" = 2 ] && [ "$(sql "select count(*) from $CONTROL")" = 23 ]; echo $?)"

# T-04, the third probe: a second domain migrating the same instance with its own control table
# neither fails nor touches this one (Annex J.6).
echo "probe - another domain migrates the same instance"
applied_before="$(sql "select count(*) from $CONTROL")"
probe_dir="$(mktemp -d)"
printf 'databaseChangeLog: []\n' > "$probe_dir/probe.yaml"
# the runner container's user is not the owner of this temporary folder, so it must be readable by others
chmod 755 "$probe_dir" && chmod 644 "$probe_dir/probe.yaml"
probe_host="$(cd "$probe_dir" && (pwd -W 2>/dev/null || pwd))"
probe_status=0
MSYS_NO_PATHCONV=1 docker run --rm --network "$network" -e LIQUIBASE_COMMAND_PASSWORD -v "$probe_host:/liquibase/probe" -w /liquibase/probe "$runner_image" \
  --url="jdbc:postgresql://$container:5432/postgres" --username=postgres \
  --changelog-file=probe.yaml \
  --database-changelog-table-name=databasechangelog_probe_domain \
  --database-changelog-lock-table-name=databasechangeloglock_probe_domain update >/dev/null 2>&1 || probe_status=$?
rm -rf "$probe_dir"
check "a second domain with its own control table migrates without collision" "$probe_status"
mine="$(sql "select count(*) from $CONTROL")"
check "this domain's control table is untouched by it" "$([ "$mine" = "$applied_before" ] && [ "$mine" -gt 0 ]; echo $?)"

# T-05, AC-D1.12: the compose file holds only the runner, and the runner needs no volume because the
# migrations travel inside its image. The static half (no database image, no volumes, no extension)
# is tests/check-structure.sh; this half asks Docker what the file means.
echo "T-05 - deploy/compose.yml holds only the runner"
compose_file="deploy/compose.yml"
compose_env=(env PG_DATABASE=platform PG_ADMIN_USER=migrator "PG_ADMIN_PASSWORD=$throwaway")
check "the runner image carries the migrations" "$(MSYS_NO_PATHCONV=1 docker run --rm --entrypoint test "$runner_image" -f /liquibase/work/changelog/changelog-master.yaml; echo $?)"
check "compose validates the file when the three variables are given" "$("${compose_env[@]}" docker compose -f "$compose_file" config -q >/dev/null 2>&1; echo $?)"
missing="$(env PG_DATABASE=platform PG_ADMIN_USER=migrator docker compose -f "$compose_file" config -q 2>&1 || true)"
check "compose refuses the file when PG_ADMIN_PASSWORD is missing" "$(echo "$missing" | grep -q 'PG_ADMIN_PASSWORD'; echo $?)"
# The infrastructure's root file includes this one and defines the postgres service it waits for.
# A stand-in for that root file shows what the runner becomes once composed.
root_dir="$(mktemp -d)"
printf 'include:\n  - %s\nservices:\n  postgres:\n    image: %s\n' "$host_dir/$compose_file" "$POSTGRES_IMAGE" > "$root_dir/root.yml"
composed="$("${compose_env[@]}" docker compose --profile tooling -f "$root_dir/root.yml" config 2>&1 || true)"
services="$("${compose_env[@]}" docker compose --profile tooling -f "$root_dir/root.yml" config --services 2>&1 | sort | tr '\n' ' ' || true)"
rm -rf "$root_dir"
check "composed with the instance, the only service besides postgres is the runner" "$([ "$services" = "commercial-reservation-db-migrate postgres " ]; echo $?)"
check "the runner waits for postgres to be healthy" "$(echo "$composed" | grep -q 'condition: service_healthy'; echo $?)"
check "the runner points at the single instance" "$(echo "$composed" | grep -q 'jdbc:postgresql://postgres:5432/platform'; echo $?)"
check "the runner passes the control table of this domain" "$(echo "$composed" | grep -q -e "--database-changelog-table-name=$CONTROL"; echo $?)"
check "the runner passes the lock table of this domain" "$(echo "$composed" | grep -q -e "--database-changelog-lock-table-name=$LOCK"; echo $?)"
check "the runner sits on the external platform network" "$(echo "$composed" | grep -q 'external: true'; echo $?)"

# T-06: literal reconstruction record, in section 8's order. Reuse this single
# disposable instance; never roll back a developer's infrastructure database.
echo "HU-COM-002 T-06 - section 8, eleven steps (literal engine and runner answers)"
liquibase rollback-count 999
liquibase update --label-filter='!HU-COM-002 and !HU-COM-003 and !HU-COM-004 and !HU-COM-005 and !HU-COM-006 and !HU-WRK-007 and !HU-COM-007 and !HU-COM-008 and !HU-COM-009'
record_base="$(snapshot)"
echo "T-06 STEP 1 - apply this slice over HU-COM-001 (16 -> 23)"
liquibase update
engine "select count(*) as changesets from $CONTROL; select schemaname, tablename from pg_tables where schemaname in ('$SCHEMA','public') order by 1,2;" postgres
echo "T-06 STEP 2 - inspect attributes and forbidden columns"
engine "select table_name, column_name, data_type, is_nullable from information_schema.columns where table_schema = '$SCHEMA' and table_name like 'associated_establishment%' order by table_name, ordinal_position;"
echo "T-06 STEP 3 - a third establishment type"
engine "$(ae_insert LODGING "'Rejected type'" "'T-06'" ACTIVE);" || true
echo "T-06 STEP 4 - a null tenant"
engine "insert into $ae_table (association_id, tenant_id, establishment_type, commercial_name, commercial_information, association_status, created_at, updated_at) values (gen_random_uuid(), null, 'HOTEL', 'Rejected tenant', 'T-06', 'ACTIVE', now(), now());" || true
echo "T-06 STEP 5 - application DELETE"
engine "delete from $ae_table;" || true
echo "T-06 STEP 6 - association with image, without image, and explicit rollback"
engine "begin; $(ae_row "'$(aid 301)'"); $(img_insert "$(aid 301)" image/png 1024); commit; select a.association_id, a.tenant_id, i.image_id from $ae_table a join $img_table i using (association_id) where a.association_id = '$(aid 301)';"
engine "begin; $(ae_row "'$(aid 302)'"); commit; select association_id from $ae_table where association_id = '$(aid 302)';"
echo "STEP 6 LIMITATION: DP-03 closed by models.md; the engine accepts no image, the API refuses it."
engine "begin; $(ae_row "'$(aid 303)'"); $(img_insert "$(aid 303)" image/png 1024); rollback; select (select count(*) from $ae_table where association_id = '$(aid 303)') as associations, (select count(*) from $img_table where association_id = '$(aid 303)') as images;"
echo "T-06 STEP 7 - inspect image content, type, size, checksum and tenant"
engine "select image_id, tenant_id, association_id, encode(content, 'hex') as content_hex, content_type, size_bytes, sha256 from $img_table;"
echo "T-06 STEP 8 - three visibility transitions (same transaction, application role)"
association_transition 401 EstablishmentAssociationPublished NULL ACTIVE
association_transition 402 EstablishmentAssociationInactivated "'ACTIVE'" INACTIVE
association_transition 403 EstablishmentAssociationReactivated "'INACTIVE'" ACTIVE
echo "T-06 STEP 9 - second update, no pending changesets"
record_second="$(liquibase update 2>&1)"; printf '%s\n' "$record_second"
check "secondRunAppliesZeroChangesets: T-06 incremental second update applies zero" "$(echo "$record_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
echo "T-06 STEP 10 - revert exactly seven changesets to HU-COM-001"
engine "delete from $SCHEMA.outbox_event where association_id is not null;"
liquibase rollback-count 7
engine "select count(*) as changesets from $CONTROL; select tablename from pg_tables where schemaname = '$SCHEMA' order by 1;" postgres
record_reverted="$(snapshot)"
printf 'HU-COM-001 columns/constraints/indexes/privileges MD5: %s\nReverted MD5: %s\n' "$record_base" "$record_reverted"
check "revertRemovesTheTwoTablesAndLeavesTheSchemaAsOneHadIt: T-06 MD5 matches HU-COM-001" "$([ -n "$record_base" ] && [ "$record_base" = "$record_reverted" ]; echo $?)"
echo "T-06 STEP 11 - rule coverage and specification trace"
echo "RN-01 typeOutsideHotelAndRestaurantIsRefusedByTheEngine; RN-02 forbidden columns; RN-03 everyRowCarriesANonNullTenantId; RN-07 applicationUserCannotDeleteAnAssociation; RN-08 sizeAbove800KbOrTypeOutsidePngJpegWebpIsRefusedByTheEngine; RN-09 associationAndImageAreWrittenInOneTransaction; RN-10 transport only (no engine test); RN-11 visibilityChangeWritesItsOutboxRowInTheSameTransaction."
if [ "$fail" -eq 0 ]; then
  echo "STEP 11 READY: all engine rule checks pass, including RN-11. The mapping above is ready for the spec's trace cells; no external spec was edited."
else
  echo "STEP 11 BLOCKED: at least one engine rule check failed."
fi
liquibase update

source tests/discount-rule-checks.sh
source tests/customer-checks.sh
source tests/additional-discount-checks.sh
source tests/discount-rule-persistence-checks.sh
source tests/discount-rule-codes-checks.sh
source tests/outbox-widening-checks.sh
source tests/authorizable-reason-checks.sh
source tests/offer-checks.sh
source tests/customer-terms-checks.sh
source tests/tenant-status-checks.sh
source tests/reservation-checks.sh
source tests/reserve-digital-checks.sh
source tests/payment-checks.sh
exit "$fail"
