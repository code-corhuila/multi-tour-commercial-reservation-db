#!/usr/bin/env bash
# Sourced by db-ci.sh after decision-resume-checks.sh, on the same disposable PostgreSQL instance.
# HU-COM-020 -db (issue code-corhuila/multi-tour-docs#186), the accumulated freeze of a rescheduling episode (AC-18.13, AC-20.6): when the tenant is active again the clock of an episode
# resumes and the time it was frozen must not be lost, because episode_started_at is immutable. The db keeps the total of the frozen minutes in rescheduling_episode.frozen_total_minutes and the
# guard of the episode lets it only grow. Every changeset of the slice is labelled episode-frozen-total. Probes are written first: red before the changesets, green after (Annex J.1).
ef_t="$SCHEMA.rescheduling_episode"
ef_cust="$(aid 8401)"; ef_svc="$(aid 8403)"; ef_res="$(aid 8410)"; ef_res2="$(aid 8411)"; ef_e1="$(aid 8420)"; ef_e2="$(aid 8421)"
ef_sql() { sql "$1" 2>/dev/null || true; }
ef_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-020 db: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
ef_accepted() { # SQL, description
  local status=0
  engine "$1" >/dev/null || status=$?
  check "HU-COM-020 db: $2 is accepted" "$status"
}
ef_episode() { # episode id, reservation id (the first probe reservation by default)
  echo "insert into $ef_t (rescheduling_episode_id, tenant_id, reservation_id, original_salida_id, episode_started_at, proposal_due_at, episode_state, opened_at) values ('$1', '$tenant', '${2:-$ef_res}', gen_random_uuid(), now() - interval '5 hours', now() + interval '19 hours', 'OPEN', now() - interval '5 hours')"
}

echo 'HU-COM-020 db episode frozen total - base: every changeset that exists before the slice, with the probe rows'
liquibase rollback-count 999 >/dev/null
db_labels='!episode-frozen-total and !cancellation-penalty-policy'
liquibase update >/dev/null
ef_base="$(sql "select count(*) from $CONTROL")"; ef_snap="$(snapshot)"
sql "insert into $SCHEMA.customer (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status, terms_accepted, terms_accepted_at) values ('$ef_cust', '$tenant', 'Freeze total probe', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now());
     insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values ('$ef_svc', '$tenant', 'TOUR', 'Freeze total probe tour', 'ACTIVE', 150000, 90000, 12, false, false, now(), now())" >/dev/null 2>&1 || true
engine "$(rs_row reservation_id "'$ef_res'" customer_id "'$ef_cust'" service_id "'$ef_svc'");" >/dev/null || true
engine "$(rs_row reservation_id "'$ef_res2'" customer_id "'$ef_cust'" service_id "'$ef_svc'");" >/dev/null || true
check 'the probe reservation exists on the base' "$([ "$(ef_sql "select count(*) from $SCHEMA.reservation where reservation_id = '$ef_res'")" = 1 ]; echo $?)"

echo 'HU-COM-020 db episode frozen total - probes written first: red before the changesets, green after'
db_labels='episode-frozen-total'
liquibase update >/dev/null
check 'the changesets of the slice add two to the control table' "$([ "$(sql "select count(*) from $CONTROL")" = "$((ef_base + 2))" ]; echo $?)"

echo 'anEpisodeKeepsTheTotalOfItsFrozenMinutes (AC-18.13, AC-20.6)'
ef_accepted "$(ef_episode "$ef_e1")" 'an open episode with no total'
check 'the total of a new episode is empty and has no DEFAULT' "$([ "$(ef_sql "select count(*) from $ef_t where rescheduling_episode_id = '$ef_e1' and frozen_total_minutes is null")" = 1 ]; echo $?)"
ef_accepted "update $ef_t set frozen_at = now() - interval '1 hour', remaining_episode_minutes = 3000 where rescheduling_episode_id = '$ef_e1'" 'the freeze of the open episode'
ef_accepted "update $ef_t set frozen_at = NULL, remaining_episode_minutes = NULL, frozen_total_minutes = 60 where rescheduling_episode_id = '$ef_e1'" 'the resume that keeps the total frozen'
ef_accepted "update $ef_t set frozen_total_minutes = 90 where rescheduling_episode_id = '$ef_e1'" 'a total that grows'
ef_refusal "update $ef_t set frozen_total_minutes = 30 where rescheduling_episode_id = '$ef_e1';" trg_rescheduling_episode_guard 'a total that decreases'
ef_refusal "update $ef_t set frozen_total_minutes = NULL where rescheduling_episode_id = '$ef_e1';" trg_rescheduling_episode_guard 'a total that is erased'
ef_accepted "$(ef_episode "$ef_e2" "$ef_res2")" 'an open episode of another reservation'
ef_refusal "update $ef_t set frozen_total_minutes = -1 where rescheduling_episode_id = '$ef_e2';" chk_rescheduling_episode_frozen_total 'a negative total'
ef_accepted "update $ef_t set episode_state = 'CANCELLED', closed_at = now(), closed_reason = 'NO_ALTERNATIVE' where rescheduling_episode_id = '$ef_e2'" 'the closing of the second episode'
ef_refusal "update $ef_t set frozen_total_minutes = 10 where rescheduling_episode_id = '$ef_e2';" trg_rescheduling_episode_guard 'a total written on a closed episode'
ef_accepted "update $ef_t set frozen_total_minutes = 150 where rescheduling_episode_id = '$ef_e1'" 'the total of the first episode still grows after the other closed'

echo 'onlyThePlannedColumnAndTheGuardChangeSecondRunAppliesZeroAndRevertLeavesNoTrace (AC-D16.1)'
check 'nothing new appears in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasechangelog%'")" = 0 ]; echo $?)"
ef_second="$(liquibase update 2>&1)"; printf '%s\n' "$ef_second"
check 'a second update applies zero changesets' "$(printf '%s\n' "$ef_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "delete from $ef_t where reservation_id in ('$ef_res', '$ef_res2'); delete from $SCHEMA.reservation where reservation_id in ('$ef_res', '$ef_res2'); delete from $SCHEMA.catalog_service where service_id = '$ef_svc'; delete from $SCHEMA.customer where customer_id = '$ef_cust'" >/dev/null 2>&1 || true
ef_n="$(sql "select count(*) from $CONTROL where labels ilike '%episode-frozen-total%'" 2>/dev/null || echo 0)"
check 'the two changesets of the slice carry the label' "$([ "$ef_n" = 2 ]; echo $?)"
liquibase rollback-count "$ef_n" >/dev/null
ef_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$ef_snap" "$ef_reverted"
check 'the revert restores columns, constraints, indexes and privileges exactly and leaves the base changesets' "$([ -n "$ef_snap" ] && [ "$ef_reverted" = "$ef_snap" ] && [ "$(sql "select count(*) from $CONTROL")" = "$ef_base" ]; echo $?)"
db_labels='episode-frozen-total'
liquibase update >/dev/null
check 'the changesets of the slice reapply' "$([ "$(sql "select count(*) from $CONTROL")" = "$((ef_base + 2))" ]; echo $?)"
