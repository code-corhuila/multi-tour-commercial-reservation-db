#!/usr/bin/env bash
# Sourced by db-ci.sh after account-session-cutoff-checks.sh, on the same disposable PostgreSQL instance, with every changeset that exists before the slice (counted at run time); the slice is one changeset, 045.
# HU-COM-020 AC-20.13 and RN-12 -db (docs spec 020 DP-05, PROPOSED default): the envelope of outbox_event gains one nullable column, reason, that carries the marker RESTRICTED_ACCESS when the event was written by the
# restricted Administrator of an inactive tenant. It is allowed and not required, so every row already stored stays valid; it admits one value and nothing else, so no free text, address or amount can travel in it; no payload key
# is added. The probes run as the superuser with the foreign keys switched off (session_replication_role = replica); the CHECK constraints under test still apply. The changeset is labelled restricted-access-reason.
# Probes are written first: red before the changeset, green after (Annex J.1).
ra_ob="$SCHEMA.outbox_event"; ra_res="$(aid 9301)"
ra_event() { # the reason column and value (SQL literals), or nothing for a row without it
  local cols='' vals=''
  if [ $# -ge 2 ]; then cols=', reason'; vals=", $2"; fi
  echo "set session_replication_role = replica; insert into $ra_ob (tenant_id, event_type, reservation_id, actor_id, occurred_at, payload$cols) values ('$tenant', 'ReservationConfirmed', '$ra_res', '$actor', now(), '{\"reservationId\":\"x\",\"paymentStatus\":\"FULLY_PAID\"}'::jsonb$vals)"
}
ra_sql() { sql "$1" 2>/dev/null || true; }
ra_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" postgres 2>&1 || true)"; printf '%s\n' "$answer"
  check "AC-20.13 db: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
ra_accepted() { # SQL, description
  local status=0
  engine "begin; $1; rollback;" postgres >/dev/null || status=$?
  check "AC-20.13 db: $2 is accepted" "$status"
}
ra_key='chk_outbox_event_reason'

echo 'AC-20.13 db restricted access reason - base: every changeset that exists before the slice'
liquibase rollback-count 999 >/dev/null
db_labels='!restricted-access-reason and !rescheduling-proposed-notice and !fk-tenant-composite'
liquibase update >/dev/null
ra_base="$(snapshot)"
ra_n0="$(sql "select count(*) from $CONTROL")"
check "the base holds every changeset except the one of the slice ($ra_n0)" "$([ "$ra_n0" -gt 0 ] && [ "$(sql "select count(*) from $CONTROL where labels ilike '%restricted-access-reason%'")" = 0 ]; echo $?)"
ra_refusal "$(ra_event reason "'RESTRICTED_ACCESS'")" 'column "reason"' 'on that base, an event that carries the reason'

echo 'AC-20.13 db restricted access reason - probes written first: red before the changeset, green after'
db_labels='restricted-access-reason'
liquibase update >/dev/null
check 'the changeset of the slice adds one changeset (045) to the control table' "$([ "$(sql "select count(*) from $CONTROL")" = "$((ra_n0 + 1))" ]; echo $?)"

echo 'aRestrictedActionCarriesTheMarkerInTheEnvelope'
ra_accepted "$(ra_event reason "'RESTRICTED_ACCESS'")" 'an event with the reason RESTRICTED_ACCESS'
ra_accepted "$(ra_event reason 'NULL')" 'an event with a null reason'
ra_accepted "$(ra_event)" 'an event written without the reason (additive: stored rows stay valid)'

echo 'theReasonAdmitsOnlyTheMarker'
ra_refusal "$(ra_event reason "'restricted_access'")" "$ra_key" 'the marker in lower case'
ra_refusal "$(ra_event reason "''")" "$ra_key" 'an empty reason'
ra_refusal "$(ra_event reason "'customer asked for the money back'")" "$ra_key" 'a free text reason'
ra_refusal "$(ra_event reason "'RESTRICTED_ACCESS '")" "$ra_key" 'the marker with a trailing space'

echo 'onlyTheColumnChangesSecondRunAppliesZeroAndRevertLeavesNoTrace'
check 'nothing new appears in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasecha%'")" = 0 ]; echo $?)"
check 'the reason column is nullable text' "$([ "$(ra_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='outbox_event' and column_name='reason' and data_type='text' and is_nullable='YES'")" = 1 ]; echo $?)"
ra_second="$(liquibase update 2>&1)"; printf '%s\n' "$ra_second"
check 'a second update applies zero changesets' "$(printf '%s\n' "$ra_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
ra_n="$(sql "select count(*) from $CONTROL where labels ilike '%restricted-access-reason%'" 2>/dev/null || echo 0)"
liquibase rollback-count "$ra_n"
ra_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$ra_base" "$ra_reverted"
check 'the revert restores columns, constraints, indexes and privileges exactly and leaves the base changesets' "$([ -n "$ra_base" ] && [ "$ra_reverted" = "$ra_base" ] && [ "$(sql "select count(*) from $CONTROL")" = "$ra_n0" ]; echo $?)"
db_labels='restricted-access-reason'
liquibase update >/dev/null
check 'the changeset of the slice reapplies the one changeset of the slice' "$([ "$(sql "select count(*) from $CONTROL")" = "$((ra_n0 + 1))" ]; echo $?)"
