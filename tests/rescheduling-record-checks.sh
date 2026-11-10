#!/usr/bin/env bash
# Sourced by db-ci.sh after rescheduling-checks.sh, on the same disposable PostgreSQL instance, with the 161 changesets that exist before this slice.
# HU-COM-018 -db (issue code-corhuila/multi-tour-docs#184), plan D-04, D-06, D-07 and D-08, slice 2: the append-only rescheduling_record table, the hold kind of the allocation with its
# unique key, the four read indexes and the outbox shape of ReservationRescheduled. Every changeset of the slice is labelled HU-COM-018 and rescheduling-record. Probes are written first:
# red before the changesets, green after (Annex J.1). The rows of the probes are removed by the owner at the end.
rb_rec="$SCHEMA.rescheduling_record"; rb_ep="$SCHEMA.rescheduling_episode"; rb_pr="$SCHEMA.rescheduling_proposal"; rb_al="$SCHEMA.capacity_allocation"; rb_ob="$SCHEMA.outbox_event"
rb_cust="$(aid 8101)"; rb_svc="$(aid 8103)"; rb_res1="$(aid 8110)"; rb_res2="$(aid 8111)"; rb_res3="$(aid 8112)"
rb_e1="$(aid 8120)"; rb_e2="$(aid 8121)"; rb_r1="$(aid 8130)"; rb_r2="$(aid 8131)"; rb_sal="$(aid 8140)"; rb_sal2="$(aid 8141)"
rb_sql() { sql "$1" 2>/dev/null || true; }
rb_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-018 db: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
rb_accepted() { # SQL, description
  local status=0
  engine "$1" >/dev/null || status=$?
  check "HU-COM-018 db: $2 is accepted" "$status"
}
rb_explain() { printf '%s\n' 'set enable_seqscan = off;' "explain $1;" | docker exec -i -e PGPASSWORD "$container" psql -X -U postgres -d postgres 2>&1 || true; }
rb_record() { # column/value pairs (SQL literals) that replace the defaults of a valid record of the first episode
  local -A v=([rescheduling_record_id]="gen_random_uuid()" [tenant_id]="'$tenant'" [rescheduling_episode_id]="'$rb_e1'" [original_reservation_id]="'$rb_res1'"
    [linked_reservation_id]="NULL" [agreed_salida_id]="gen_random_uuid()" [agreed_start_at]="now() + interval '30 days'" [approved_by]="'$actor'" [recorded_at]="now()")
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $rb_rec (rescheduling_record_id, tenant_id, rescheduling_episode_id, original_reservation_id, linked_reservation_id, agreed_salida_id, agreed_start_at, approved_by, recorded_at) values (${v[rescheduling_record_id]}, ${v[tenant_id]}, ${v[rescheduling_episode_id]}, ${v[original_reservation_id]}, ${v[linked_reservation_id]}, ${v[agreed_salida_id]}, ${v[agreed_start_at]}, ${v[approved_by]}, ${v[recorded_at]})"
}
rb_alloc() { # reservation, kind, then released_at literal
  echo "insert into $rb_al (capacity_allocation_id, tenant_id, salida_id, reservation_id, party_size, allocation_kind, allocated_at, released_at) values (gen_random_uuid(), '$tenant', '${4:-$rb_sal}', '$1', 2, '$2', now(), $3)"
}
rb_event() { # payload (SQL literal), then column/value pairs that replace the defaults
  local payload="$1"; shift
  local -A v=([reservation_id]="'$rb_res1'" [event_type]="'ReservationRescheduled'" [actor_id]="'$actor'")
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $rb_ob (tenant_id, event_type, reservation_id, actor_id, occurred_at, payload) values ('$tenant', ${v[event_type]}, ${v[reservation_id]}, ${v[actor_id]}, now(), $payload)"
}

