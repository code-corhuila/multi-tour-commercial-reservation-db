#!/usr/bin/env bash
# Structure check of the repository (Annex A, norm 5.1, Annex I). It runs before any migration is
# built: a file outside the master changelog does not exist, and a secret in a repository that is
# public is a grave fault.
set -u
cd "$(dirname "$0")/.."

fail=0
bad() { echo "FAIL: $1"; fail=1; }

# ---- 1. every family and subfolder of Annex A carries its changelog.yaml, even when empty
families=(01_ddl 02_dml 03_dcl 04_tcl)
ddl=(00_extensions 01_schemas 02_types 03_tables 04_alter 05_views 06_materialized_views
     07_functions 08_procedures 09_triggers 10_indexes)
dml=(00_inserts 01_updates 02_deletes 03_upserts 04_patches)
dcl=(00_roles 01_grants 02_policies)
tcl=(00_transaction_blocks 01_manual_recoveries 02_release_tags)

check_family() {
  local family="$1"; shift
  [ -f "$family/changelog.yaml" ] || bad "$family/changelog.yaml is missing"
  local previous=""
  for sub in "$@"; do
    [ -f "$family/$sub/changelog.yaml" ] || bad "$family/$sub/changelog.yaml is missing"
    # the include order of the family changelog is the execution order
    local line
    line=$(grep -n "$sub/changelog.yaml" "$family/changelog.yaml" 2>/dev/null | head -1 | cut -d: -f1)
    [ -n "$line" ] || { bad "$family/changelog.yaml does not include $sub"; continue; }
    if [ -n "$previous" ] && [ "$line" -le "$previous" ]; then bad "$family/changelog.yaml includes $sub out of order"; fi
    previous="$line"
  done
}
check_family 01_ddl "${ddl[@]}"
check_family 02_dml "${dml[@]}"
check_family 03_dcl "${dcl[@]}"
check_family 04_tcl "${tcl[@]}"

# ---- 2. the master changelog is the single entry point and includes every family in order
master=changelog/changelog-master.yaml
[ -f "$master" ] || bad "$master is missing"
if [ -f "$master" ]; then
  previous=""
  for family in "${families[@]}"; do
    line=$(grep -n "$family/changelog.yaml" "$master" | head -1 | cut -d: -f1)
    [ -n "$line" ] || { bad "$master does not include $family"; continue; }
    if [ -n "$previous" ] && [ "$line" -le "$previous" ]; then bad "$master includes $family out of order"; fi
    previous="$line"
  done
fi

