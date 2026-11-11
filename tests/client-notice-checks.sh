#!/usr/bin/env bash
# Sourced by db-ci.sh after the discount-rule stackable checks, on the same disposable PostgreSQL instance.
# HU-COM-015 -db (issue multi-tour-docs#181), plan D-02 and D-03, slice (a): the ClientNotified notice as one more type of the outbox with a closed
# payload and no personal datum, and one notice per triggering event and tenant. Two changesets, both labelled HU-COM-015 (ddl-alter-027 and
# ddl-indexes-032). Probes are written first: red before the changesets, green after (Annex J.1).
nc_ob="$SCHEMA.outbox_event"; nc_tenant_b="00000000-0000-0000-0000-000000000002"
nc_cust="$(aid 4101)"; nc_cust_b="$(aid 4102)"; nc_svc="$(aid 4103)"
nc_res1="$(aid 4110)"; nc_res_b="$(aid 4112)"
nc_sql() { sql "$1" 2>/dev/null || true; }
nc_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-015 db: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -Eq "$2"; echo $?)"
}
nc_accepted() { # SQL, description
  local status=0
  engine "$1" >/dev/null || status=$?
  check "HU-COM-015 db: $2 is accepted" "$status"
}
nc_payload() { # notification type, triggering event type, triggering event id, extra JSON members (optional, with a leading comma)
  echo "'{\"customerId\":\"$nc_cust\",\"notificationType\":\"$1\",\"triggeringEventType\":\"$2\",\"triggeringEventId\":\"$3\"${4:-}}'::jsonb"
}
nc_event() { # payload (SQL literal), then column/value pairs that replace the defaults
  local payload="$1"; shift
  local -A v=([tenant_id]="'$tenant'" [event_type]="'ClientNotified'" [reservation_id]="'$nc_res1'" [customer_id]="NULL" [actor_id]="'$actor'")
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $nc_ob (tenant_id, event_type, reservation_id, customer_id, actor_id, occurred_at, payload) values (${v[tenant_id]}, ${v[event_type]}, ${v[reservation_id]}, ${v[customer_id]}, ${v[actor_id]}, now(), $payload)"
}
nc_objects() { sql "select (select count(*) from pg_tables where schemaname='$SCHEMA') || '|' || (select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace) || '|' || (select count(*) from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace='$SCHEMA'::regnamespace))" 2>/dev/null || true; }

echo 'HU-COM-015 db - base: the 110 changesets that exist before the story'
liquibase rollback-count 999 >/dev/null
db_labels='!HU-COM-015 and !HU-COM-016'
liquibase update >/dev/null
nc_base="$(snapshot)"
nc_base_objects="$(nc_objects)"
check 'base holds exactly 110 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 110 ]; echo $?)"
sql "insert into $SCHEMA.customer (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status, terms_accepted, terms_accepted_at) values ('$nc_cust', '$tenant', 'Notice probe A', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now()), ('$nc_cust_b', '$nc_tenant_b', 'Notice probe B', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now());
     insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values ('$nc_svc', '$tenant', 'TOUR', 'Notice probe tour', 'ACTIVE', 150000, 90000, 12, false, false, now(), now())" >/dev/null 2>&1 || true
engine "$(rs_row reservation_id "'$nc_res1'" customer_id "'$nc_cust'" service_id "'$nc_svc'"); $(rs_row reservation_id "'$nc_res_b'" tenant_id "'$nc_tenant_b'" customer_id "'$nc_cust_b'" service_id "'$nc_svc'");" >/dev/null || true
check 'the probe reservations exist on the base' "$([ "$(nc_sql "select count(*) from $SCHEMA.reservation where reservation_id in ('$nc_res1','$nc_res_b')")" = 2 ]; echo $?)"

echo 'HU-COM-015 db - probes written first: red before the changesets, green after'
db_labels='HU-COM-015'
liquibase update >/dev/null
check 'the two changesets of slice (a) bring the control table to 112' "$([ "$(sql "select count(*) from $CONTROL")" = 112 ]; echo $?)"