echo 'HU-COM-018 db slice 2 - base: the 161 changesets that exist before the slice, with the probe rows'
liquibase rollback-count 999 >/dev/null
db_labels='!rescheduling-record and !HU-COM-020 and !decision-resume'
liquibase update >/dev/null
rb_base="$(snapshot)"
rb_base_objects="$(sql "select (select count(*) from pg_tables where schemaname='$SCHEMA') || '|' || (select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace) || '|' || (select count(*) from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace='$SCHEMA'::regnamespace))" 2>/dev/null || true)"
check 'base holds exactly 179 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 161 ]; echo $?)"
sql "insert into $SCHEMA.customer (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status, terms_accepted, terms_accepted_at) values ('$rb_cust', '$tenant', 'Record probe', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now());
     insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values ('$rb_svc', '$tenant', 'TOUR', 'Record probe tour', 'ACTIVE', 150000, 90000, 12, false, false, now(), now())" >/dev/null 2>&1 || true
engine "$(rs_row reservation_id "'$rb_res1'" customer_id "'$rb_cust'" service_id "'$rb_svc'"); $(rs_row reservation_id "'$rb_res2'" customer_id "'$rb_cust'" service_id "'$rb_svc'"); $(rs_row reservation_id "'$rb_res3'" customer_id "'$rb_cust'" service_id "'$rb_svc'");" >/dev/null || true
sql "insert into $rb_ep (rescheduling_episode_id, tenant_id, reservation_id, original_salida_id, episode_started_at, proposal_due_at, episode_state, opened_at) values ('$rb_e1', '$tenant', '$rb_res1', gen_random_uuid(), now(), now() + interval '1 day', 'OPEN', now()), ('$rb_e2', '$tenant', '$rb_res2', gen_random_uuid(), now(), now() + interval '1 day', 'OPEN', now())" >/dev/null 2>&1 || true
check 'the probe reservations and episodes exist on the base' "$([ "$(rb_sql "select (select count(*) from $SCHEMA.reservation where reservation_id in ('$rb_res1','$rb_res2','$rb_res3')) || '|' || (select count(*) from $rb_ep where rescheduling_episode_id in ('$rb_e1','$rb_e2'))")" = '3|2' ]; echo $?)"

echo 'HU-COM-018 db slice 2 - probes written first: red before the changesets, green after'
db_labels='rescheduling-record'
liquibase update >/dev/null
check 'the changesets of the slice bring the control table to 170' "$([ "$(sql "select count(*) from $CONTROL")" = 170 ]; echo $?)"

echo 'aRecordRequiresEveryFieldAndOnePerEpisode (AC-D18.10)'
rb_accepted "$(rb_record rescheduling_record_id "'$rb_r1'")" 'a whole record'
for column in rescheduling_record_id tenant_id rescheduling_episode_id original_reservation_id agreed_salida_id agreed_start_at approved_by recorded_at; do
  rb_refusal "$(rb_record rescheduling_episode_id "'$rb_e2'" "$column" NULL);" "null value in column \"$column\".*not-null constraint" "a record without $column"
done
rb_refusal "$(rb_record rescheduling_episode_id "'$rb_e2'" linked_reservation_id "'$rb_res1'" original_reservation_id "'$rb_res1'");" chk_rescheduling_record_linked 'a record whose linked reservation equals the original'
rb_refusal "$(rb_record);" uq_rescheduling_record_episode 'a second record for the same episode'
rb_refusal "$(rb_record rescheduling_episode_id "'$(aid 8199)'");" fk_rescheduling_record_episode 'a record of an episode that does not exist'
rb_refusal "$(rb_record rescheduling_episode_id "'$rb_e2'" original_reservation_id "'$(aid 8198)'");" fk_rescheduling_record_original 'a record of a reservation that does not exist'
rb_accepted "$(rb_record rescheduling_record_id "'$rb_r2'" rescheduling_episode_id "'$rb_e2'" original_reservation_id "'$rb_res2'" linked_reservation_id "'$rb_res3'")" 'a record with another linked reservation'
check 'no column of the record table has a DEFAULT' "$([ "$(rb_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='rescheduling_record' and column_default is not null")" = 0 ]; echo $?)"