# ---- 3. the rollback mirror exists, and no extension is created here (plan.md D-10, Annex J.4)
[ -d 05_rollbacks ] || bad "05_rollbacks/ is missing"
if ls 01_ddl/00_extensions/*.sql >/dev/null 2>&1; then bad "01_ddl/00_extensions must stay empty: extensions belong to the instance (Annex J.4)"; fi

# ---- 3b. the migrations define no extension, no login and no secret (AC-D1.12, RNF-D8, Annex J.4, J.7).
# Comments (SQL, YAML and the changeset comment field) are stripped first: they may explain why something is absent without being it.
# The deploy folder names the PG_ADMIN_PASSWORD variable the runner reads, so only the migrations are searched for LOGIN and passwords.
sql_text() { find "$@" -type f \( -name '*.sql' -o -name '*.yaml' -o -name '*.yml' -o -name Dockerfile \) -print0 | xargs -0 -r sed 's/--.*$//; s/^[[:space:]]*#.*$//; /^[[:space:]]*comment:/d'; }
sql_text 01_ddl 02_dml 03_dcl 04_tcl 05_rollbacks deploy | grep -qiE 'create[[:space:]]+extension' && bad "an extension is created in the migrations or in deploy/: it belongs to the instance (Annex J.4)"
sql_text 01_ddl 02_dml 03_dcl 04_tcl 05_rollbacks | grep -qiE '(^|[^a-z_])login([^a-z_]|$)|password' && bad "a LOGIN role or a password appears in the migrations: users are created by the infrastructure from secrets (Annex A rule 10)"
sql_text 01_ddl 02_dml 03_dcl 04_tcl 05_rollbacks | grep -qiE 'create[[:space:]]+(role|user)[[:space:]]+commercial_reservation_app' && bad "commercial_reservation_app is created here: the infrastructure creates it (Annex J.7)"

# ---- 3c. deploy/compose.yml holds only the migration runner (AC-D1.12, RNF-D1, Annex J.7)
compose=deploy/compose.yml
if [ ! -f "$compose" ]; then
  bad "$compose is missing (T-05)"
else
  body="$(sed 's/^[[:space:]]*#.*$//' "$compose")"
  echo "$body" | grep -qE '^[[:space:]]*image:[[:space:]]*["'"'"']?postgres' && bad "$compose defines a PostgreSQL image: the instance belongs to multi-tour-infra-postgres"
  echo "$body" | grep -qE '^[[:space:]]*volumes:' && bad "$compose declares volumes: the data lives in the instance"
  services="$(echo "$body" | awk '/^services:/{s=1;next} /^[^ ]/{s=0} s && /^  [A-Za-z0-9_-]+:/{n++} END{print n+0}')"
  [ "$services" = 1 ] || bad "$compose must define exactly one service, the runner (found $services)"
  echo "$body" | grep -qE 'profiles:.*tooling|^[[:space:]]*-[[:space:]]*tooling' || bad "$compose does not put the runner in the tooling profile"
  echo "$body" | grep -q 'condition: service_healthy' || bad "$compose does not wait for the postgres service to be healthy"
  echo "$body" | grep -q 'jdbc:postgresql://postgres:5432/${PG_DATABASE' || bad "$compose does not point at the single instance by jdbc:postgresql://postgres:5432/\${PG_DATABASE}"
  for name in databasechangelog_commercial_reservation databasechangeloglock_commercial_reservation; do
    echo "$body" | grep -q "$name" || bad "$compose does not pass the control table $name (Annex J.6)"
  done
  for var in PG_ADMIN_USER PG_ADMIN_PASSWORD PG_DATABASE; do
    echo "$body" | grep -q "\${$var:?" || bad "$compose does not require $var without a default"
  done
fi

# ---- 4. common files (norm 5.1, Annex I); CODEOWNERS is never modified (norm 13)
for file in README.md .gitignore .env.example .github/CODEOWNERS .github/pull_request_template.md; do
  [ -f "$file" ] || bad "$file is missing"
done
grep -q '@ariel5253' .github/CODEOWNERS 2>/dev/null || bad ".github/CODEOWNERS no longer names @ariel5253"
for ignored in '^\.env' '^\*\.pem' '^keys/'; do
  grep -qE "${ignored}\\r?$" .gitignore 2>/dev/null || bad ".gitignore does not ignore the pattern $ignored"
done

# ---- 5. .env.example lists every key with a placeholder and never a real value (constitution article XI)
if [ -f .env.example ]; then
  grep -qE '^[A-Z][A-Z0-9_]*=' .env.example || bad ".env.example lists no variable"
  while IFS= read -r row; do
    case "$row" in ''|\#*) continue ;; esac
    row="${row%$'\r'}" # a Windows checkout converts line endings; the value is what follows the '='
    key="${row%%=*}"; value="${row#*=}"
    case "$key" in
      *PASSWORD*|*SECRET*|*TOKEN*|*KEY*) [ -z "$value" ] || bad ".env.example gives a value to the secret $key" ;;
    esac
    # the runner builds the connection from parts (Annex J.7): no URL, with or without credentials, is versioned
    case "$value" in *://*) bad ".env.example holds a connection string in $key; list its parts instead" ;; esac
  done < .env.example
fi

# ---- 5b. the workflows keep the course's limits to save automation minutes (notices of 2026-10-07 and 2026-10-08)
[ -f .github/workflows/ci.yml ] || bad ".github/workflows/ci.yml is missing (norm 5.1)"
[ -f .github/workflows/db-ci.yml ] || bad ".github/workflows/db-ci.yml is missing (Annex A)"
for workflow in .github/workflows/*.yml; do
  [ -f "$workflow" ] || continue
  grep -q 'cancel-in-progress: true' "$workflow" || bad "$workflow has no concurrency with cancel-in-progress: true"
  grep -q 'timeout-minutes: 10' "$workflow" || bad "$workflow has no timeout-minutes: 10"
  grep -q 'contents: read' "$workflow" || bad "$workflow does not restrict permissions to contents: read"
  grep -qE '^[[:space:]]*schedule:' "$workflow" && bad "$workflow uses schedule"
  grep -q 'branches: \[develop, qa\]' "$workflow" || bad "$workflow does not run only on pull requests toward develop and qa"
done

# ---- 6. the README answers the five questions of article XV, in order
if [ -f README.md ]; then
  for heading in 'What it is' 'How to start' 'Where its data is' 'How to test' 'What is missing'; do
    grep -q "^## $heading" README.md || bad "README.md has no section '$heading'"
  done
fi

# HU-COM-003: written before the table/index migrations they require.
for entry in '03_tables/007_create_discount_rule' '10_indexes/007_create_discount_rule_indexes' \
  '04_alter/005_generalize_outbox_event_discount_rules' '10_indexes/008_create_outbox_event_discount_rule_index'; do
  folder="${entry%/*}"; stem="${entry##*/}"
  [ -f "01_ddl/$entry.sql" ] || bad "HU-COM-003 migration 01_ddl/$entry.sql is missing"
  [ -f "05_rollbacks/01_ddl/$entry.rollback.sql" ] || bad "HU-COM-003 rollback $entry is missing"
  grep -q "path: $stem.sql" "01_ddl/$folder/changelog.yaml" || bad "HU-COM-003 $stem is not included"
