#!/usr/bin/env bash
# Sourced by db-ci.sh after client-notice-checks.sh, on the same disposable PostgreSQL instance.
# HU-COM-015 -db (issue multi-tour-docs#181), plan D-04, slice (b): the delivery data of an outbox event (attempts, last error, next attempt, failed mark,
# correlation id), its impossible combinations, and the guard that lets delivery change only those columns and never delete a pending or failed event.
# Three changesets labelled HU-COM-015 and client-notice-delivery: ddl-alter-028, ddl-functions-006 and ddl-triggers-006. Probes are written first: red
# before the changesets, green after (Annex J.1).
nd_ob="$SCHEMA.outbox_event"; nd_res="$(aid 4310)"; nd_cust="$(aid 4301)"; nd_svc="$(aid 4303)"
nd_sql() { sql "$1" 2>/dev/null || true; }
nd_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-015 db: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -Eq "$2"; echo $?)"
}
nd_accepted() { # SQL, description
  local status=0
  engine "$1" >/dev/null || status=$?
  check "HU-COM-015 db: $2 is accepted" "$status"
}
nd_notice() { # event id, then column/value pairs that replace the defaults of an unpublished notice
  local -A v=([published_at]="NULL" [correlation_id]="NULL")
  local id="$1"; shift
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $nd_ob (outbox_event_id, tenant_id, event_type, reservation_id, actor_id, occurred_at, published_at, payload) values ('$id', '$tenant', 'ClientNotified', '$nd_res', '$actor', now(), ${v[published_at]}, '{\"customerId\":\"$nd_cust\",\"notificationType\":\"PROOF_APPROVED\",\"triggeringEventType\":\"PaymentValidated\",\"triggeringEventId\":\"$id\"}'::jsonb)"
}
nd_upd() { echo "update $nd_ob set $2 where outbox_event_id = '$1'"; }
nd_objects() { sql "select (select count(*) from pg_tables where schemaname='$SCHEMA') || '|' || (select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace) || '|' || (select count(*) from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace='$SCHEMA'::regnamespace))" 2>/dev/null || true; }
nd_e1="$(aid 4321)"; nd_e2="$(aid 4322)"; nd_e3="$(aid 4323)"; nd_e4="$(aid 4324)"; nd_e5="$(aid 4325)"; nd_e6="$(aid 4326)"; nd_old="$(aid 4320)"

echo 'HU-COM-015 delivery - base: the 112 changesets that exist before the delivery data'
liquibase rollback-count 999 >/dev/null
db_labels='!client-notice-delivery'
liquibase update >/dev/null
nd_base="$(snapshot)"
nd_base_objects="$(nd_objects)"
check 'base holds exactly 112 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 112 ]; echo $?)"
sql "insert into $SCHEMA.customer (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status, terms_accepted, terms_accepted_at) values ('$nd_cust', '$tenant', 'Delivery probe', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now());
     insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values ('$nd_svc', '$tenant', 'TOUR', 'Delivery probe tour', 'ACTIVE', 150000, 90000, 12, false, false, now(), now())" >/dev/null 2>&1 || true
engine "$(rs_row reservation_id "'$nd_res'" customer_id "'$nd_cust'" service_id "'$nd_svc'");" >/dev/null || true
engine "$(nd_notice "$nd_old")" >/dev/null || true
check 'the probe reservation and one notice written before the columns exist' "$([ "$(nd_sql "select count(*) from $nd_ob where outbox_event_id = '$nd_old'")" = 1 ]; echo $?)"

echo 'HU-COM-015 delivery - probes written first: red before the changesets, green after'
db_labels='client-notice-delivery'
liquibase update >/dev/null
check 'the three changesets bring the control table to 115' "$([ "$(sql "select count(*) from $CONTROL")" = 115 ]; echo $?)"

