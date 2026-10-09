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

# ---- 4. common files (norm 5.1, Annex I); CODEOWNERS is never modified (norm 13)
for file in README.md .gitignore .env.example .github/CODEOWNERS .github/pull_request_template.md; do
  [ -f "$file" ] || bad "$file is missing"
done
grep -q '@ariel5253' .github/CODEOWNERS 2>/dev/null || bad ".github/CODEOWNERS no longer names @ariel5253"
for ignored in '^\.env$' '^\*\.pem$' '^keys/$'; do
  grep -q "$ignored" .gitignore 2>/dev/null || bad ".gitignore does not ignore the pattern $ignored"
done

# ---- 5. .env.example lists every key with a placeholder and never a real value (constitution article XI)
if [ -f .env.example ]; then
  grep -qE '^[A-Z][A-Z0-9_]*=' .env.example || bad ".env.example lists no variable"
  while IFS= read -r row; do
    case "$row" in ''|\#*) continue ;; esac
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

if [ "$fail" -eq 0 ]; then echo "OK: structure check passed"; fi
exit "$fail"