done
# HU-COM-004 T-02: written before the table migration it requires (T-01 is not built: G-C, DP-04-3).
entry="03_tables/010_create_reservation_additional_discount"
[ -f "01_ddl/$entry.sql" ] || bad "HU-COM-004 migration 01_ddl/$entry.sql is missing"
[ -f "05_rollbacks/01_ddl/$entry.rollback.sql" ] || bad "HU-COM-004 rollback $entry is missing"
grep -q "path: 010_create_reservation_additional_discount.sql" 01_ddl/03_tables/changelog.yaml || bad "HU-COM-004 010 is not included"
# HU-COM-003 persistence of the defaults of 2026-10-28 (coverage, optional cap, status); numbers follow the free ones.
for entry in '03_tables/013_create_discount_rule_service' '04_alter/008_add_discount_rule_coverage_cap_and_status' \
  '10_indexes/010_create_discount_rule_service_index'; do
  folder="${entry%/*}"; stem="${entry##*/}"
  [ -f "01_ddl/$entry.sql" ] || bad "HU-COM-003 persistence migration 01_ddl/$entry.sql is missing"
  [ -f "05_rollbacks/01_ddl/$entry.rollback.sql" ] || bad "HU-COM-003 persistence rollback $entry is missing"
  grep -q "path: $stem.sql" "01_ddl/$folder/changelog.yaml" || bad "HU-COM-003 persistence $stem is not included"
done
# HU-COM-003 codes and audit columns (ddl-alter-009): written before the migration it requires.
entry='04_alter/009_migrate_discount_rule_codes_and_add_audit_columns'
[ -f "01_ddl/$entry.sql" ] || bad "HU-COM-003 codes migration 01_ddl/$entry.sql is missing"
[ -f "05_rollbacks/01_ddl/$entry.rollback.sql" ] || bad "HU-COM-003 codes rollback $entry is missing"
grep -q "path: ${entry##*/}.sql" 01_ddl/04_alter/changelog.yaml || bad "HU-COM-003 codes ${entry##*/} is not included"
# HU-COM-004 outbox widening, authorizable reasons and immutable additional discount: written before the migrations.
for entry in '04_alter/010_widen_outbox_event_for_reservation_and_customer_events' '03_tables/014_create_authorizable_reason' \
  '10_indexes/011_create_authorizable_reason_enabled_index'; do
  folder="${entry%/*}"; stem="${entry##*/}"
  [ -f "01_ddl/$entry.sql" ] || bad "HU-COM-004 migration 01_ddl/$entry.sql is missing"
  [ -f "05_rollbacks/01_ddl/$entry.rollback.sql" ] || bad "HU-COM-004 rollback $entry is missing"
  grep -q "path: $stem.sql" "01_ddl/$folder/changelog.yaml" || bad "HU-COM-004 $stem is not included"
done
entry='01_grants/006_revoke_update_on_reservation_additional_discount'
[ -f "03_dcl/$entry.sql" ] || bad "HU-COM-004 grant 03_dcl/$entry.sql is missing"
[ -f "05_rollbacks/03_dcl/$entry.rollback.sql" ] || bad "HU-COM-004 grant rollback $entry is missing"
grep -q "path: ${entry##*/}.sql" 03_dcl/01_grants/changelog.yaml || bad "HU-COM-004 ${entry##*/} is not included"
# HU-COM-006 departure columns, processed events and their indexes and grant: written before the migrations.
for entry in '04_alter/011_add_salida_capacity_departure_columns' '10_indexes/012_create_salida_capacity_start_index' \
  '03_tables/015_create_processed_event' '10_indexes/013_create_processed_event_index'; do
  folder="${entry%/*}"; stem="${entry##*/}"
  [ -f "01_ddl/$entry.sql" ] || bad "HU-COM-006 migration 01_ddl/$entry.sql is missing"
  [ -f "05_rollbacks/01_ddl/$entry.rollback.sql" ] || bad "HU-COM-006 rollback $entry is missing"
  grep -q "path: $stem.sql" "01_ddl/$folder/changelog.yaml" || bad "HU-COM-006 $stem is not included"
