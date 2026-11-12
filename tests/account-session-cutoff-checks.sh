#!/usr/bin/env bash
# Sourced by db-ci.sh after payment-parameters-changed-checks.sh, on the same disposable PostgreSQL instance, with every changeset that exists before the slice (counted at run time); the slice is one changeset, 039 of the tables.
# HU-SEC-005 AC4 and HU-SEC-006 AC7 -db (docs spec 022, PROPOSED): the table account_session_cutoff, one row per revoked account (account_id, tenant_id, revoked_from, created_at, updated_at). The key is the account and there is no
# foreign key (accounts belong to security). No DEFAULT: the service states every instant. The application user inserts, updates and selects; nobody deletes. The changeset is labelled account-session-cutoff.
# Probes are written first: red before the changeset, green after (Annex J.1).
sc_t="$SCHEMA.account_session_cutoff"
sc_sql() { sql "$1" 2>/dev/null || true; }
sc_row() { # account id, tenant id, then column/value pairs that replace the defaults
  local acc="${1:-gen_random_uuid()}" ten="${2:-gen_random_uuid()}"
  echo "insert into $sc_t (account_id, tenant_id, revoked_from, created_at, updated_at) values ($acc, $ten, now(), now(), now())"
}
sc_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "account session cutoff: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
sc_accepted() { # SQL, description
  local status=0
  engine "begin; $1; rollback;" >/dev/null || status=$?
  check "account session cutoff: $2 is accepted" "$status"
}

echo 'account session cutoff - base: every changeset that exists before the slice'
liquibase rollback-count 999 >/dev/null
db_labels='!account-session-cutoff'
liquibase update >/dev/null
sc_base="$(snapshot)"
sc_n0="$(sql "select count(*) from $CONTROL")"
check "the base holds every changeset except the one of the slice ($sc_n0)" "$([ "$sc_n0" -gt 0 ] && [ "$(sql "select count(*) from $CONTROL where labels ilike '%account-session-cutoff%'")" = 0 ]; echo $?)"
check 'on that base the table does not exist' "$([ "$(sql "select to_regclass('$sc_t') is null")" = t ]; echo $?)"

echo 'account session cutoff - probes written first: red before the changeset, green after'
db_labels='account-session-cutoff'
liquibase update >/dev/null
check 'the changeset of the slice adds one changeset to the control table' "$([ "$(sql "select count(*) from $CONTROL")" = "$((sc_n0 + 1))" ]; echo $?)"

echo 'the table (AC-D22.1)'
sc_cols='account_id uuid NO,tenant_id uuid NO,revoked_from timestamp with time zone NO,created_at timestamp with time zone NO,updated_at timestamp with time zone NO'
check 'AC-D22.1 account_session_cutoff holds its five columns, all required' "$([ "$(cols_of account_session_cutoff)" = "$sc_cols" ]; echo $?)"
check 'AC-D22.1 no column has a DEFAULT and there is no foreign key' "$([ "$(sc_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='account_session_cutoff' and column_default is not null")" = 0 ] && [ "$(sc_sql "select count(*) from pg_constraint where conrelid='$sc_t'::regclass and contype='f'")" = 0 ]; echo $?)"
check 'AC-D22.2 the primary key is account_id' "$([ "$(sc_sql "select pg_get_constraintdef(oid) from pg_constraint where conname='pk_account_session_cutoff' and conrelid='$sc_t'::regclass")" = 'PRIMARY KEY (account_id)' ]; echo $?)"
sc_names='chk_account_session_cutoff_account_id_required,chk_account_session_cutoff_created_at_required,chk_account_session_cutoff_revoked_from_required,chk_account_session_cutoff_tenant_id_required,chk_account_session_cutoff_updated_at_required,pk_account_session_cutoff'
check 'AC-D22.3 the named constraints are exactly the planned ones' "$([ "$(sc_sql "select string_agg(conname, ',' order by conname collate \"C\") from pg_constraint where conrelid='$sc_t'::regclass and contype <> 'n'")" = "$sc_names" ]; echo $?)"
sc_accepted "$(sc_row)" 'a whole row'

echo 'the refusals (AC-D22.2, AC-D22.3)'
sc_a1="$(aid 9401)"
engine "$(sc_row "'$sc_a1'")" >/dev/null || true
sc_refusal "$(sc_row "'$sc_a1'");" pk_account_session_cutoff 'AC-D22.2 a second row of the same account'
sc_without() { # the column left null, in the order of the table
  local -A v=([account_id]='gen_random_uuid()' [tenant_id]='gen_random_uuid()' [revoked_from]='now()' [created_at]='now()' [updated_at]='now()')
  v[$1]='null'
  echo "insert into $sc_t (account_id, tenant_id, revoked_from, created_at, updated_at) values (${v[account_id]}, ${v[tenant_id]}, ${v[revoked_from]}, ${v[created_at]}, ${v[updated_at]})"
}
for column in account_id tenant_id revoked_from created_at updated_at; do
  sc_refusal "$(sc_without "$column");" "ERROR:  23502.*column \"$column\"" "AC-D22.3 a row without $column"
done

echo 'privileges (AC-D22.4)'
check 'AC-D22.4 the application user selects, inserts and updates; neither it nor the writer deletes' "$([ "$(privileges_of "$sc_t")" = 'INSERT,SELECT,UPDATE' ] && [ "$(sql "select has_table_privilege('$writer','$sc_t','DELETE')")" = f ]; echo $?)"
check 'AC-D22.4 the reader reads and does not write' "$([ "$(sql "select has_table_privilege('$reader','$sc_t','SELECT') and not has_table_privilege('$reader','$sc_t','INSERT')")" = t ]; echo $?)"
sc_refusal "delete from $sc_t;" 'permission denied for table account_session_cutoff' 'AC-D22.4 DELETE as the application user'

echo 'Idempotence, exact revert and reapply (AC-D22.5)'
sc_second="$(liquibase update 2>&1)"; printf '%s\n' "$sc_second"
check 'AC-D22.5 a second update applies zero changesets' "$(printf '%s\n' "$sc_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "delete from $sc_t" >/dev/null 2>&1 || true
sc_n="$(sql "select count(*) from $CONTROL where labels ilike '%account-session-cutoff%'" 2>/dev/null || echo 0)"
liquibase rollback-count "$sc_n"
sc_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$sc_base" "$sc_reverted"
check 'AC-D22.5 the revert restores the schema exactly and leaves the base changesets' "$([ -n "$sc_base" ] && [ "$sc_reverted" = "$sc_base" ] && [ "$(sql "select count(*) from $CONTROL")" = "$sc_n0" ]; echo $?)"
db_labels='account-session-cutoff'
liquibase update >/dev/null
check 'AC-D22.5 the changeset reapplies the one changeset of the slice' "$([ "$(sql "select count(*) from $CONTROL")" = "$((sc_n0 + 1))" ]; echo $?)"
