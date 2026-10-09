#!/usr/bin/env bash
# The four steps of Annex A against an empty PostgreSQL, in a throwaway container (norm 5.2.8):
#   1. update               builds everything
#   2. update, again        applies nothing
#   3. rollback-count 999   leaves the database empty
#   4. update               rebuilds
# CI and a developer run this same file. Docker is the only requirement.
set -euo pipefail
cd "$(dirname "$0")/.."

POSTGRES_IMAGE="postgres:18"
SCHEMA="commercial_reservation"
CONTROL="databasechangelog_commercial_reservation"
LOCK="databasechangeloglock_commercial_reservation"

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
  # no volume: the migrations are inside the image, exactly as the compose file runs it
  docker run --rm --network "$network" -e LIQUIBASE_COMMAND_PASSWORD "$runner_image" \
    --url="jdbc:postgresql://$container:5432/postgres" --username=postgres \
    --changelog-file=changelog/changelog-master.yaml \
    --database-changelog-table-name="$CONTROL" \
    --database-changelog-lock-table-name="$LOCK" "$@"
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
check "the schema $SCHEMA exists" "$([ "$(sql "select count(*) from pg_namespace where nspname='$SCHEMA'")" = 1 ]; echo $?)"
# T-03, AC-D1.1: nothing of this domain lives in public (Annex A rule 9, Annex J.4)
in_public="$(sql "select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasechangelog%'")"
check "no object of the domain lives in public" "$([ "$in_public" = 0 ]; echo $?)"
# T-04, AC-D1.11: the control table is this domain's own, and the default one never appears (Annex J.6)
own="$(sql "select count(*) from information_schema.tables where table_name = '$CONTROL'")"
default_table="$(sql "select count(*) from information_schema.tables where table_name = 'databasechangelog'")"
check "the control table $CONTROL exists" "$([ "$own" = 1 ]; echo $?)"
check "the default control table databasechangelog does not exist" "$([ "$default_table" = 0 ]; echo $?)"

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

# AC-D1.5, RNF-D4, RNF-D5: rules every table of the schema must keep, judged over the catalog so that T-08 inherits them
tables="$(sql "select count(*) from pg_tables where schemaname = '$SCHEMA'")"
no_tenant="$(sql "select count(*) from pg_tables t where t.schemaname = '$SCHEMA' and not exists (select 1 from pg_attribute a where a.attrelid = format('%I.%I', t.schemaname, t.tablename)::regclass and a.attname = 'tenant_id' and a.attnum > 0 and a.attnotnull and a.atttypid = 'uuid'::regtype)")"
no_tenant_index="$(sql "select count(*) from pg_tables t where t.schemaname = '$SCHEMA' and not exists (select 1 from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = i.indkey[0] where i.indrelid = format('%I.%I', t.schemaname, t.tablename)::regclass and a.attname = 'tenant_id')")"
check "everyTableCarriesAMandatoryIndexedTenantId: every table has a mandatory uuid tenant_id" "$([ "$tables" -ge 3 ] && [ "$no_tenant" = 0 ]; echo $?)"
check "everyTableCarriesAMandatoryIndexedTenantId: every table has an index that starts with tenant_id" "$([ "$tables" -ge 3 ] && [ "$no_tenant_index" = 0 ]; echo $?)"
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
compose_env=(env PG_DATABASE=platform PG_USER=migrator "PG_PASSWORD=$throwaway")
check "the runner image carries the migrations" "$(MSYS_NO_PATHCONV=1 docker run --rm --entrypoint test "$runner_image" -f /liquibase/work/changelog/changelog-master.yaml; echo $?)"
check "compose validates the file when the three variables are given" "$("${compose_env[@]}" docker compose -f "$compose_file" config -q >/dev/null 2>&1; echo $?)"
missing="$(env PG_DATABASE=platform PG_USER=migrator docker compose -f "$compose_file" config -q 2>&1 || true)"
check "compose refuses the file when PG_PASSWORD is missing" "$(echo "$missing" | grep -q 'PG_PASSWORD'; echo $?)"
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

exit "$fail"
