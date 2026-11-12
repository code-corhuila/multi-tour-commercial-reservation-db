#!/usr/bin/env bash
# Sourced by db-ci.sh after restricted-access-reason-checks.sh, on the same disposable PostgreSQL instance, with every changeset that exists before the slice (counted at run time); the slice is one changeset, 046.
# HU-COM-015 AC-15.5 -db (docs spec 015 DP-15-04 and DD-6 of spec 018, PROPOSED default): the guard chk_outbox_event_client_notified_codes (04_alter/027) admits one more trigger code, ReschedulingProposed, in its triggeringEventType list,
# so the notice of a rescheduling proposal (notificationType RESCHEDULING_PROPOSED, already admitted) can name the proposal as the fact that triggered it. Nothing else changes: no column, no payload key, no other event type, and every
# row already stored stays valid. The probes run as the superuser with the foreign keys switched off (session_replication_role = replica); the CHECK constraints under test still apply. The changeset is labelled rescheduling-proposed-notice.
# Probes are written first: red before the changeset, green after (Annex J.1).
rp_ob="$SCHEMA.outbox_event"; rp_res="$(aid 9401)"; rp_trigger="$(aid 9402)"
rp_event() { # notificationType and triggeringEventType (plain text), then optional extra members of the payload (JSON text starting with a comma)
  echo "set session_replication_role = replica; insert into $rp_ob (tenant_id, event_type, reservation_id, occurred_at, payload) values ('$tenant', 'ClientNotified', '$rp_res', now(), '{\"customerId\":\"$rp_res\",\"notificationType\":\"$1\",\"triggeringEventType\":\"$2\",\"triggeringEventId\":\"$rp_trigger\"${3:-}}'::jsonb)"
}
rp_sql() { sql "$1" 2>/dev/null || true; }
rp_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" postgres 2>&1 || true)"; printf '%s\n' "$answer"
  check "AC-15.5 db: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
rp_accepted() { # SQL, description
  local status=0
  engine "begin; $1; rollback;" postgres >/dev/null || status=$?
  check "AC-15.5 db: $2 is accepted" "$status"
}
rp_key='chk_outbox_event_client_notified_codes'

echo 'AC-15.5 db rescheduling proposed notice - base: every changeset that exists before the slice'
liquibase rollback-count 999 >/dev/null
db_labels='!rescheduling-proposed-notice'
liquibase update >/dev/null
rp_base="$(snapshot)"
rp_n0="$(sql "select count(*) from $CONTROL")"
check "the base holds every changeset except the one of the slice ($rp_n0)" "$([ "$rp_n0" -gt 0 ] && [ "$(sql "select count(*) from $CONTROL where labels ilike '%rescheduling-proposed-notice%'")" = 0 ]; echo $?)"
rp_refusal "$(rp_event RESCHEDULING_PROPOSED ReschedulingProposed)" "$rp_key" 'on that base, a proposal notice triggered by ReschedulingProposed'

echo 'AC-15.5 db rescheduling proposed notice - probes written first: red before the changeset, green after'
db_labels='rescheduling-proposed-notice'
liquibase update >/dev/null
check 'the changeset of the slice adds one changeset (046) to the control table' "$([ "$(sql "select count(*) from $CONTROL")" = "$((rp_n0 + 1))" ]; echo $?)"

echo 'aReschedulingProposalNoticeNamesTheProposalAsItsTrigger'
rp_accepted "$(rp_event RESCHEDULING_PROPOSED ReschedulingProposed)" 'a proposal notice triggered by ReschedulingProposed'
rp_accepted "$(rp_event PROOF_APPROVED PaymentValidated)" 'a proof approval notice (the older codes stay valid)'
rp_accepted "$(rp_event REFUND_PROCESSED RefundExecuted)" 'a refund notice (the older codes stay valid)'
rp_accepted "$(rp_event DEPARTURE_CANCELLED SalidaCancelled)" 'a cancelled departure notice (the older codes stay valid)'

echo 'theListStaysClosed'
rp_refusal "$(rp_event RESCHEDULING_PROPOSED reschedulingproposed)" "$rp_key" 'the trigger code in lower case'
rp_refusal "$(rp_event RESCHEDULING_PROPOSED ReschedulingProposal)" "$rp_key" 'a trigger code that only looks like it'
rp_refusal "$(rp_event RESCHEDULING_PROPOSED 'ReschedulingProposed ')" "$rp_key" 'the trigger code with a trailing space'
rp_refusal "$(rp_event RESCHEDULING_PROPOSAL ReschedulingProposed)" "$rp_key" 'a notification code that is not one of the eight'
rp_refusal "$(rp_event RESCHEDULING_PROPOSED ReschedulingProposed ',"amountCents":1000')" 'chk_outbox_event_payload_keys_client_notified' 'a proposal notice that carries an amount'
rp_refusal "$(rp_event RESCHEDULING_PROPOSED ReschedulingProposed ',"email":"a@b.c"')" 'violates check constraint' 'a proposal notice that carries an address'

echo 'onlyTheListChangesSecondRunAppliesZeroAndRevertLeavesNoTrace'
check 'nothing new appears in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasecha%'")" = 0 ]; echo $?)"
check 'the guard keeps its name' "$([ "$(rp_sql "select count(*) from pg_constraint where conrelid='$rp_ob'::regclass and conname='$rp_key'")" = 1 ]; echo $?)"
rp_second="$(liquibase update 2>&1)"; printf '%s\n' "$rp_second"
check 'a second update applies zero changesets' "$(printf '%s\n' "$rp_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
rp_n="$(sql "select count(*) from $CONTROL where labels ilike '%rescheduling-proposed-notice%'" 2>/dev/null || echo 0)"
liquibase rollback-count "$rp_n"
rp_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$rp_base" "$rp_reverted"
check 'the revert restores columns, constraints, indexes and privileges exactly and leaves the base changesets' "$([ -n "$rp_base" ] && [ "$rp_reverted" = "$rp_base" ] && [ "$(sql "select count(*) from $CONTROL")" = "$rp_n0" ]; echo $?)"
db_labels='rescheduling-proposed-notice'
liquibase update >/dev/null
check 'the changeset of the slice reapplies the one changeset of the slice' "$([ "$(sql "select count(*) from $CONTROL")" = "$((rp_n0 + 1))" ]; echo $?)"