echo 'aRecordCannotBeUpdatedOrDeleted (AC-D18.11)'
rb_refusal "update $rb_rec set approved_by = gen_random_uuid() where rescheduling_record_id = '$rb_r1';" 'permission denied for table rescheduling_record' 'an update of a record'
rb_refusal "delete from $rb_rec where rescheduling_record_id = '$rb_r1';" 'permission denied for table rescheduling_record' 'a delete of a record'

echo 'aHoldAndASeatCoexistAndASecondHoldIsRefused (AC-D18.12)'
rb_accepted "$(rb_alloc "$rb_res1" RESERVATION NULL)" 'an active seat'
rb_accepted "$(rb_alloc "$rb_res1" REPROGRAMMING_HOLD NULL "$rb_sal2")" 'an active hold beside the seat of the same reservation'
rb_refusal "$(rb_alloc "$rb_res1" REPROGRAMMING_HOLD NULL "$rb_sal2");" uq_capacity_allocation_reprogramming_hold 'a second active hold of the same reservation'
rb_accepted "$(rb_alloc "$rb_res1" REPROGRAMMING_HOLD "now()" "$rb_sal2")" 'a released hold of the same reservation'
rb_refusal "$(rb_alloc "$rb_res1" WAITING NULL);" chk_capacity_allocation_kind 'a kind outside the two'

echo 'theReadsUseTheirIndexes (AC-D18.14)'
rb_p1="$(rb_explain "select 1 from $rb_ep where tenant_id = '$tenant' and episode_state = 'OPEN' and frozen_at is null and proposal_due_at < now()")"; printf '%s\n' "$rb_p1"
check 'the due episodes are read by an index led by the tenant' "$(printf '%s\n' "$rb_p1" | grep -Eq 'Index (Only )?Scan using (idx_rescheduling_episode_tenant_due|uq_rescheduling_episode_open_reservation)'; echo $?)"
rb_p2="$(rb_explain "select 1 from $rb_pr where tenant_id = '$tenant' and proposal_state = 'PENDING' and response_deadline_at < now()")"; printf '%s\n' "$rb_p2"
check 'the proposals past their deadline are read by an index led by the tenant' "$(printf '%s\n' "$rb_p2" | grep -Eq 'Index (Only )?Scan using (idx_rescheduling_proposal_tenant_deadline|uq_rescheduling_proposal_pending_episode)'; echo $?)"
rb_p3="$(rb_explain "select 1 from $rb_ep where tenant_id = '$tenant' and reservation_id = '$rb_res1'")"; printf '%s\n' "$rb_p3"
check 'the episodes of a reservation use an index led by the tenant' "$(printf '%s\n' "$rb_p3" | grep -Eq 'idx_rescheduling_episode_tenant_reservation|uq_rescheduling_episode_open_reservation|uq_rescheduling_episode_reservation_departure'; echo $?)"
rb_p4="$(rb_explain "select 1 from $rb_pr where tenant_id = '$tenant' and rescheduling_episode_id = '$rb_e1'")"; printf '%s\n' "$rb_p4"
check 'the proposals of an episode use an index led by the tenant' "$(printf '%s\n' "$rb_p4" | grep -Eq 'idx_rescheduling_proposal_tenant_episode|uq_rescheduling_proposal_pending_episode'; echo $?)"
check 'a read scoped to another tenant returns none of the episodes' "$([ "$(rb_sql "select count(*) from $rb_ep where tenant_id = '00000000-0000-0000-0000-000000000002' and reservation_id = '$rb_res1'")" = 0 ]; echo $?)"

