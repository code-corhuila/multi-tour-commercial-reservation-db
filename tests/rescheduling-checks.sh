#!/usr/bin/env bash
# Sourced by db-ci.sh after sensitive-data-deletion-checks.sh, on the same disposable PostgreSQL instance, with the 153 changesets that exist before the story.
# HU-COM-018 -db (issue code-corhuila/multi-tour-docs#184), plan D-02, D-03 and D-05, slice 1: the rescheduling_episode and rescheduling_proposal tables, the two partial unique
# keys (one open episode per reservation, one pending proposal per episode) and the two guards that let a row move forward only. Every changeset of the slice is labelled
# HU-COM-018. Probes are written first: red before the changesets, green after (Annex J.1). The rows of the probes are removed by the owner at the end.
re_ep="$SCHEMA.rescheduling_episode"; re_pr="$SCHEMA.rescheduling_proposal"
re_cust="$(aid 8001)"; re_svc="$(aid 8003)"; re_res1="$(aid 8010)"; re_res2="$(aid 8011)"; re_res3="$(aid 8012)"
re_e1="$(aid 8020)"; re_e2="$(aid 8021)"; re_e3="$(aid 8022)"; re_p1="$(aid 8030)"; re_p2="$(aid 8031)"; re_p3="$(aid 8032)"
re_sal1="$(aid 8040)"; re_sal2="$(aid 8041)"
re_sql() { sql "$1" 2>/dev/null || true; }
re_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-018 db: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
re_accepted() { # SQL, description
  local status=0
  engine "$1" >/dev/null || status=$?
  check "HU-COM-018 db: $2 is accepted" "$status"
}
re_owner() { docker exec -e PGPASSWORD "$container" psql -U postgres -d postgres -c "$1" 2>&1 || true; }
re_episode() { # column/value pairs (SQL literals) that replace the defaults of a valid open episode of the first reservation
  local -A v=([rescheduling_episode_id]="gen_random_uuid()" [tenant_id]="'$tenant'" [reservation_id]="'$re_res1'" [original_salida_id]="gen_random_uuid()"
    [episode_started_at]="now() - interval '1 hour'" [proposal_due_at]="now() + interval '23 hours'" [episode_state]="'OPEN'" [closed_at]="NULL" [closed_reason]="NULL"
    [frozen_at]="NULL" [remaining_episode_minutes]="NULL" [opened_at]="now()")
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $re_ep (rescheduling_episode_id, tenant_id, reservation_id, original_salida_id, episode_started_at, proposal_due_at, episode_state, closed_at, closed_reason, frozen_at, remaining_episode_minutes, opened_at) values (${v[rescheduling_episode_id]}, ${v[tenant_id]}, ${v[reservation_id]}, ${v[original_salida_id]}, ${v[episode_started_at]}, ${v[proposal_due_at]}, ${v[episode_state]}, ${v[closed_at]}, ${v[closed_reason]}, ${v[frozen_at]}, ${v[remaining_episode_minutes]}, ${v[opened_at]})"
}
re_proposal() { # column/value pairs (SQL literals) that replace the defaults of a valid pending proposal of the first episode
  local -A v=([rescheduling_proposal_id]="gen_random_uuid()" [tenant_id]="'$tenant'" [rescheduling_episode_id]="'$re_e1'" [reservation_id]="'$re_res1'"
    [proposed_salida_id]="gen_random_uuid()" [party_size]=2 [proposed_by]="'$actor'" [proposed_at]="now()" [response_deadline_at]="now() + interval '3 days'"
    [proposal_state]="'PENDING'" [remaining_response_minutes]="NULL" [answer_source]="NULL" [answer_channel]="NULL" [answer_evidence]="NULL" [answered_at]="NULL"
    [answer_recorded_by]="NULL" [answer_recorded_at]="NULL" [closed_at]="NULL")
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $re_pr (rescheduling_proposal_id, tenant_id, rescheduling_episode_id, reservation_id, proposed_salida_id, party_size, proposed_by, proposed_at, response_deadline_at, proposal_state, remaining_response_minutes, answer_source, answer_channel, answer_evidence, answered_at, answer_recorded_by, answer_recorded_at, closed_at) values (${v[rescheduling_proposal_id]}, ${v[tenant_id]}, ${v[rescheduling_episode_id]}, ${v[reservation_id]}, ${v[proposed_salida_id]}, ${v[party_size]}, ${v[proposed_by]}, ${v[proposed_at]}, ${v[response_deadline_at]}, ${v[proposal_state]}, ${v[remaining_response_minutes]}, ${v[answer_source]}, ${v[answer_channel]}, ${v[answer_evidence]}, ${v[answered_at]}, ${v[answer_recorded_by]}, ${v[answer_recorded_at]}, ${v[closed_at]})"
}
re_answer() { # the columns an answer writes together with the state: state, source, channel, evidence
  echo "proposal_state = '$1', answer_source = '$2', answer_channel = $3, answer_evidence = $4, answered_at = now(), answer_recorded_by = '$actor', answer_recorded_at = now(), closed_at = now()"
}

