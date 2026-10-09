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
  MSYS_NO_PATHCONV=1 docker run --rm --network "$network" -e LIQUIBASE_COMMAND_PASSWORD -v "$host_dir:/liquibase/work" -w /liquibase/work "$runner_image" \
    --url="jdbc:postgresql://$container:5432/postgres" --username=postgres \
    --changelog-file=changelog/changelog-master.yaml \
    --database-changelog-table-name="$CONTROL" \
    --database-changelog-lock-table-name="$LOCK" "$@"
}

echo "building the runner image (deploy/Dockerfile)"
docker build -q -t "$runner_image" -f deploy/Dockerfile deploy >/dev/null
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

echo "step 2 - update again applies nothing"
second="$(liquibase update 2>&1)"
check "no changeset ran the second time" "$(echo "$second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets' ; echo $?)"

echo "step 3 - rollback-count 999 leaves the database empty"
liquibase rollback-count 999 >/dev/null
check "the schema $SCHEMA is gone" "$([ "$(sql "select count(*) from pg_namespace where nspname='$SCHEMA'")" = 0 ]; echo $?)"
left="$(sql "select count(*) from information_schema.tables where table_schema not in ('pg_catalog','information_schema') and table_name not like 'databasechangelog%'")"
check "no table is left besides the control tables" "$([ "$left" = 0 ]; echo $?)"

echo "step 4 - update rebuilds"
liquibase update >/dev/null
check "the schema $SCHEMA exists again" "$([ "$(sql "select count(*) from pg_namespace where nspname='$SCHEMA'")" = 1 ]; echo $?)"

# T-04, the third probe: a second domain migrating the same instance with its own control table
# neither fails nor touches this one (Annex J.6).
echo "probe - another domain migrates the same instance"
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
check "this domain's control table is untouched by it" "$([ "$mine" = 1 ]; echo $?)"

exit "$fail"