echo 'theAttemptColumnsExistAndOldRowsKeepTheirDefaults (AC-D15.6)'
check 'AC-D15.6 attempts is integer NOT NULL DEFAULT 0; last_error and correlation_id are text; next_attempt_at and failed_at are timestamptz; all nullable but attempts' "$([ "$(nd_sql "select string_agg(column_name || ' ' || data_type || ' ' || is_nullable || ' ' || coalesce(column_default, ''), ',' order by column_name) from information_schema.columns where table_schema='$SCHEMA' and table_name='outbox_event' and column_name in ('attempts','last_error','next_attempt_at','failed_at','correlation_id')")" = 'attempts integer NO 0,correlation_id text YES ,failed_at timestamp with time zone YES ,last_error text YES ,next_attempt_at timestamp with time zone YES ' ]; echo $?)"
check 'AC-D15.6 the notice written before the columns reads attempts 0 and the others null' "$([ "$(nd_sql "select attempts || '|' || coalesce(last_error, 'n') || '|' || coalesce(next_attempt_at::text, 'n') || '|' || coalesce(failed_at::text, 'n') || '|' || coalesce(correlation_id, 'n') from $nd_ob where outbox_event_id = '$nd_old'")" = '0|n|n|n|n' ]; echo $?)"
engine "$(nd_notice "$nd_e1")" >/dev/null || true
nd_refusal "$(nd_upd "$nd_e1" "attempts = -1");" chk_outbox_event_attempts_range 'a negative attempt count'
nd_refusal "$(nd_upd "$nd_e1" "attempts = 21");" chk_outbox_event_attempts_range 'twenty-one attempts'
nd_refusal "$(nd_upd "$nd_e1" "attempts = 1, last_error = repeat('x', 501)");" chk_outbox_event_last_error_length 'a last error of 501 characters'
nd_accepted "$(nd_upd "$nd_e1" "attempts = 1, last_error = repeat('x', 500), next_attempt_at = now() + interval '5 seconds'")" 'one attempt with a 500-character error and a wait'
check 'AC-D15.6 the attempt data was stored' "$([ "$(nd_sql "select attempts || '|' || char_length(last_error) || '|' || (next_attempt_at is not null) from $nd_ob where outbox_event_id = '$nd_e1'")" = '1|500|true' ]; echo $?)"
nd_refusal "insert into $nd_ob (tenant_id, event_type, reservation_id, actor_id, occurred_at, correlation_id, payload) values ('$tenant', 'ReservationCancelled', '$nd_res', '$actor', now(), repeat('c', 65), '{\"reservationId\":\"x\",\"cause\":\"PAYMENT_EXPIRY\",\"releasedSeats\":2}'::jsonb);" chk_outbox_event_correlation_id_length 'a correlation id of 65 characters'

echo 'impossibleCombinationsOfPublishedFailedAndAttemptsAreRefused (AC-D15.7)'
engine "$(nd_notice "$nd_e2")" >/dev/null || true
nd_refusal "$(nd_upd "$nd_e2" "attempts = 1, published_at = now(), failed_at = now()");" chk_outbox_event_delivery_state 'a row both published and failed'
nd_refusal "$(nd_upd "$nd_e2" "failed_at = now()");" chk_outbox_event_delivery_state 'a failed mark with zero attempts'
nd_refusal "$(nd_upd "$nd_e2" "attempts = 20, failed_at = now(), next_attempt_at = now()");" chk_outbox_event_delivery_state 'a wait on a failed row'
nd_refusal "$(nd_upd "$nd_e2" "published_at = now(), next_attempt_at = now()");" chk_outbox_event_delivery_state 'a wait on a published row'

echo 'deliveryChangesOnlyTheDeliveryColumns (AC-D15.8)'
engine "$(nd_notice "$nd_e3")" >/dev/null || true
nd_refusal "$(nd_upd "$nd_e3" "payload = '{\"customerId\":\"x\",\"notificationType\":\"PROOF_REJECTED\",\"triggeringEventType\":\"PaymentRejected\",\"triggeringEventId\":\"$nd_e3\"}'::jsonb");" trg_outbox_event_delivery_guard 'an update of the payload'
nd_refusal "$(nd_upd "$nd_e3" "event_type = 'ReservationConfirmed'");" 'trg_outbox_event_delivery_guard|chk_outbox_event' 'an update of the event type'
nd_refusal "$(nd_upd "$nd_e3" "reservation_id = NULL");" 'trg_outbox_event_delivery_guard|chk_outbox_event' 'an update of the reference'
nd_refusal "$(nd_upd "$nd_e3" "tenant_id = '00000000-0000-0000-0000-000000000002'");" trg_outbox_event_delivery_guard 'an update of the tenant'
nd_refusal "$(nd_upd "$nd_e3" "occurred_at = now() + interval '1 day'");" trg_outbox_event_delivery_guard 'an update of the occurrence time'
nd_accepted "$(nd_upd "$nd_e3" "attempts = 2, last_error = 'The mail provider answered 503', next_attempt_at = now() + interval '10 seconds'")" 'an update of the attempt columns'
nd_accepted "$(nd_upd "$nd_e3" "published_at = now(), next_attempt_at = NULL")" 'marking the event published'

