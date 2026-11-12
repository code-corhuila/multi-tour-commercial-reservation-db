#!/usr/bin/env bash
# Sourced by db-ci.sh after exceptional-access-use-checks.sh, on the same disposable PostgreSQL instance, with every changeset that exists before the slice (counted at run time); the slice is one changeset, 043.
# HU-CSH-003 DP-RM-B3 -db (PDR v1.9 RF-012, "ventas por dia = reservas cuyo valor comercial quedo confirmado en esa fecha"): the closed key list of ReservationConfirmed (04_alter/017) admits one more key,
# commercialValueCents, the final value of the reservation at the instant of its confirmation, as a non-negative whole number of cents. It is allowed and not required, so the rows already stored stay valid; the
# closed list stays closed (nothing else travels) and no other event type changes. The probes run as the superuser with the foreign keys switched off (session_replication_role = replica): the rows reference no real reservation, and the CHECK constraints under test still apply. The changeset is labelled reservation-confirmed-value. Probes are written first: red before the changeset, green after (Annex J.1).
rv_ob="$SCHEMA.outbox_event"; rv_res="$(aid 9201)"
rv_event() { # payload (SQL literal), then column/value pairs that replace the defaults
  local payload="$1"; shift
  local -A v=([event_type]="'ReservationConfirmed'")
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "set session_replication_role = replica; insert into $rv_ob (tenant_id, event_type, reservation_id, actor_id, occurred_at, payload) values ('$tenant', ${v[event_type]}, '$rv_res', '$actor', now(), $payload)"
}
rv_json() { echo "'{$1}'::jsonb"; } # the members of the object, spelled out by the caller
rv_sql() { sql "$1" 2>/dev/null || true; }
rv_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" postgres 2>&1 || true)"; printf '%s\n' "$answer"
  check "DP-RM-B3 db: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
rv_accepted() { # SQL, description
  local status=0
  engine "begin; $1; rollback;" postgres >/dev/null || status=$?
  check "DP-RM-B3 db: $2 is accepted" "$status"
}
rv_key='chk_outbox_event_payload_keys_reservation_confirmed'
rv_base_keys='"reservationId":"x","paymentStatus":"FULLY_PAID"'

echo 'DP-RM-B3 db reservation confirmed value - base: every changeset that exists before the slice'
liquibase rollback-count 999 >/dev/null
db_labels='!reservation-confirmed-value'
liquibase update >/dev/null
rv_base="$(snapshot)"
rv_n0="$(sql "select count(*) from $CONTROL")"
check "the base holds every changeset except the one of the slice ($rv_n0)" "$([ "$rv_n0" -gt 0 ] && [ "$(sql "select count(*) from $CONTROL where labels ilike '%reservation-confirmed-value%'")" = 0 ]; echo $?)"
rv_refusal "$(rv_event "$(rv_json "$rv_base_keys,\"commercialValueCents\":324000")")" "$rv_key" 'on that base, a confirmation that carries commercialValueCents'

echo 'DP-RM-B3 db reservation confirmed value - probes written first: red before the changeset, green after'
db_labels='reservation-confirmed-value'
liquibase update >/dev/null
check 'the changeset of the slice adds one changeset (043) to the control table' "$([ "$(sql "select count(*) from $CONTROL")" = "$((rv_n0 + 1))" ]; echo $?)"

echo 'theConfirmationCarriesTheCommercialValueOfTheReservation'
rv_accepted "$(rv_event "$(rv_json "$rv_base_keys,\"allocatedCapacity\":2,\"commercialValueCents\":324000")")" 'a confirmation with the payment status, the capacity and the commercial value'
rv_accepted "$(rv_event "$(rv_json "$rv_base_keys,\"commercialValueCents\":324000")")" 'a confirmation with the commercial value and no capacity'
rv_accepted "$(rv_event "$(rv_json "$rv_base_keys,\"commercialValueCents\":0")")" 'a confirmation of a reservation whose final value is zero'
rv_accepted "$(rv_event "$(rv_json "$rv_base_keys,\"allocatedCapacity\":2")")" 'a confirmation written before the slice, with no commercial value (additive: stored rows stay valid)'

echo 'theListStaysClosedAndTheValueIsAWholeNumberOfCents'
rv_refusal "$(rv_event "$(rv_json "\"reservationId\":\"x\",\"commercialValueCents\":324000")")" "$rv_key" 'a confirmation without the payment status'
rv_refusal "$(rv_event "$(rv_json "$rv_base_keys,\"commercialValueCents\":324000,\"finalValueCents\":324000")")" "$rv_key" 'a confirmation that carries a second value key'
rv_refusal "$(rv_event "$(rv_json "$rv_base_keys,\"commercialValue\":324000")")" "$rv_key" 'a confirmation whose value is named commercialValue instead of commercialValueCents'
rv_refusal "$(rv_event "$(rv_json "$rv_base_keys,\"commercialValueCents\":-1")")" "$rv_key" 'a negative commercial value'
rv_refusal "$(rv_event "$(rv_json "$rv_base_keys,\"commercialValueCents\":3240.5")")" "$rv_key" 'a commercial value with decimals'
rv_refusal "$(rv_event "$(rv_json "$rv_base_keys,\"commercialValueCents\":\"324000\"")")" "$rv_key" 'a commercial value written as text'
rv_refusal "$(rv_event "$(rv_json "$rv_base_keys,\"commercialValueCents\":null")")" "$rv_key" 'a commercial value that is null'
rv_refusal "$(rv_event "$(rv_json "$rv_base_keys,\"commercialValueCents\":324000,\"email\":\"a@b.c\"")")" 'violates check constraint' 'a confirmation that carries a sensitive key'
rv_refusal "$(rv_event "$(rv_json '"reservationId":"x","amountCents":1000,"paymentStatus":"FULLY_PAID","pendingBalanceCents":0,"validatorId":"v","commercialValueCents":324000')" event_type "'PaymentValidated'")" 'chk_outbox_event_payload_keys_payment_validated' 'a PaymentValidated that borrows commercialValueCents (no other event type changes)'

echo 'onlyTheKeyListChangesSecondRunAppliesZeroAndRevertLeavesNoTrace'
check 'nothing new appears in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasecha%'")" = 0 ]; echo $?)"
check 'the constraint keeps its name' "$([ "$(rv_sql "select count(*) from pg_constraint where conrelid='$rv_ob'::regclass and conname='$rv_key'")" = 1 ]; echo $?)"
rv_second="$(liquibase update 2>&1)"; printf '%s\n' "$rv_second"
check 'a second update applies zero changesets' "$(printf '%s\n' "$rv_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
rv_n="$(sql "select count(*) from $CONTROL where labels ilike '%reservation-confirmed-value%'" 2>/dev/null || echo 0)"
liquibase rollback-count "$rv_n"
rv_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$rv_base" "$rv_reverted"
check 'the revert restores columns, constraints, indexes and privileges exactly and leaves the base changesets' "$([ -n "$rv_base" ] && [ "$rv_reverted" = "$rv_base" ] && [ "$(sql "select count(*) from $CONTROL")" = "$rv_n0" ]; echo $?)"
db_labels='reservation-confirmed-value'
liquibase update >/dev/null
check 'the changeset of the slice reapplies the one changeset of the slice' "$([ "$(sql "select count(*) from $CONTROL")" = "$((rv_n0 + 1))" ]; echo $?)"