echo 'HU-COM-018 db - base: the 153 changesets that exist before the story, with the probe rows'
liquibase rollback-count 999 >/dev/null
db_labels='!HU-COM-018 and !HU-COM-020 and !decision-resume'
liquibase update >/dev/null
re_base="$(snapshot)"
re_base_objects="$(sql "select (select count(*) from pg_tables where schemaname='$SCHEMA') || '|' || (select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace) || '|' || (select count(*) from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace='$SCHEMA'::regnamespace))" 2>/dev/null || true)"
check 'base holds exactly 153 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 153 ]; echo $?)"
sql "insert into $SCHEMA.customer (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status, terms_accepted, terms_accepted_at) values ('$re_cust', '$tenant', 'Rescheduling probe', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now());
     insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values ('$re_svc', '$tenant', 'TOUR', 'Rescheduling probe tour', 'ACTIVE', 150000, 90000, 12, false, false, now(), now())" >/dev/null 2>&1 || true
engine "$(rs_row reservation_id "'$re_res1'" customer_id "'$re_cust'" service_id "'$re_svc'"); $(rs_row reservation_id "'$re_res2'" customer_id "'$re_cust'" service_id "'$re_svc'"); $(rs_row reservation_id "'$re_res3'" customer_id "'$re_cust'" service_id "'$re_svc'");" >/dev/null || true
check 'the three probe reservations exist on the base' "$([ "$(re_sql "select count(*) from $SCHEMA.reservation where reservation_id in ('$re_res1','$re_res2','$re_res3')")" = 3 ]; echo $?)"

echo 'HU-COM-018 db - probes written first: red before the changesets, green after'
db_labels='HU-COM-018 and !rescheduling-record'
liquibase update >/dev/null
check 'the changesets of the story bring the control table to 161' "$([ "$(sql "select count(*) from $CONTROL")" = 161 ]; echo $?)"

echo 'anEpisodeRequiresEveryFieldAndItsClosingMatchesItsOutcome (AC-D18.2, AC-D18.3)'
re_accepted "$(re_episode rescheduling_episode_id "'$re_e1'")" 'a whole open episode'
for column in rescheduling_episode_id tenant_id reservation_id original_salida_id episode_started_at proposal_due_at episode_state opened_at; do
  re_refusal "$(re_episode reservation_id "'$re_res2'" "$column" NULL);" "null value in column \"$column\".*not-null constraint" "an episode without $column"
