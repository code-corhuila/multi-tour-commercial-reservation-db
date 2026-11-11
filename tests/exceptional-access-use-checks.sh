#!/usr/bin/env bash
# Sourced by db-ci.sh after departure-order-checks.sh, on the same disposable PostgreSQL instance, with the 180 changesets that exist before the slice.
# HU-SEC-007 G-SEC9-1 -db (ADR-004 D5; Project Lead, 2026-11-11): the ninth widening of outbox_event adds PlatformExceptionalAccessUsed, the audit of each use of the token of an exceptional or
# emergency access. Its aggregate is the authorization of the access (authorization_id), its payload is closed to eight keys and its actor is required. Every changeset of the slice is labelled
# exceptional-access-use. Probes are written first: red before the changeset, green after (Annex J.1). The rows of the probes are rolled back by their own transactions.
ea_ob="$SCHEMA.outbox_event"
ea_auth="$(aid 9101)"; ea_res="$(aid 9102)"
ea_payload="'{\"authorizationId\":\"$ea_auth\",\"platformAdministratorId\":\"$actor\",\"tenantId\":\"$tenant\",\"method\":\"GET\",\"route\":\"/api/v1/commercial-reservation/reservations/{id}\",\"area\":\"RESERVATIONS\",\"occurredAt\":\"2026-11-11T10:00:00Z\",\"correlationId\":\"c-1\"}'::jsonb"
ea_use() { # payload (SQL literal), then column/value pairs that replace the defaults
  local payload="$1"; shift
  local -A v=([event_type]="'PlatformExceptionalAccessUsed'" [authorization_id]="'$ea_auth'" [reservation_id]="null" [actor_id]="'$actor'")
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $ea_ob (tenant_id, event_type, authorization_id, reservation_id, actor_id, occurred_at, payload) values ('$tenant', ${v[event_type]}, ${v[authorization_id]}, ${v[reservation_id]}, ${v[actor_id]}, now(), $payload)"
}
ea_sql() { sql "$1" 2>/dev/null || true; }
ea_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-SEC-007 db: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
ea_accepted() { # SQL, description
  local status=0
  engine "begin; $1; rollback;" >/dev/null || status=$?
  check "HU-SEC-007 db: $2 is accepted" "$status"
}

echo 'HU-SEC-007 db exceptional access use - base: the 180 changesets that exist before the slice'
liquibase rollback-count 999 >/dev/null
db_labels='!exceptional-access-use'
liquibase update >/dev/null
ea_base="$(snapshot)"
check 'base holds exactly 180 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 180 ]; echo $?)"
check 'the base has no authorization_id column' "$([ "$(ea_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='outbox_event' and column_name='authorization_id'")" = 0 ]; echo $?)"

echo 'HU-SEC-007 db exceptional access use - probes written first: red before the changeset, green after'
db_labels='exceptional-access-use'
liquibase update >/dev/null
check 'the changeset of the slice brings the control table to 181' "$([ "$(sql "select count(*) from $CONTROL")" = 181 ]; echo $?)"

echo 'thePlatformExceptionalAccessUsedEventIsWrittenWithItsAuthorizationAsAggregate'
check 'authorization_id is a nullable uuid with no DEFAULT and no foreign key' "$([ "$(ea_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='outbox_event' and column_name='authorization_id' and data_type='uuid' and is_nullable='YES' and column_default is null")" = 1 ] && [ "$(ea_sql "select count(*) from pg_constraint where conrelid='$ea_ob'::regclass and contype='f' and pg_get_constraintdef(oid) ilike '%authorization_id%'")" = 0 ]; echo $?)"
ea_accepted "$(ea_use "$ea_payload")" 'the use of an exceptional access with its eight keys, the authorization as aggregate and the administrator as actor'
ea_accepted "insert into $ea_ob (tenant_id, event_type, reservation_id, actor_id, occurred_at, payload) values ('$tenant', 'ReservationModified', '$ea_res', '$actor', now(), '{\"reason\":\"x\"}'::jsonb)" 'an event of the older types, which still names its reservation'

echo 'theEventRefusesAnythingButItsClosedShape'
ea_refusal "$(ea_use "$ea_payload" authorization_id null)" 'chk_outbox_event_exactly_one_aggregate' 'a use with no aggregate'
ea_refusal "$(ea_use "$ea_payload" reservation_id "'$ea_res'")" 'chk_outbox_event_exactly_one_aggregate' 'a use that names the authorization and a reservation'
ea_refusal "$(ea_use "$ea_payload" event_type "'ReservationModified'")" 'chk_outbox_event_exactly_one_aggregate' 'an event of another type that names an authorization'
ea_refusal "$(ea_use "$ea_payload" actor_id null)" 'chk_outbox_event_actor_required' 'a use with no actor'
ea_refusal "$(ea_use "null")" 'chk_outbox_event_payload' 'a use with no payload'
ea_refusal "$(ea_use "'{\"authorizationId\":\"$ea_auth\",\"platformAdministratorId\":\"$actor\",\"tenantId\":\"$tenant\",\"method\":\"GET\",\"route\":\"/x\",\"area\":\"CASH\",\"occurredAt\":\"2026-11-11T10:00:00Z\"}'::jsonb")" 'chk_outbox_event_payload_keys_platform_exceptional_access_used' 'a use that leaves out the correlationId'
ea_refusal "$(ea_use "'{\"authorizationId\":\"$ea_auth\",\"platformAdministratorId\":\"$actor\",\"tenantId\":\"$tenant\",\"method\":\"GET\",\"route\":\"/x\",\"area\":\"CASH\",\"occurredAt\":\"2026-11-11T10:00:00Z\",\"correlationId\":\"c\",\"responseBody\":\"x\"}'::jsonb")" 'chk_outbox_event_payload_keys_platform_exceptional_access_used' 'a use that carries a key of the response'
ea_refusal "$(ea_use "'{\"authorizationId\":\"$ea_auth\",\"platformAdministratorId\":\"$actor\",\"tenantId\":\"$tenant\",\"method\":\"GET\",\"route\":\"/x\",\"area\":\"CASH\",\"occurredAt\":\"2026-11-11T10:00:00Z\",\"correlationId\":\"c\",\"email\":\"a@b.c\"}'::jsonb")" 'violates check constraint' 'a use that carries a sensitive key'

echo 'onlyThePlannedColumnIsAddedSecondRunAppliesZeroAndRevertLeavesNoTrace'
check 'nothing new appears in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasecha%'")" = 0 ]; echo $?)"
ea_second="$(liquibase update 2>&1)"; printf '%s\n' "$ea_second"
check 'a second update applies zero changesets' "$(printf '%s\n' "$ea_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
ea_n="$(sql "select count(*) from $CONTROL where labels ilike '%exceptional-access-use%'" 2>/dev/null || echo 0)"
liquibase rollback-count "$ea_n"
ea_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$ea_base" "$ea_reverted"
check 'the revert restores columns, constraints, indexes and privileges exactly and leaves 180 changesets' "$([ -n "$ea_base" ] && [ "$ea_reverted" = "$ea_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 180 ]; echo $?)"
db_labels='exceptional-access-use'
liquibase update >/dev/null
check 'the changeset of the slice reapplies to 181' "$([ "$(sql "select count(*) from $CONTROL")" = 181 ]; echo $?)"