echo 'slice015AddsOnlyTheExpectedObjectsAndNothingInPublic (AC-D15.1)'
check 'AC-D15.1 the slice adds no table, function or trigger to the base' "$([ "$(nc_objects)" = "$nc_base_objects" ]; echo $?)"
check 'AC-D15.1 the two planned constraints and the unique index exist' "$([ "$(nc_sql "select (select count(*) from pg_constraint where conrelid='$nc_ob'::regclass and conname in ('chk_outbox_event_payload_keys_client_notified','chk_outbox_event_client_notified_codes')) || '|' || (select count(*) from pg_indexes where schemaname='$SCHEMA' and indexname='uq_outbox_event_client_notified_trigger')")" = '2|1' ]; echo $?)"
check 'AC-D15.1 nothing new appears in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasechangelog%'")" = 0 ]; echo $?)"

echo 'aNoticeWithItsFourKeysIsAcceptedWithAndWithoutAnActor (AC-D15.2)'
nc_accepted "$(nc_event "$(nc_payload PROOF_APPROVED PaymentValidated "$(aid 4201)")")" 'a notice with its four keys and the actor of the fact'
nc_accepted "$(nc_event "$(nc_payload RESERVATION_CANCELLED_NON_PAYMENT ReservationCancelled "$(aid 4202)")" actor_id NULL)" 'a notice with no actor'
nc_accepted "$(nc_event "$(nc_payload PROOF_REJECTED PaymentRejected "$(aid 4203)")")" 'a notice of type PROOF_REJECTED triggered by PaymentRejected'
nc_accepted "$(nc_event "$(nc_payload RESERVATION_CONFIRMED ReservationConfirmed "$(aid 4204)")")" 'a notice of type RESERVATION_CONFIRMED triggered by ReservationConfirmed'

echo 'aNoticeWithAMissingExtraOrSensitiveKeyIsRefused (AC-D15.3)'
nc_k='chk_outbox_event_payload_keys_client_notified'
nc_refusal "$(nc_event "'{\"notificationType\":\"PROOF_APPROVED\",\"triggeringEventType\":\"PaymentValidated\",\"triggeringEventId\":\"$(aid 4301)\"}'::jsonb");" "$nc_k" 'a notice without customerId'
nc_refusal "$(nc_event "'{\"customerId\":\"$nc_cust\",\"triggeringEventType\":\"PaymentValidated\",\"triggeringEventId\":\"$(aid 4302)\"}'::jsonb");" "$nc_k|chk_outbox_event_client_notified_codes" 'a notice without notificationType'
nc_refusal "$(nc_event "'{\"customerId\":\"$nc_cust\",\"notificationType\":\"PROOF_APPROVED\",\"triggeringEventId\":\"$(aid 4303)\"}'::jsonb");" "$nc_k|chk_outbox_event_client_notified_codes" 'a notice without triggeringEventType'
nc_refusal "$(nc_event "'{\"customerId\":\"$nc_cust\",\"notificationType\":\"PROOF_APPROVED\",\"triggeringEventType\":\"PaymentValidated\"}'::jsonb");" "$nc_k" 'a notice without triggeringEventId'
nc_refusal "$(nc_event "$(nc_payload PROOF_APPROVED PaymentValidated "$(aid 4304)" ',"amountCents":1000')");" "$nc_k" 'a notice with an extra key'
nc_refusal "$(nc_event "$(nc_payload PROOF_APPROVED PaymentValidated "$(aid 4305)" ',"email":"ana@example.com"')");" "$nc_k|chk_outbox_event_payload_no_sensitive_keys" 'a notice carrying an e-mail address'
nc_refusal "$(nc_event "$(nc_payload PROOF_APPROVED PaymentValidated "$(aid 4306)" ',"fullName":"Ana Perez"')");" "$nc_k|chk_outbox_event_payload_no_sensitive_keys" 'a notice carrying a name'
nc_refusal "$(nc_event NULL);" 'chk_outbox_event_payload|chk_outbox_event_client_notified_codes' 'a notice without payload'
nc_refusal "$(nc_event "$(nc_payload PROOF_APPROVED PaymentValidated "$(aid 4307)")" reservation_id NULL);" chk_outbox_event_exactly_one_aggregate 'a notice without a reservation'
nc_refusal "$(nc_event "$(nc_payload PROOF_APPROVED PaymentValidated "$(aid 4308)")" customer_id "'$nc_cust'");" chk_outbox_event_exactly_one_aggregate 'a notice that names the reservation and the customer as aggregates'