done
re_refusal "$(re_episode reservation_id "'$re_res2'" episode_state "'PAUSED'");" chk_rescheduling_episode_state 'a state outside the three codes'
re_refusal "$(re_episode reservation_id "'$re_res2'" closed_at "now()");" chk_rescheduling_episode_closing 'an open episode with a closing instant'
re_refusal "$(re_episode reservation_id "'$re_res2'" closed_reason "'NO_ALTERNATIVE'");" chk_rescheduling_episode_closing 'an open episode with a reason'
re_refusal "$(re_episode reservation_id "'$re_res2'" episode_state "'CANCELLED'" closed_reason "'NO_ALTERNATIVE'");" chk_rescheduling_episode_closing 'a cancelled episode without a closing instant'
re_refusal "$(re_episode reservation_id "'$re_res2'" episode_state "'CANCELLED'" closed_at "now()");" chk_rescheduling_episode_closing 'a cancelled episode without a reason'
re_refusal "$(re_episode reservation_id "'$re_res2'" episode_state "'RESCHEDULED'" closed_at "now()" closed_reason "'NO_ALTERNATIVE'");" chk_rescheduling_episode_closing 'a rescheduled episode with another reason than ACCEPTED'
re_refusal "$(re_episode reservation_id "'$re_res2'" episode_state "'CANCELLED'" closed_at "now()" closed_reason "'ACCEPTED'");" chk_rescheduling_episode_closing 'a cancelled episode with the reason ACCEPTED'
re_refusal "$(re_episode reservation_id "'$re_res2'" episode_state "'CANCELLED'" closed_at "now()" closed_reason "'BORED'");" chk_rescheduling_episode_reason 'a reason outside the seven codes'
re_refusal "$(re_episode reservation_id "'$(aid 8099)'");" fk_rescheduling_episode_reservation 'an episode for a reservation that does not exist'
re_accepted "$(re_episode reservation_id "'$re_res2'" episode_state "'RESCHEDULED'" closed_at "now()" closed_reason "'ACCEPTED'")" 'a rescheduled episode closed with ACCEPTED'
for reason in REJECTED_BY_CUSTOMER NO_ALTERNATIVE PROPOSAL_PERIOD_EXPIRED RESPONSE_DEADLINE_EXPIRED EPISODE_LIMIT_REACHED PROPOSED_DEPARTURE_CANCELLED_WHILE_INACTIVE; do
  re_accepted "$(re_episode reservation_id "'$re_res3'" episode_state "'CANCELLED'" closed_at "now()" closed_reason "'$reason'")" "a cancelled episode closed with $reason"
done
check 'no column of the episode table has a DEFAULT' "$([ "$(re_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='rescheduling_episode' and column_default is not null")" = 0 ]; echo $?)"

echo 'aFreezeNeedsBothColumnsAndNoNegativeMinutes (AC-D18.4)'
re_refusal "$(re_episode reservation_id "'$re_res2'" episode_state "'CANCELLED'" closed_at "now()" closed_reason "'NO_ALTERNATIVE'" frozen_at "now()");" chk_rescheduling_episode_freeze 'a freeze instant without remaining minutes'
re_refusal "$(re_episode reservation_id "'$re_res2'" episode_state "'CANCELLED'" closed_at "now()" closed_reason "'NO_ALTERNATIVE'" remaining_episode_minutes 60);" chk_rescheduling_episode_freeze 'remaining minutes without a freeze instant'
re_refusal "$(re_episode reservation_id "'$re_res2'" episode_state "'CANCELLED'" closed_at "now()" closed_reason "'NO_ALTERNATIVE'" frozen_at "now()" remaining_episode_minutes -1);" chk_rescheduling_episode_freeze 'negative remaining minutes'

echo 'oneOpenEpisodePerReservationAndOnePerDeparture (AC-D18.5)'
re_refusal "$(re_episode);" uq_rescheduling_episode_open_reservation 'a second open episode for the same reservation'
re_accepted "$(re_episode rescheduling_episode_id "'$re_e2'" reservation_id "'$re_res3'" original_salida_id "'$re_sal1'")" 'an open episode for another reservation'
re_refusal "$(re_episode rescheduling_episode_id "'$re_e3'" reservation_id "'$re_res3'" original_salida_id "'$re_sal1'" episode_state "'CANCELLED'" closed_at "now()" closed_reason "'NO_ALTERNATIVE'");" uq_rescheduling_episode_reservation_departure 'a second episode for the same reservation and departure'

echo 'aProposalRequiresEveryFieldAndAClosedState (AC-D18.6)'
re_accepted "$(re_proposal rescheduling_proposal_id "'$re_p1'")" 'a whole pending proposal'
for column in rescheduling_proposal_id tenant_id rescheduling_episode_id reservation_id proposed_salida_id party_size proposed_by proposed_at response_deadline_at proposal_state; do
  re_refusal "$(re_proposal rescheduling_episode_id "'$re_e2'" reservation_id "'$re_res3'" "$column" NULL);" "null value in column \"$column\".*not-null constraint" "a proposal without $column"
