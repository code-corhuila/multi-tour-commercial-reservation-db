#!/usr/bin/env bash
# Sourced by db-ci.sh after payment-followup-checks.sh, on the same disposable PostgreSQL instance and with the eleven changesets of
# HU-COM-011 applied (99 in the control table). HU-COM-011 -db (issue multi-tour-docs#177), plan D-04, D-05, D-07: the cancellation columns
# and the terminal guard of reservation, the closed key list of ReservationCancelled, the structure and the revert of the whole slice.
# Probes are written first: red before the changesets, green after (Annex J.1).
rc_t="$SCHEMA.reservation"; rc_ob="$SCHEMA.outbox_event"
rc_res1="$(aid 3210)"; rc_res2="$(aid 3211)"; rc_res3="$(aid 3212)"
rc_sql() { sql "$1" 2>/dev/null || true; }
rc_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-011 db: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
rc_accepted() { # SQL, description
  local status=0
  engine "$1" >/dev/null || status=$?
  check "HU-COM-011 db: $2 is accepted" "$status"
}
rc_event() { # payload (SQL literal), then column/value pairs that replace the defaults
  local payload="$1"; shift
  local -A v=([reservation_id]="'$rc_res3'" [event_type]="'ReservationCancelled'")
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $rc_ob (tenant_id, event_type, reservation_id, actor_id, occurred_at, payload) values ('$tenant', ${v[event_type]}, ${v[reservation_id]}, '$actor', now(), $payload)"
}
rc_cancel() { # reservation id, then the SET list of the cancellation
  echo "update $rc_t set $2 where reservation_id = '$1'"
}
rc_ok_set="reservation_status = 'CANCELLED', cancellation_cause = 'PAYMENT_EXPIRY', cancelled_at = now(), cancelled_by = NULL"

engine "$(rs_row reservation_id "'$rc_res1'" customer_id "'$fu_cust'" service_id "'$fu_svc'"); $(rs_row reservation_id "'$rc_res2'" customer_id "'$fu_cust'" service_id "'$fu_svc'"); $(rs_row reservation_id "'$rc_res3'" customer_id "'$fu_cust'" service_id "'$fu_svc'");" >/dev/null || true
check 'the probe reservations exist with the cancellation columns in place' "$([ "$(rc_sql "select count(*) from $rc_t where reservation_id in ('$rc_res1','$rc_res2','$rc_res3') and cancellation_cause is null and cancelled_at is null and cancelled_by is null")" = 3 ]; echo $?)"

echo 'cancelledNeedsCauseAndInstantAndOthersCarryNone (AC-D11.7)'
rc_refusal "$(rc_cancel "$rc_res1" "reservation_status = 'CANCELLED'");" chk_reservation_cancellation_coherent 'a cancelled reservation without cause or instant'
rc_refusal "$(rc_cancel "$rc_res1" "reservation_status = 'CANCELLED', cancellation_cause = 'PAYMENT_EXPIRY'");" chk_reservation_cancellation_coherent 'a cancelled reservation without the instant'
rc_refusal "$(rc_cancel "$rc_res1" "reservation_status = 'CANCELLED', cancelled_at = now()");" chk_reservation_cancellation_coherent 'a cancelled reservation without the cause'
rc_refusal "$(rc_cancel "$rc_res1" "cancellation_cause = 'PAYMENT_EXPIRY'");" chk_reservation_cancellation_coherent 'a pending reservation that carries a cause'
rc_refusal "$(rc_cancel "$rc_res1" "cancelled_at = now()");" chk_reservation_cancellation_coherent 'a pending reservation that carries an instant'
rc_refusal "$(rc_cancel "$rc_res1" "reservation_status = 'CANCELLED', cancellation_cause = 'MOOD', cancelled_at = now()");" chk_reservation_cancellation_cause 'a cause outside the three codes'
rc_accepted "$(rc_cancel "$rc_res1" "$rc_ok_set")" 'a cancellation by the system with cause PAYMENT_EXPIRY and no canceller'
rc_accepted "$(rc_cancel "$rc_res2" "reservation_status = 'CANCELLED', cancellation_cause = 'CUSTOMER_REQUEST', cancelled_at = now(), cancelled_by = '$actor'")" 'a cancellation by a person with cause CUSTOMER_REQUEST'
check 'AC-D11.7 the system cancellation stored no canceller and the person one stored the actor' "$([ "$(rc_sql "select count(*) from $rc_t where (reservation_id='$rc_res1' and cancelled_by is null and cancelled_at is not null) or (reservation_id='$rc_res2' and cancelled_by='$actor')")" = 2 ]; echo $?)"