echo 'anUnknownNotificationTypeOrTriggeringTypeIsRefused (AC-D15.4)'
nc_c='chk_outbox_event_client_notified_codes'
nc_refusal "$(nc_event "$(nc_payload WELCOME PaymentValidated "$(aid 4401)")");" "$nc_c" 'a notification type outside the eight codes'
nc_refusal "$(nc_event "$(nc_payload proof_approved PaymentValidated "$(aid 4402)")");" "$nc_c" 'a notification type in lower case'
nc_refusal "$(nc_event "$(nc_payload PROOF_APPROVED Bogus "$(aid 4403)")");" "$nc_c" 'a triggering type that is not a type of the outbox'
nc_refusal "$(nc_event "$(nc_payload PROOF_APPROVED ClientNotified "$(aid 4404)")");" "$nc_c" 'a notice triggered by a notice'

echo 'theActorStaysRequiredForTheOtherReservationEvents (DP-D15-2)'
nc_refusal "insert into $nc_ob (tenant_id, event_type, reservation_id, actor_id, occurred_at, payload) values ('$tenant', 'ReservationCancelled', '$nc_res1', NULL, now(), '{\"reservationId\":\"x\",\"cause\":\"PAYMENT_EXPIRY\",\"releasedSeats\":2}'::jsonb);" chk_outbox_event_actor_required 'a ReservationCancelled without actor'

echo 'oneNoticePerTriggeringEventAndTenant (AC-D15.5)'
nc_dup="$(aid 4501)"
nc_accepted "$(nc_event "$(nc_payload PROOF_APPROVED PaymentValidated "$nc_dup")")" 'the first notice of a triggering event'
nc_refusal "$(nc_event "$(nc_payload PROOF_APPROVED PaymentValidated "$nc_dup")");" uq_outbox_event_client_notified_trigger 'a second notice of the same triggering event in the same tenant'
nc_refusal "$(nc_event "$(nc_payload RESERVATION_CONFIRMED PaymentValidated "$nc_dup")");" uq_outbox_event_client_notified_trigger 'a second notice of another type for the same triggering event'
nc_accepted "$(nc_event "$(nc_payload PROOF_APPROVED PaymentValidated "$nc_dup")" tenant_id "'$nc_tenant_b'" reservation_id "'$nc_res_b'")" 'the same triggering event id in another tenant'
check 'AC-D15.5 the unique key is a valid unique partial index on (tenant_id, triggeringEventId) for ClientNotified only' "$([ "$(nc_sql "select count(*) from pg_index i join pg_class c on c.oid=i.indexrelid where c.relname='uq_outbox_event_client_notified_trigger' and i.indisunique and i.indisvalid")" = 1 ] && [ "$(nc_sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and indexname='uq_outbox_event_client_notified_trigger' and indexdef like '%tenant_id%triggeringEventId%' and indexdef like '%ClientNotified%'")" = 1 ]; echo $?)"

echo 'secondRunAppliesZeroAndTheRevertRestoresTheSchema (AC-D15.12, AC-D15.13)'
nc_second="$(liquibase update 2>&1)"; printf '%s\n' "$nc_second"
check 'AC-D15.12 a second update applies zero changesets' "$(printf '%s\n' "$nc_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "delete from $nc_ob where event_type = 'ClientNotified'; delete from $SCHEMA.reservation where reservation_id in ('$nc_res1','$nc_res_b'); delete from $SCHEMA.catalog_service where service_id = '$nc_svc'; delete from $SCHEMA.customer where customer_id in ('$nc_cust','$nc_cust_b')" >/dev/null 2>&1 || true
check 'the notices of the probes are gone before the revert' "$([ "$(sql "select count(*) from $nc_ob where event_type = 'ClientNotified'")" = 0 ]; echo $?)"
liquibase rollback-count 2
nc_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$nc_base" "$nc_reverted"
check 'AC-D15.13 the two-change revert restores columns, constraints, indexes and privileges exactly and leaves 110 changesets' "$([ -n "$nc_base" ] && [ "$nc_reverted" = "$nc_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 110 ]; echo $?)"
db_labels='HU-COM-015'
liquibase update >/dev/null
check 'AC-D15.13 the changesets reapply to 112 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 112 ]; echo $?)"