done
re_refusal "$(re_proposal rescheduling_episode_id "'$re_e2'" reservation_id "'$re_res3'" proposal_state "'MAYBE'");" chk_rescheduling_proposal_state 'a state outside the five codes'
re_refusal "$(re_proposal rescheduling_episode_id "'$re_e2'" reservation_id "'$re_res3'" party_size 0);" chk_rescheduling_proposal_party_size 'a party size of zero'
re_refusal "$(re_proposal rescheduling_episode_id "'$(aid 8098)'" reservation_id "'$re_res3'");" fk_rescheduling_proposal_episode 'a proposal of an episode that does not exist'
re_refusal "$(re_proposal rescheduling_episode_id "'$re_e2'" reservation_id "'$(aid 8097)'");" fk_rescheduling_proposal_reservation 'a proposal for a reservation that does not exist'
check 'no column of the proposal table has a DEFAULT' "$([ "$(re_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='rescheduling_proposal' and column_default is not null")" = 0 ]; echo $?)"

echo 'anAnswerNeedsItsSourceChannelAndEvidenceAsTheSourceSays (AC-D18.7)'
re_ans() { # state, source, channel, evidence, then pairs: a proposal of the second episode already holding its answer
  local st="$1" so="$2" ch="$3" ev="$4"; shift 4
  re_proposal rescheduling_episode_id "'$re_e2'" reservation_id "'$re_res3'" proposal_state "'$st'" answer_source "$so" answer_channel "$ch" answer_evidence "$ev" answered_at "now()" answer_recorded_by "'$actor'" answer_recorded_at "now()" closed_at "now()" "$@"
}
re_accepted "$(re_ans ACCEPTED "'CUSTOMER'" NULL NULL)" 'an acceptance by the customer without channel or evidence'
re_accepted "$(re_ans REJECTED "'OUTSIDE_CHANNEL'" "'PHONE'" "'Called the agency at noon'")" 'a rejection by an outside channel with its evidence'
re_refusal "$(re_ans ACCEPTED "'OUTSIDE_CHANNEL'" NULL "'Called'");" chk_rescheduling_proposal_source 'an outside answer without channel'
re_refusal "$(re_ans ACCEPTED "'OUTSIDE_CHANNEL'" "'PHONE'" NULL);" chk_rescheduling_proposal_source 'an outside answer without evidence'
re_refusal "$(re_ans ACCEPTED "'OUTSIDE_CHANNEL'" "'PHONE'" "'   '");" chk_rescheduling_proposal_source 'an outside answer with a blank evidence'
re_refusal "$(re_ans ACCEPTED "'OUTSIDE_CHANNEL'" "'PIGEON'" "'Called'");" chk_rescheduling_proposal_source 'an outside answer through a channel outside the four'
re_refusal "$(re_ans ACCEPTED "'CUSTOMER'" "'EMAIL'" NULL);" chk_rescheduling_proposal_source 'a customer answer with a channel'
re_refusal "$(re_ans ACCEPTED "'CUSTOMER'" NULL "'Called'");" chk_rescheduling_proposal_source 'a customer answer with evidence'
re_refusal "$(re_ans ACCEPTED "'ROBOT'" NULL NULL);" chk_rescheduling_proposal_source 'an answer from a source outside the two'
re_refusal "$(re_proposal rescheduling_episode_id "'$re_e2'" reservation_id "'$re_res3'" answer_source "'CUSTOMER'");" chk_rescheduling_proposal_answer 'a pending proposal that carries an answer'
re_refusal "$(re_proposal rescheduling_episode_id "'$re_e2'" reservation_id "'$re_res3'" proposal_state "'ACCEPTED'" answer_source "'CUSTOMER'" answered_at "now()");" chk_rescheduling_proposal_answer 'an accepted proposal without recorder'
re_accepted "$(re_proposal rescheduling_episode_id "'$re_e2'" reservation_id "'$re_res3'" proposal_state "'VOID'" closed_at "now()")" 'a void proposal with a closing instant and no answer'
re_refusal "$(re_proposal rescheduling_episode_id "'$re_e2'" reservation_id "'$re_res3'" proposal_state "'VOID'");" chk_rescheduling_proposal_answer 'a void proposal without a closing instant'
re_accepted "$(re_proposal rescheduling_episode_id "'$re_e2'" reservation_id "'$re_res3'" proposal_state "'EXPIRED'" closed_at "now()")" 'an expired proposal with a closing instant and no answer'
re_refusal "$(re_proposal rescheduling_episode_id "'$re_e2'" reservation_id "'$re_res3'" remaining_response_minutes -1);" chk_rescheduling_proposal_remaining 'a pending proposal with negative remaining minutes'
re_refusal "$(re_proposal rescheduling_episode_id "'$re_e2'" reservation_id "'$re_res3'" proposal_state "'VOID'" closed_at "now()" remaining_response_minutes 5);" chk_rescheduling_proposal_remaining 'remaining minutes on a closed proposal'