echo 'aCancelledReservationCannotBeUpdated (AC-D11.8)'
rc_refusal "update $rc_t set party_size = 3 where reservation_id = '$rc_res1';" trg_reservation_cancelled_guard 'an update of a cancelled reservation'
rc_refusal "update $rc_t set reservation_status = 'PENDING_PAYMENT', cancellation_cause = NULL, cancelled_at = NULL where reservation_id = '$rc_res1';" trg_reservation_cancelled_guard 'the reactivation of a cancelled reservation'
rc_refusal "$(rc_cancel "$rc_res1" "$rc_ok_set");" trg_reservation_cancelled_guard 'a second cancellation of a cancelled reservation'
check 'AC-D11.8 trg_reservation_cancelled_guard is a BEFORE UPDATE row trigger and the birth trigger is untouched' "$([ "$(rc_sql "select count(*) from pg_trigger where tgrelid='$rc_t'::regclass and not tgisinternal and ((tgname='trg_reservation_cancelled_guard' and (tgtype & 1) = 1 and (tgtype & 2) = 2 and (tgtype & 16) = 16) or (tgname='trg_reservation_birth' and (tgtype & 4) = 4 and (tgtype & 16) = 0))")" = 2 ]; echo $?)"
rc_accepted "update $rc_t set party_size = 3 where reservation_id = '$rc_res3'" 'an update of a reservation that is not cancelled'

echo 'reservationCancelledPayloadHasOnlyItsKeyList (AC-D11.11)'
rc_payload='{"reservationId":"x","cause":"PAYMENT_EXPIRY","releasedSeats":2}'
rc_accepted "$(rc_event "'$rc_payload'::jsonb")" 'ReservationCancelled with exactly reservationId, cause and releasedSeats'
rc_refusal "$(rc_event "'{\"reservationId\":\"x\",\"cause\":\"PAYMENT_EXPIRY\",\"releasedSeats\":2,\"customerName\":\"Ana\"}'::jsonb");" chk_outbox_event_payload_keys_reservation_cancelled 'ReservationCancelled carrying a customer name'
rc_refusal "$(rc_event "'{\"reservationId\":\"x\",\"cause\":\"PAYMENT_EXPIRY\"}'::jsonb");" chk_outbox_event_payload_keys_reservation_cancelled 'ReservationCancelled with a missing key'
rc_refusal "$(rc_event NULL);" chk_outbox_event_payload 'ReservationCancelled without payload'
rc_refusal "$(rc_event "'$rc_payload'::jsonb" reservation_id NULL);" chk_outbox_event_exactly_one_aggregate 'ReservationCancelled without a reservation'
rc_refusal "$(rc_event "'$rc_payload'::jsonb" reservation_id "'$(aid 3299)'");" fk_outbox_event_reservation 'ReservationCancelled for a reservation that does not exist'