done
entry='01_grants/007_grant_delete_on_processed_event'
[ -f "03_dcl/$entry.sql" ] || bad "HU-COM-006 grant 03_dcl/$entry.sql is missing"
[ -f "05_rollbacks/03_dcl/$entry.rollback.sql" ] || bad "HU-COM-006 grant rollback $entry is missing"
grep -q "path: ${entry##*/}.sql" 03_dcl/01_grants/changelog.yaml || bad "HU-COM-006 ${entry##*/} is not included"
# HU-COM-005 terms acceptance on customer (ddl-alter-019): written before the migration it requires.
entry='04_alter/019_add_customer_terms_acceptance'
[ -f "01_ddl/$entry.sql" ] || bad "HU-COM-005 terms migration 01_ddl/$entry.sql is missing"
[ -f "05_rollbacks/01_ddl/$entry.rollback.sql" ] || bad "HU-COM-005 terms rollback $entry is missing"
grep -q "path: ${entry##*/}.sql" 01_ddl/04_alter/changelog.yaml || bad "HU-COM-005 terms ${entry##*/} is not included"
# HU-WRK-007 tenant status table, its identifier guard function and trigger: written before the migrations.
for entry in '03_tables/024_create_tenant_status' '07_functions/003_create_fn_tenant_status_guard' \
  '09_triggers/003_create_trg_tenant_status_identifier_guard'; do
  folder="${entry%/*}"; stem="${entry##*/}"
  [ -f "01_ddl/$entry.sql" ] || bad "HU-WRK-007 migration 01_ddl/$entry.sql is missing"
  [ -f "05_rollbacks/01_ddl/$entry.rollback.sql" ] || bad "HU-WRK-007 rollback $entry is missing"
  grep -q "path: $stem.sql" "01_ddl/$folder/changelog.yaml" || bad "HU-WRK-007 $stem is not included"
done
# HU-COM-007 reservation table, birth function and trigger: written before the migrations.
for entry in '03_tables/016_create_reservation' '07_functions/001_create_trg_reservation_birth_function' \
  '09_triggers/001_create_trg_reservation_birth'; do
  folder="${entry%/*}"; stem="${entry##*/}"
  [ -f "01_ddl/$entry.sql" ] || bad "HU-COM-007 migration 01_ddl/$entry.sql is missing"
  [ -f "05_rollbacks/01_ddl/$entry.rollback.sql" ] || bad "HU-COM-007 rollback $entry is missing"
  grep -q "path: $stem.sql" "01_ddl/$folder/changelog.yaml" || bad "HU-COM-007 $stem is not included"
done
# HU-COM-007 reserved service, fixed discount lines and the keys that waited for the reservation: written before the migrations.
for entry in '03_tables/017_create_reserved_service' '03_tables/018_create_reservation_fixed_discount' \
  '04_alter/013_add_reservation_foreign_keys_to_companion_and_additional_discount'; do
  folder="${entry%/*}"; stem="${entry##*/}"
  [ -f "01_ddl/$entry.sql" ] || bad "HU-COM-007 migration 01_ddl/$entry.sql is missing"
  [ -f "05_rollbacks/01_ddl/$entry.rollback.sql" ] || bad "HU-COM-007 rollback $entry is missing"
  grep -q "path: $stem.sql" "01_ddl/$folder/changelog.yaml" || bad "HU-COM-007 $stem is not included"
done
entry='01_grants/008_revoke_update_on_reservation_fixed_discount'
[ -f "03_dcl/$entry.sql" ] || bad "HU-COM-007 grant 03_dcl/$entry.sql is missing"
[ -f "05_rollbacks/03_dcl/$entry.rollback.sql" ] || bad "HU-COM-007 grant rollback $entry is missing"
grep -q "path: ${entry##*/}.sql" 03_dcl/01_grants/changelog.yaml || bad "HU-COM-007 ${entry##*/} is not included"
# HU-COM-007 second widening of the outbox and the reservation indexes: written before the migrations.
for entry in '04_alter/012_widen_outbox_event_for_reservation_payment_and_capacity_events' \
  '10_indexes/014_create_reservation_tenant_status_index' '10_indexes/015_create_reservation_tenant_salida_index' \
  '10_indexes/016_create_reservation_tenant_customer_index' '10_indexes/017_create_outbox_event_reservation_index'; do
  folder="${entry%/*}"; stem="${entry##*/}"
  [ -f "01_ddl/$entry.sql" ] || bad "HU-COM-007 migration 01_ddl/$entry.sql is missing"
  [ -f "05_rollbacks/01_ddl/$entry.rollback.sql" ] || bad "HU-COM-007 rollback $entry is missing"
  grep -q "path: $stem.sql" "01_ddl/$folder/changelog.yaml" || bad "HU-COM-007 $stem is not included"
done
if [ "$fail" -eq 0 ]; then echo "OK: structure check passed"; fi
exit "$fail"