echo 'onlyOneProposalIsPendingPerEpisode (AC-D18.8)'
re_refusal "$(re_proposal);" uq_rescheduling_proposal_pending_episode 'a second pending proposal for the same episode'
re_accepted "$(re_proposal rescheduling_episode_id "'$re_e2'" reservation_id "'$re_res3'" rescheduling_proposal_id "'$re_p2'")" 'a pending proposal for another episode'

echo 'onlyTheForwardMovesAreAcceptedAndAClosedRowNeverChanges (AC-D18.9)'
re_accepted "update $re_pr set remaining_response_minutes = 600 where rescheduling_proposal_id = '$re_p1'" 'a freeze of the pending proposal that keeps its state'
re_accepted "update $re_pr set remaining_response_minutes = NULL where rescheduling_proposal_id = '$re_p1'" 'the resume of the pending proposal'
re_accepted "update $re_pr set response_deadline_at = now() + interval '5 days' where rescheduling_proposal_id = '$re_p1'" 'the new response deadline after a resume'
re_refusal "update $re_pr set answer_source = 'CUSTOMER' where rescheduling_proposal_id = '$re_p1';" trg_rescheduling_proposal_guard 'an answer written without its state'
re_refusal "update $re_pr set proposed_salida_id = gen_random_uuid() where rescheduling_proposal_id = '$re_p1';" trg_rescheduling_proposal_guard 'a change of the proposed departure'
re_refusal "update $re_pr set proposal_state = 'PENDING', closed_at = now() where rescheduling_proposal_id = '$re_p1';" trg_rescheduling_proposal_guard 'a closing instant written without the state'
re_accepted "update $re_pr set $(re_answer ACCEPTED CUSTOMER NULL NULL) where rescheduling_proposal_id = '$re_p1'" 'the answer of a pending proposal'
re_refusal "update $re_pr set $(re_answer REJECTED CUSTOMER NULL NULL) where rescheduling_proposal_id = '$re_p1';" trg_rescheduling_proposal_guard 'a second answer to the same proposal'
re_refusal "update $re_pr set remaining_response_minutes = 5 where rescheduling_proposal_id = '$re_p1';" trg_rescheduling_proposal_guard 'any change of a closed proposal'
re_accepted "update $re_pr set proposal_state = 'VOID', closed_at = now() where rescheduling_proposal_id = '$re_p2'" 'a pending proposal voided'
re_refusal "update $re_pr set proposal_state = 'PENDING', closed_at = NULL where rescheduling_proposal_id = '$re_p2';" trg_rescheduling_proposal_guard 'a voided proposal brought back to pending'
re_accepted "update $re_ep set frozen_at = now(), remaining_episode_minutes = 300 where rescheduling_episode_id = '$re_e1'" 'the freeze of an open episode'
re_accepted "update $re_ep set frozen_at = NULL, remaining_episode_minutes = NULL where rescheduling_episode_id = '$re_e1'" 'the resume of an open episode'
re_refusal "update $re_ep set original_salida_id = gen_random_uuid() where rescheduling_episode_id = '$re_e1';" trg_rescheduling_episode_guard 'a change of the original departure'
re_refusal "update $re_ep set episode_state = 'OPEN', closed_reason = 'NO_ALTERNATIVE' where rescheduling_episode_id = '$re_e1';" trg_rescheduling_episode_guard 'a reason written without leaving the open state'
re_accepted "update $re_ep set episode_state = 'RESCHEDULED', closed_at = now(), closed_reason = 'ACCEPTED' where rescheduling_episode_id = '$re_e1'" 'the closing of an open episode'
re_refusal "update $re_ep set episode_state = 'CANCELLED', closed_reason = 'NO_ALTERNATIVE' where rescheduling_episode_id = '$re_e1';" trg_rescheduling_episode_guard 'a second closing of the same episode'
re_refusal "update $re_ep set episode_state = 'OPEN', closed_at = NULL, closed_reason = NULL where rescheduling_episode_id = '$re_e1';" trg_rescheduling_episode_guard 'a closed episode reopened'