echo 'onlyThePlannedObjectsAreAdded (AC-D11.1)'
rc_count_sql="select (select count(*) from pg_tables where schemaname='$SCHEMA') || '|' || (select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace) || '|' || (select count(*) from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace='$SCHEMA'::regnamespace))"
rc_objects="$(sql "$rc_count_sql" 2>/dev/null || true)"
IFS='|' read -r rc_bt rc_bf rc_bg <<< "$fu_base_objects"
rc_expected="$((rc_bt + 1))|$((rc_bf + 2))|$((rc_bg + 2))"
printf 'Base objects (tables|functions|triggers): %s\nExpected: %s\nFound:    %s\n' "$fu_base_objects" "$rc_expected" "$rc_objects"
check 'AC-D11.1 exactly one table, two functions and two triggers were added to the base, and they are the planned ones' "$([ -n "$fu_base_objects" ] && [ "$rc_objects" = "$rc_expected" ] && [ "$(rc_sql "select count(*) from pg_tables where schemaname='$SCHEMA' and tablename='payment_followup'")" = 1 ] && [ "$(rc_sql "select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace and proname in ('fn_payment_deadline_extension_guard','fn_reservation_cancelled_guard')")" = 2 ] && [ "$(rc_sql "select count(*) from pg_trigger where tgname in ('trg_payment_deadline_extension_guard','trg_reservation_cancelled_guard')")" = 2 ]; echo $?)"
check 'AC-D11.1 nothing new appears in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasechangelog%'")" = 0 ] && [ "$(rc_sql "select count(*) from pg_proc where pronamespace='public'::regnamespace and proname like '%payment%'")" = 0 ]; echo $?)"
check 'RNF-D11.2 neither new column of payment_deadline nor of reservation has a DEFAULT' "$([ "$(rc_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and column_name in ('extension_hours','extension_granted_at','extension_granted_by','frozen_at','remaining_at_freeze_minutes','cancellation_cause','cancelled_at','cancelled_by') and column_default is not null")" = 0 ]; echo $?)"

echo 'secondRunAppliesZeroAndRevertLeavesNoTrace (AC-D11.13)'
rc_second="$(liquibase update 2>&1)"; printf '%s\n' "$rc_second"
check 'AC-D11.13 a second update applies zero changesets' "$(printf '%s\n' "$rc_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "delete from $rc_ob where reservation_id in ('$rc_res1','$rc_res2','$rc_res3'); delete from $SCHEMA.idempotency_key where key = 'followup-key-1'; delete from $fu_t; delete from $fu_dl where reservation_id in ('$fu_res1','$fu_res2','$fu_res_b'); delete from $rc_t where reservation_id in ('$fu_res1','$fu_res2','$fu_res_b','$rc_res1','$rc_res2','$rc_res3'); delete from $SCHEMA.catalog_service where service_id = '$fu_svc'; delete from $SCHEMA.customer where customer_id in ('$fu_cust','$fu_cust_b')" >/dev/null 2>&1 || true
check 'the rows of the probes are gone before the revert' "$([ "$(sql "select (select count(*) from $fu_t) + (select count(*) from $rc_t where reservation_id in ('$rc_res1','$rc_res2','$rc_res3'))")" = 0 ]; echo $?)"
liquibase rollback-count 11
rc_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$fu_base" "$rc_reverted"
check 'AC-D11.13 the eleven-change revert restores columns, constraints, indexes and privileges exactly and leaves 88 changesets' "$([ -n "$fu_base" ] && [ "$rc_reverted" = "$fu_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 88 ]; echo $?)"
check 'the follow-up table, the two guards and the extension, freeze and cancellation columns are gone after the revert' "$([ "$(rc_sql "select count(*) from pg_tables where schemaname='$SCHEMA' and tablename='payment_followup'")" = 0 ] && [ "$(rc_sql "select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace and proname in ('fn_payment_deadline_extension_guard','fn_reservation_cancelled_guard')")" = 0 ] && [ "$(rc_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and column_name in ('extension_hours','frozen_at','cancellation_cause')")" = 0 ]; echo $?)"
db_labels=''
liquibase update >/dev/null
liquibase rollback-count 999 >/dev/null
liquibase update >/dev/null
liquibase validate >/dev/null
check 'a full build from empty without any label filter applies exactly 177 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 153 ]; echo $?)"