echo 'afterPublicationTheAttemptDataIsFrozen (AC-D15.8)'
nd_refusal "$(nd_upd "$nd_e3" "attempts = 3");" trg_outbox_event_delivery_guard 'an attempt on a published event'
nd_refusal "$(nd_upd "$nd_e3" "last_error = 'late'");" trg_outbox_event_delivery_guard 'a last error on a published event'
nd_refusal "$(nd_upd "$nd_e3" "published_at = NULL");" trg_outbox_event_delivery_guard 'unpublishing an event'
engine "$(nd_notice "$nd_e4")" >/dev/null || true
nd_accepted "$(nd_upd "$nd_e4" "attempts = 20, last_error = 'The mail provider answered 503', failed_at = now()")" 'the twentieth attempt marking the event failed'
nd_refusal "$(nd_upd "$nd_e4" "last_error = 'rewritten'");" trg_outbox_event_delivery_guard 'a change on a failed event'

echo 'anUnpublishedOrFailedEventCannotBeDeleted (AC-D15.9)'
engine "$(nd_notice "$nd_e5")" >/dev/null || true
nd_refusal "delete from $nd_ob where outbox_event_id = '$nd_e5';" trg_outbox_event_delivery_guard 'the deletion of an unpublished event by the application user'
nd_refusal "delete from $nd_ob where outbox_event_id = '$nd_e4';" trg_outbox_event_delivery_guard 'the deletion of a failed event by the application user'
nd_accepted "delete from $nd_ob where outbox_event_id = '$nd_e3';" 'the purge of a published event by the application user'
engine "$(nd_notice "$nd_e6" published_at "now()")" >/dev/null || true
nd_accepted "delete from $nd_ob where outbox_event_id = '$nd_e6';" 'the purge of an event written as published'
check 'AC-D15.9 the unpublished and the failed events are still there' "$([ "$(nd_sql "select count(*) from $nd_ob where outbox_event_id in ('$nd_e5','$nd_e4')")" = 2 ]; echo $?)"

echo 'onlyThePlannedObjectsAreAdded (AC-D15.1)'
check 'AC-D15.1 the slice adds one function and one trigger and no table' "$([ "$(nd_objects)" = "$(echo "$nd_base_objects" | awk -F'|' '{print $1 "|" $2+1 "|" $3+1}')" ]; echo $?)"
check 'AC-D15.1 the guard is a BEFORE UPDATE OR DELETE row trigger' "$([ "$(nd_sql "select count(*) from pg_trigger where tgrelid='$nd_ob'::regclass and tgname='trg_outbox_event_delivery_guard' and (tgtype & 1) = 1 and (tgtype & 2) = 2 and (tgtype & 8) = 8 and (tgtype & 16) = 16")" = 1 ]; echo $?)"
check 'AC-D15.1 nothing new appears in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasechangelog%'")" = 0 ]; echo $?)"

echo 'secondRunAppliesZeroAndTheRevertRestoresTheSchema (AC-D15.12, AC-D15.13)'
nd_second="$(liquibase update 2>&1)"; printf '%s\n' "$nd_second"
check 'AC-D15.12 a second update applies zero changesets' "$(printf '%s\n' "$nd_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "delete from $nd_ob where event_type = 'ClientNotified'; delete from $SCHEMA.reservation where reservation_id = '$nd_res'; delete from $SCHEMA.catalog_service where service_id = '$nd_svc'; delete from $SCHEMA.customer where customer_id = '$nd_cust'" >/dev/null 2>&1 || true
check 'the events of the probes are gone before the revert' "$([ "$(sql "select count(*) from $nd_ob")" = 0 ]; echo $?)"
liquibase rollback-count 3
nd_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$nd_base" "$nd_reverted"
check 'AC-D15.13 the three-change revert restores columns, constraints, indexes and privileges exactly and leaves 112 changesets' "$([ -n "$nd_base" ] && [ "$nd_reverted" = "$nd_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 112 ]; echo $?)"
check 'AC-D15.13 the function and the trigger are gone after the revert' "$([ "$(nd_objects)" = "$nd_base_objects" ]; echo $?)"
db_labels='client-notice-delivery'
liquibase update >/dev/null
check 'AC-D15.13 the changesets reapply to 115 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 115 ]; echo $?)"