echo 'nothingIsDeletedAndAReservationWithAnEpisodeCannotBe (AC-D18.13)'
re_refusal "delete from $re_pr where rescheduling_proposal_id = '$re_p1';" 'permission denied for table rescheduling_proposal' 'a delete of a proposal'
re_refusal "delete from $re_ep where rescheduling_episode_id = '$re_e1';" 'permission denied for table rescheduling_episode' 'a delete of an episode'
check 'AC-D18.13 even the owner cannot delete a reservation that has an episode' "$(re_owner "delete from $SCHEMA.reservation where reservation_id = '$re_res1'" | grep -q 'fk_rescheduling_episode_reservation'; echo $?)"
check 'AC-D18.13 even the owner cannot delete an episode that has a proposal' "$(re_owner "delete from $re_ep where rescheduling_episode_id = '$re_e1'" | grep -q 'fk_rescheduling_proposal_episode'; echo $?)"

echo 'onlyThePlannedObjectsAreAddedAndRevertLeavesNoTrace, slice 1 (AC-D18.1, AC-D18.17)'
re_objects="$(sql "select (select count(*) from pg_tables where schemaname='$SCHEMA') || '|' || (select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace) || '|' || (select count(*) from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace='$SCHEMA'::regnamespace))" 2>/dev/null || true)"
IFS='|' read -r re_bt re_bf re_bg <<< "$re_base_objects"
check 'AC-D18.1 exactly the two planned tables, two functions and two triggers were added to the base' "$([ -n "$re_base_objects" ] && [ "$re_objects" = "$((re_bt + 2))|$((re_bf + 2))|$((re_bg + 2))" ]; echo $?)"
check 'AC-D18.1 the two partial unique keys exist' "$([ "$(re_sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and indexname in ('uq_rescheduling_episode_open_reservation','uq_rescheduling_proposal_pending_episode')")" = 2 ]; echo $?)"
check 'AC-D18.1 nothing new appears in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasechangelog%'")" = 0 ]; echo $?)"
re_second="$(liquibase update 2>&1)"; printf '%s\n' "$re_second"
check 'AC-D18.17 a second update applies zero changesets' "$(printf '%s\n' "$re_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "delete from $re_pr; delete from $re_ep; delete from $SCHEMA.reservation where reservation_id in ('$re_res1','$re_res2','$re_res3'); delete from $SCHEMA.catalog_service where service_id = '$re_svc'; delete from $SCHEMA.customer where customer_id = '$re_cust'" >/dev/null 2>&1 || true
check 'the rows of the probes are gone before the revert' "$([ "$(sql "select (select count(*) from $re_pr) + (select count(*) from $re_ep) + (select count(*) from $SCHEMA.reservation where reservation_id in ('$re_res1','$re_res2','$re_res3'))")" = 0 ]; echo $?)"
re_n="$(sql "select count(*) from $CONTROL where labels ilike '%HU-COM-018%'" 2>/dev/null || echo 0)"
liquibase rollback-count "$re_n"
re_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$re_base" "$re_reverted"
check 'AC-D18.17 the revert restores columns, constraints, indexes and privileges exactly and leaves 153 changesets' "$([ -n "$re_base" ] && [ "$re_reverted" = "$re_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 153 ]; echo $?)"
db_labels='HU-COM-018 and !rescheduling-record'
liquibase update >/dev/null
check 'the changesets of the story reapply to 161' "$([ "$(sql "select count(*) from $CONTROL")" = 161 ]; echo $?)"
