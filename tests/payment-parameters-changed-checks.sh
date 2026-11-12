#!/usr/bin/env bash
# Sourced by db-ci.sh after reservation-confirmed-value-checks.sh, on the same disposable PostgreSQL instance, with every changeset that exists before the slice (counted at run time); the slice is one changeset, 044.
# HU-COM-009 DP-04 -db (Project Lead, 2026-11-12; 02-domain/domain-events.md): the tenth widening of outbox_event adds PaymentParametersChanged, the audit trace of a change of the payment parameters. Its aggregate is the changed
# row of payment_condition (payment_condition_id, a seventh reference), its payload is closed (tenantId, actorId, paymentType and changedAt required; serviceId allowed) and its actor is required. No value of a parameter and no
# reason can travel. The probes run as the superuser with the foreign keys switched off (session_replication_role = replica); the CHECK constraints under test still apply. The changeset is labelled payment-parameters-changed.
# Probes are written first: red before the changeset, green after (Annex J.1).
pc_ob="$SCHEMA.outbox_event"; pc_row="$(aid 9301)"; pc_res="$(aid 9302)"; pc_svc="$(aid 9303)"
pc_key='chk_outbox_event_payload_keys_payment_parameters_changed'
pc_base_keys="\"tenantId\":\"$tenant\",\"actorId\":\"$actor\",\"paymentType\":\"DEPOSIT\",\"changedAt\":\"2026-11-12T10:00:00Z\""
pc_event() { # payload (SQL literal), then column/value pairs that replace the defaults
  local payload="$1"; shift
  local -A v=([event_type]="'PaymentParametersChanged'" [payment_condition_id]="'$pc_row'" [reservation_id]="null" [actor_id]="'$actor'")
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "set session_replication_role = replica; insert into $pc_ob (tenant_id, event_type, payment_condition_id, reservation_id, actor_id, occurred_at, payload) values ('$tenant', ${v[event_type]}, ${v[payment_condition_id]}, ${v[reservation_id]}, ${v[actor_id]}, now(), $payload)"
}
pc_json() { echo "'{$1}'::jsonb"; } # the members of the object, spelled out by the caller
pc_sql() { sql "$1" 2>/dev/null || true; }
pc_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" postgres 2>&1 || true)"; printf '%s\n' "$answer"
  check "DP-04 db: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
pc_accepted() { # SQL, description
  local status=0
  engine "begin; $1; rollback;" postgres >/dev/null || status=$?
  check "DP-04 db: $2 is accepted" "$status"
}

echo 'DP-04 db payment parameters changed - base: every changeset that exists before the slice'
liquibase rollback-count 999 >/dev/null
db_labels='!payment-parameters-changed'
liquibase update >/dev/null
pc_base="$(snapshot)"
pc_n0="$(sql "select count(*) from $CONTROL")"
check "the base holds every changeset except the one of the slice ($pc_n0)" "$([ "$pc_n0" -gt 0 ] && [ "$(sql "select count(*) from $CONTROL where labels ilike '%payment-parameters-changed%'")" = 0 ]; echo $?)"
pc_refusal "$(pc_event "$(pc_json "$pc_base_keys")")" 'chk_outbox_event_event_type\|payment_condition_id' 'on that base, a PaymentParametersChanged event'

echo 'DP-04 db payment parameters changed - probes written first: red before the changeset, green after'
db_labels='payment-parameters-changed'
liquibase update >/dev/null
check 'the changeset of the slice adds one changeset (044) to the control table' "$([ "$(sql "select count(*) from $CONTROL")" = "$((pc_n0 + 1))" ]; echo $?)"

echo 'thePaymentParametersChangedEventIsWrittenWithTheChangedRowAsAggregate'
check 'payment_condition_id is a nullable uuid with no DEFAULT and no foreign key' "$([ "$(pc_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='outbox_event' and column_name='payment_condition_id' and data_type='uuid' and is_nullable='YES' and column_default is null")" = 1 ] && [ "$(pc_sql "select count(*) from pg_constraint where conrelid='$pc_ob'::regclass and contype='f' and pg_get_constraintdef(oid) ilike '%payment_condition_id%'")" = 0 ]; echo $?)"
pc_accepted "$(pc_event "$(pc_json "$pc_base_keys,\"serviceId\":\"$pc_svc\"")")" 'a change of a service row with its five keys, the row as aggregate and the administrator as actor'
pc_accepted "$(pc_event "$(pc_json "$pc_base_keys")")" 'a change of the tenant level, which has no service key'
pc_accepted "$(pc_event "$(pc_json "\"tenantId\":\"$tenant\",\"actorId\":\"$actor\",\"paymentType\":\"FULL_PAYMENT\",\"changedAt\":\"2026-11-12T10:00:00Z\"")")" 'a change of the total payment type'
check 'every older event type is still in the list of the table (nothing is removed)' "$([ "$(pc_sql "select count(*) from unnest(array['CatalogServiceInactivated','CatalogServiceReactivated','EstablishmentAssociationPublished','EstablishmentAssociationInactivated','EstablishmentAssociationReactivated','DiscountRuleChanged','ReservationModified','CustomerRegistered','SensitiveDataAccessed','ReservationCreated','PaymentEvidenceRegistered','CapacityAllocated','PaymentValidated','PaymentRejected','ReservationConfirmed','CapacityReleased','ReservationCancelled','ClientNotified','RefundAuthorized','CreditBalanceRecorded','CreditBalanceApplied','SensitiveDataDeleted','ReservationRescheduled','PlatformExceptionalAccessUsed']) t where (select pg_get_constraintdef(oid) from pg_constraint where conrelid='$pc_ob'::regclass and conname='chk_outbox_event_event_type') like '%' || quote_literal(t) || '%'")" = 24 ]; echo $?)"