echo 'theOutboxAcceptsReservationRescheduledWithItsSevenKeysOnly (AC-D18.16)'
rb_pay='{"reschedulingRecordId":"a","reservationId":"b","linkedReservationId":null,"originalSalidaId":"c","agreedSalidaId":"d","agreedStartAt":"2026-12-20T14:00:00Z","approvedBy":"e"}'
rb_accepted "$(rb_event "'$rb_pay'::jsonb")" 'ReservationRescheduled with exactly its seven keys'
rb_refusal "$(rb_event "'{\"reschedulingRecordId\":\"a\",\"reservationId\":\"b\",\"linkedReservationId\":null,\"originalSalidaId\":\"c\",\"agreedSalidaId\":\"d\",\"agreedStartAt\":\"x\",\"approvedBy\":\"e\",\"evidence\":\"call\"}'::jsonb");" chk_outbox_event_payload_keys_reservation_rescheduled 'ReservationRescheduled with an eighth key'
rb_refusal "$(rb_event "'{\"reschedulingRecordId\":\"a\",\"reservationId\":\"b\",\"approvedBy\":\"e\"}'::jsonb");" chk_outbox_event_payload_keys_reservation_rescheduled 'ReservationRescheduled with missing keys'
rb_refusal "$(rb_event "'$rb_pay'::jsonb" actor_id NULL);" chk_outbox_event_actor_required 'ReservationRescheduled without an actor'
rb_refusal "$(rb_event "'$rb_pay'::jsonb" reservation_id NULL);" chk_outbox_event_exactly_one_aggregate 'ReservationRescheduled without a reservation'
rb_accepted "$(rb_event "'{\"reservationId\":\"x\",\"cause\":\"PAYMENT_EXPIRY\",\"releasedSeats\":2}'::jsonb" event_type "'ReservationCancelled'")" 'ReservationCancelled of an earlier story keeps its key list'

echo 'onlyThePlannedObjectsAreAddedAndRevertLeavesNoTrace, slice 2 (AC-D18.1, AC-D18.17)'
rb_objects="$(sql "select (select count(*) from pg_tables where schemaname='$SCHEMA') || '|' || (select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace) || '|' || (select count(*) from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace='$SCHEMA'::regnamespace))" 2>/dev/null || true)"
IFS='|' read -r rb_bt rb_bf rb_bg <<< "$rb_base_objects"
check 'AC-D18.1 exactly one table was added to the base, and no function or trigger' "$([ -n "$rb_base_objects" ] && [ "$rb_objects" = "$((rb_bt + 1))|$rb_bf|$rb_bg" ]; echo $?)"
check 'AC-D18.1 nothing new appears in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasechangelog%'")" = 0 ]; echo $?)"
rb_second="$(liquibase update 2>&1)"; printf '%s\n' "$rb_second"
check 'AC-D18.17 a second update applies zero changesets' "$(printf '%s\n' "$rb_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "delete from $rb_ob where payload ->> 'reservationId' in ('b','x') or reservation_id = '$rb_res1'; delete from $rb_al where reservation_id = '$rb_res1'; delete from $rb_rec; delete from $rb_ep where rescheduling_episode_id in ('$rb_e1','$rb_e2'); delete from $SCHEMA.reservation where reservation_id in ('$rb_res1','$rb_res2','$rb_res3'); delete from $SCHEMA.catalog_service where service_id = '$rb_svc'; delete from $SCHEMA.customer where customer_id = '$rb_cust'" >/dev/null 2>&1 || true
check 'the rows of the probes are gone before the revert' "$([ "$(sql "select (select count(*) from $rb_rec) + (select count(*) from $rb_ep where rescheduling_episode_id in ('$rb_e1','$rb_e2')) + (select count(*) from $rb_al where reservation_id = '$rb_res1') + (select count(*) from $SCHEMA.reservation where reservation_id in ('$rb_res1','$rb_res2','$rb_res3'))")" = 0 ]; echo $?)"
rb_n="$(sql "select count(*) from $CONTROL where labels ilike '%rescheduling-record%'" 2>/dev/null || echo 0)"
liquibase rollback-count "$rb_n"
rb_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$rb_base" "$rb_reverted"
check 'AC-D18.17 the revert restores columns, constraints, indexes and privileges exactly and leaves 161 changesets' "$([ -n "$rb_base" ] && [ "$rb_reverted" = "$rb_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 161 ]; echo $?)"
db_labels='rescheduling-record'
liquibase update >/dev/null
check 'the changesets of the slice reapply to 170' "$([ "$(sql "select count(*) from $CONTROL")" = 170 ]; echo $?)"