echo 'theEventRefusesAnythingButItsClosedShape'
pc_refusal "$(pc_event "$(pc_json "$pc_base_keys")" payment_condition_id null)" 'chk_outbox_event_exactly_one_aggregate' 'a change with no aggregate'
pc_refusal "$(pc_event "$(pc_json "$pc_base_keys")" reservation_id "'$pc_res'")" 'chk_outbox_event_exactly_one_aggregate' 'a change that names the row and a reservation'
pc_refusal "$(pc_event "$(pc_json "$pc_base_keys")" event_type "'ReservationModified'")" 'chk_outbox_event_exactly_one_aggregate' 'an event of another type that names a payment condition'
pc_refusal "$(pc_event "$(pc_json "$pc_base_keys")" actor_id null)" 'chk_outbox_event_actor_required' 'a change with no actor'
pc_refusal "$(pc_event "null")" 'chk_outbox_event_payload' 'a change with no payload'
pc_refusal "$(pc_event "$(pc_json "\"tenantId\":\"$tenant\",\"actorId\":\"$actor\",\"paymentType\":\"DEPOSIT\"")")" "$pc_key" 'a change that leaves out the instant'
pc_refusal "$(pc_event "$(pc_json "\"tenantId\":\"$tenant\",\"paymentType\":\"DEPOSIT\",\"changedAt\":\"2026-11-12T10:00:00Z\"")")" "$pc_key" 'a change that leaves out the actor'
pc_refusal "$(pc_event "$(pc_json "$pc_base_keys,\"minimumDepositBp\":3000")")" "$pc_key" 'a change that carries the value of a parameter'
pc_refusal "$(pc_event "$(pc_json "$pc_base_keys,\"reason\":\"a free text\"")")" "$pc_key" 'a change that carries the reason'
pc_refusal "$(pc_event "$(pc_json "\"tenantId\":\"$tenant\",\"actorId\":\"$actor\",\"paymentType\":\"LOAN\",\"changedAt\":\"2026-11-12T10:00:00Z\"")")" "$pc_key" 'a change whose payment type is not one of the two'
pc_refusal "$(pc_event "$(pc_json "$pc_base_keys,\"email\":\"a@b.c\"")")" 'violates check constraint' 'a change that carries a sensitive key'

echo 'onlyThePlannedColumnIsAddedSecondRunAppliesZeroAndRevertLeavesNoTrace'
check 'nothing new appears in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasecha%'")" = 0 ]; echo $?)"
pc_second="$(liquibase update 2>&1)"; printf '%s\n' "$pc_second"
check 'a second update applies zero changesets' "$(printf '%s\n' "$pc_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
echo 'a revert over a database that holds an event of the slice is refused, and the event is kept'
engine "$(pc_event "$(pc_json "$pc_base_keys")")" postgres >/dev/null
pc_refused=1; liquibase rollback-count 1 >/dev/null 2>&1 || pc_refused=0
check 'the revert is refused while a PaymentParametersChanged row exists' "$pc_refused"
check 'the refused revert leaves the changeset and the row in place' "$([ "$(sql "select count(*) from $CONTROL")" = "$((pc_n0 + 1))" ] && [ "$(sql "select count(*) from $pc_ob where event_type='PaymentParametersChanged'")" = 1 ]; echo $?)"
sql "delete from $pc_ob where event_type='PaymentParametersChanged'" >/dev/null
pc_n="$(sql "select count(*) from $CONTROL where labels ilike '%payment-parameters-changed%'" 2>/dev/null || echo 0)"
liquibase rollback-count "$pc_n"
pc_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$pc_base" "$pc_reverted"
check 'the revert restores columns, constraints, indexes and privileges exactly and leaves the base changesets' "$([ -n "$pc_base" ] && [ "$pc_reverted" = "$pc_base" ] && [ "$(sql "select count(*) from $CONTROL")" = "$pc_n0" ]; echo $?)"
db_labels='payment-parameters-changed'
liquibase update >/dev/null
check 'the changeset of the slice reapplies the one changeset of the slice' "$([ "$(sql "select count(*) from $CONTROL")" = "$((pc_n0 + 1))" ]; echo $?)"
