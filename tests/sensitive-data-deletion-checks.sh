#!/usr/bin/env bash
# Sourced by db-ci.sh after credit-balance-guards-checks.sh, on the same disposable PostgreSQL instance, with the 144 changesets that exist before the story.
# HU-COM-019 -db (issue multi-tour-docs#185), plan D-02 to D-07: the DELETE grant on the two sensitive tables, the append-only sensitive_data_deletion record, the end columns of
# the departure mirror, the outbox shape of SensitiveDataDeleted and the indexes. Every changeset of the story is labelled HU-COM-019. Probes are written first: red before the
# changesets, green after (Annex J.1). The rows of the probes are removed by the owner at the end.
sd_t="$SCHEMA.sensitive_data_deletion"; sd_cs="$SCHEMA.customer_sensitive_data"; sd_ps="$SCHEMA.reservation_companion_sensitive_data"; sd_cap="$SCHEMA.salida_capacity"; sd_ob="$SCHEMA.outbox_event"
sd_tenant_b="00000000-0000-0000-0000-000000000002"
sd_cust="$(aid 7001)"; sd_cust_b="$(aid 7002)"; sd_svc="$(aid 7003)"; sd_res="$(aid 7010)"; sd_res2="$(aid 7011)"; sd_res_b="$(aid 7012)"; sd_comp="$(aid 7020)"
sd_sal1="$(aid 7030)"; sd_sal2="$(aid 7031)"; sd_sal3="$(aid 7032)"; sd_sal4="$(aid 7033)"
sd_sql() { sql "$1" 2>/dev/null || true; }
sd_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-019 db: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
sd_accepted() { # SQL, description
  local status=0
  engine "$1" >/dev/null || status=$?
  check "HU-COM-019 db: $2 is accepted" "$status"
}
sd_as() { # role, statement: the literal answer of the engine to a statement run as a role
  docker exec -e PGPASSWORD "$container" psql -U postgres -d postgres -c "set role $1" -c "$2" 2>&1 || true
}
sd_explain() { printf '%s\n' 'set enable_seqscan = off;' "explain $1;" | docker exec -i -e PGPASSWORD "$container" psql -X -U postgres -d postgres 2>&1 || true; }
sd_row() { # column/value pairs (SQL literals) that replace the defaults of a valid deletion record of the first reservation
  local -A v=([reservation_id]="'$sd_res'" [tenant_id]="'$tenant'" [customer_id]="'$sd_cust'" [anchor_at]="now() - interval '400 days'" [anchor_basis]="'SERVICE_END'"
    [deleted_at]="now()" [customer_data_deleted]="true" [companion_rows_deleted]=1)
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $sd_t (reservation_id, tenant_id, customer_id, anchor_at, anchor_basis, deleted_at, customer_data_deleted, companion_rows_deleted) values (${v[reservation_id]}, ${v[tenant_id]}, ${v[customer_id]}, ${v[anchor_at]}, ${v[anchor_basis]}, ${v[deleted_at]}, ${v[customer_data_deleted]}, ${v[companion_rows_deleted]})"
}
sd_cap_row() { # salida id, status, then column/value pairs for the end columns
  local id="$1" status="$2"; shift 2
  local -A v=([estimated_ends_at]="NULL" [finalized_at]="NULL" [cancelled_at]="NULL")
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $sd_cap (salida_capacity_id, tenant_id, salida_id, service_id, effective_capacity, held_seats, hora_inicio, status, estimated_ends_at, finalized_at, cancelled_at) values (gen_random_uuid(), '$tenant', '$id', '$sd_svc', 10, 0, now(), '$status', ${v[estimated_ends_at]}, ${v[finalized_at]}, ${v[cancelled_at]})"
}
sd_event() { # payload (SQL literal), then column/value pairs that replace the defaults
  local payload="$1"; shift
  local -A v=([reservation_id]="'$sd_res'" [event_type]="'SensitiveDataDeleted'" [actor_id]="NULL")
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $sd_ob (tenant_id, event_type, reservation_id, actor_id, occurred_at, payload) values ('$tenant', ${v[event_type]}, ${v[reservation_id]}, ${v[actor_id]}, now(), $payload)"
}

echo 'HU-COM-019 db - base: the 144 changesets that exist before the story, with the probe rows'
liquibase rollback-count 999 >/dev/null
db_labels='!HU-COM-019 and !HU-COM-018 and !HU-COM-020 and !decision-resume and !episode-frozen-total and !departure-order and !exceptional-access-use and !reservation-confirmed-value and !payment-parameters-changed and !account-session-cutoff and !restricted-access-reason and !rescheduling-proposed-notice'
liquibase update >/dev/null
sd_lines() { sql "select string_agg(x, E'
' order by x) from (
    select 'c:' || table_name || '.' || column_name || ' ' || data_type || ' ' || is_nullable || ' ' || coalesce(column_default, '') as x from information_schema.columns where table_schema = '$SCHEMA'
    union all select 'k:' || conrelid::regclass::text || ' ' || conname || ' ' || pg_get_constraintdef(oid) from pg_constraint where connamespace = '$SCHEMA'::regnamespace
    union all select 'i:' || indexdef from pg_indexes where schemaname = '$SCHEMA'
    union all select 'p:' || grantee || ' ' || table_name || ' ' || privilege_type from information_schema.role_table_grants where table_schema = '$SCHEMA') s" 2>/dev/null || true; }
sd_base="$(snapshot)"; sd_base_lines="$(sd_lines)"
sd_base_objects="$(sql "select (select count(*) from pg_tables where schemaname='$SCHEMA') || '|' || (select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace) || '|' || (select count(*) from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace='$SCHEMA'::regnamespace))" 2>/dev/null || true)"
check 'base holds exactly 144 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 144 ]; echo $?)"
sql "insert into $SCHEMA.customer (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status, terms_accepted, terms_accepted_at) values ('$sd_cust', '$tenant', 'Retention probe A', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now()), ('$sd_cust_b', '$sd_tenant_b', 'Retention probe B', now(), 'enc:v1:x2', 'enc:v1:y2', '{}'::jsonb, 'ACTIVE', true, now());
     insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values ('$sd_svc', '$tenant', 'TOUR', 'Retention probe tour', 'ACTIVE', 150000, 90000, 12, false, false, now(), now())" >/dev/null 2>&1 || true
engine "$(rs_row reservation_id "'$sd_res'" customer_id "'$sd_cust'" service_id "'$sd_svc'"); $(rs_row reservation_id "'$sd_res2'" customer_id "'$sd_cust'" service_id "'$sd_svc'"); $(rs_row reservation_id "'$sd_res_b'" tenant_id "'$sd_tenant_b'" customer_id "'$sd_cust_b'" service_id "'$sd_svc'");" >/dev/null || true
sql "insert into $SCHEMA.reservation_companion (reservation_companion_id, tenant_id, reservation_id, full_name, document_number, birth_date_or_age) values ('$sd_comp', '$tenant', '$sd_res', 'Companion probe', 'DOC7020', 'enc:v1:z');
     insert into $sd_cs (customer_id, tenant_id, emergency_info) values ('$sd_cust', '$tenant', '{}'::jsonb);
     insert into $sd_ps (reservation_companion_id, tenant_id, activity_requirements) values ('$sd_comp', '$tenant', '{}'::jsonb)" >/dev/null 2>&1 || true
check 'the probe reservations, companion and sensitive rows exist on the base' "$([ "$(sd_sql "select (select count(*) from $SCHEMA.reservation where reservation_id in ('$sd_res','$sd_res2','$sd_res_b')) || '|' || (select count(*) from $sd_cs where customer_id = '$sd_cust') || '|' || (select count(*) from $sd_ps where reservation_companion_id = '$sd_comp')")" = '3|1|1' ]; echo $?)"

echo 'HU-COM-019 db - probes written first: red before the changesets, green after'
db_labels='HU-COM-019'
liquibase update >/dev/null
check 'the changesets of the story bring the control table to 153' "$([ "$(sql "select count(*) from $CONTROL")" = 153 ]; echo $?)"

echo 'onlyTheTwoSensitiveTablesGainDelete, theReaderStillCannotSelectTheSensitiveTables (AC-D19.2, AC-D19.3)'
check 'the writer holds DELETE on exactly the two sensitive tables among the tables that had none' "$([ "$(sd_sql "select string_agg(table_name, ',' order by table_name) from information_schema.role_table_grants where table_schema='$SCHEMA' and grantee='commercial_reservation_writer' and privilege_type='DELETE' and table_name in ('customer_sensitive_data','reservation_companion_sensitive_data')")" = 'customer_sensitive_data,reservation_companion_sensitive_data' ]; echo $?)"
sd_refusal "delete from $SCHEMA.customer where customer_id = '$sd_cust';" 'permission denied for table customer' 'a delete of a customer'
sd_refusal "delete from $SCHEMA.reservation where reservation_id = '$sd_res2';" 'permission denied for table reservation' 'a delete of a reservation'
check 'the reader still cannot select the customer sensitive table' "$(sd_as commercial_reservation_reader "select * from $sd_cs" | grep -q 'permission denied'; echo $?)"
check 'the reader still cannot select the companion sensitive table' "$(sd_as commercial_reservation_reader "select * from $sd_ps" | grep -q 'permission denied'; echo $?)"

echo 'deletingSensitiveRowsLeavesTheCustomerAndItsConsentUntouched (AC-D19.7)'
sd_accepted "delete from $sd_ps where reservation_companion_id = '$sd_comp'" 'a delete of the companion sensitive row'
sd_accepted "delete from $sd_cs where customer_id = '$sd_cust'" 'a delete of the customer sensitive row'
check 'the customer and its consent columns are unchanged' "$([ "$(sd_sql "select terms_accepted::text || '|' || (terms_accepted_at is not null)::text from $SCHEMA.customer where customer_id = '$sd_cust'")" = 'true|true' ]; echo $?)"

echo 'deletionRecordRequiresItsFieldsAndAKnownBasis (AC-D19.4)'
sd_accepted "$(sd_row)" 'a whole deletion record'
for column in reservation_id tenant_id customer_id anchor_at anchor_basis deleted_at customer_data_deleted companion_rows_deleted; do
  sd_refusal "$(sd_row reservation_id "'$sd_res2'" "$column" NULL);" "null value in column \"$column\".*not-null constraint" "a record without $column"
done
sd_refusal "$(sd_row reservation_id "'$sd_res2'" anchor_basis "'WHENEVER'");" chk_sensitive_data_deletion_basis 'a basis outside the five codes'
sd_refusal "$(sd_row reservation_id "'$sd_res2'" companion_rows_deleted -1);" chk_sensitive_data_deletion_count 'a negative count'
sd_refusal "$(sd_row reservation_id "'$(aid 7099)'");" fk_sensitive_data_deletion_reservation 'a record for a reservation that does not exist'
for basis in ESTIMATED_END CLOSING CANCELLATION_NO_VALUES CANCELLATION_BLOCKED; do
  sd_accepted "$(sd_row reservation_id "'$sd_res2'" anchor_basis "'$basis'")" "the basis $basis"
  sql "delete from $sd_t where reservation_id = '$sd_res2'" >/dev/null 2>&1 || true
done

echo 'deletionRecordCannotBeUpdatedDeletedOrRepeated (AC-D19.5)'
sd_refusal "update $sd_t set companion_rows_deleted = 9 where reservation_id = '$sd_res';" 'permission denied for table sensitive_data_deletion' 'an update of a record'
sd_refusal "delete from $sd_t where reservation_id = '$sd_res';" 'permission denied for table sensitive_data_deletion' 'a delete of a record'
sd_refusal "$(sd_row);" pk_sensitive_data_deletion 'a second record for the same reservation'

echo 'endColumnsAreCoherentWithTheDepartureStatus (AC-D19.6)'
sd_accepted "$(sd_cap_row "$sd_sal1" SCHEDULED estimated_ends_at "now() + interval '2 days'")" 'a scheduled departure with only the estimated end'
sd_accepted "$(sd_cap_row "$sd_sal2" FINALIZED estimated_ends_at "now() - interval '2 days'" finalized_at "now() - interval '1 day'")" 'a finalized departure with its real end'
sd_accepted "$(sd_cap_row "$sd_sal3" CANCELLED cancelled_at "now()")" 'a cancelled departure with its cancellation instant'
sd_refusal "$(sd_cap_row "$sd_sal4" IN_EXECUTION finalized_at "now()");" chk_salida_capacity_finalized_at_status 'a real end on a departure that is not finalized'
sd_refusal "$(sd_cap_row "$sd_sal4" FINALIZED cancelled_at "now()");" chk_salida_capacity_cancelled_at_status 'a cancellation instant on a departure that is not cancelled'

echo 'recordsAndEndedDeparturesNeverCrossTenants, preFilterAndRecordLookupUseTheirIndexes (AC-D19.8, AC-D19.9)'
sql "insert into $sd_t (reservation_id, tenant_id, customer_id, anchor_at, anchor_basis, deleted_at, customer_data_deleted, companion_rows_deleted) values ('$sd_res_b', '$sd_tenant_b', '$sd_cust_b', now(), 'CLOSING', now(), false, 0)" >/dev/null 2>&1 || true
check 'a read scoped to the first tenant returns none of the records of the second tenant' "$([ "$(sd_sql "select count(*) from $sd_t where tenant_id = '$tenant' and reservation_id = '$sd_res_b'")" = 0 ]; echo $?)"
sd_p1="$(sd_explain "select 1 from $sd_t where tenant_id = '$tenant' order by deleted_at desc limit 20")"; printf '%s\n' "$sd_p1"
check 'the history of the deletions uses idx_sensitive_data_deletion_tenant_deleted_at' "$(printf '%s\n' "$sd_p1" | grep -q 'idx_sensitive_data_deletion_tenant_deleted_at'; echo $?)"
sd_p2="$(sd_explain "select 1 from $sd_cap where tenant_id = '$tenant' and finalized_at is not null and finalized_at < now()")"; printf '%s\n' "$sd_p2"
check 'the finalized departures use idx_salida_capacity_tenant_finalized_at' "$(printf '%s\n' "$sd_p2" | grep -q 'idx_salida_capacity_tenant_finalized_at'; echo $?)"
sd_p3="$(sd_explain "select 1 from $sd_cap where tenant_id = '$tenant' and status not in ('FINALIZED', 'CANCELLED') and estimated_ends_at < now()")"; printf '%s\n' "$sd_p3"
check 'the departures past their estimated end use idx_salida_capacity_tenant_estimated_end' "$(printf '%s\n' "$sd_p3" | grep -q 'idx_salida_capacity_tenant_estimated_end'; echo $?)"
sd_p4="$(sd_explain "select 1 from $sd_cap where tenant_id = '$tenant' and cancelled_at is not null and cancelled_at < now()")"; printf '%s\n' "$sd_p4"
check 'the cancelled departures use idx_salida_capacity_tenant_cancelled_at' "$(printf '%s\n' "$sd_p4" | grep -q 'idx_salida_capacity_tenant_cancelled_at'; echo $?)"

echo 'sensitiveDataDeletedPayloadHasOnlyItsKeyList, theSameKeyTwiceIsRefusedPerTenant (AC-D19.10, AC-D19.11)'
sd_pay='{"reservationId":"r","customerId":"c","anchorBasis":"SERVICE_END","anchorAt":"2025-01-01T00:00:00Z","customerDataDeleted":true,"companionRowsDeleted":1}'
sd_accepted "$(sd_event "'$sd_pay'::jsonb")" 'SensitiveDataDeleted with exactly its six keys and no actor'
sd_refusal "$(sd_event "'{\"reservationId\":\"r\",\"customerId\":\"c\",\"anchorBasis\":\"SERVICE_END\",\"anchorAt\":\"2025-01-01T00:00:00Z\",\"customerDataDeleted\":true,\"companionRowsDeleted\":1,\"fullName\":\"Ana\"}'::jsonb");" 'chk_outbox_event_payload_keys_sensitive_data_deleted' 'SensitiveDataDeleted with a seventh key'
sd_refusal "$(sd_event "'{\"reservationId\":\"r\",\"customerId\":\"c\",\"anchorBasis\":\"SERVICE_END\"}'::jsonb");" 'chk_outbox_event_payload_keys_sensitive_data_deleted' 'SensitiveDataDeleted with missing keys'
sd_refusal "$(sd_event NULL);" chk_outbox_event_payload 'SensitiveDataDeleted without payload'
sd_refusal "$(sd_event "'$sd_pay'::jsonb" reservation_id NULL);" chk_outbox_event_exactly_one_aggregate 'SensitiveDataDeleted without a reservation'
sd_accepted "$(sd_event "'{\"reservationId\":\"x\",\"cause\":\"PAYMENT_EXPIRY\",\"releasedSeats\":2}'::jsonb" event_type "'ReservationCancelled'" actor_id "'$actor'")" 'ReservationCancelled of an earlier story keeps its key list'
sd_key="insert into $SCHEMA.idempotency_key (key, tenant_id, resource_type, resource_id) values ('sensitive-deletion-key-1', '$tenant', 'sensitive_data_deletion', '$sd_res')"
sd_accepted "$sd_key" 'the first registration of a deletion key'
sd_refusal "$sd_key;" pk_idempotency_key 'the same key of the same tenant twice'

echo 'onlyThePlannedObjectsAreAdded, secondRunAppliesZeroAndRevertLeavesNoTrace (AC-D19.1, AC-D19.12)'
sd_objects="$(sql "select (select count(*) from pg_tables where schemaname='$SCHEMA') || '|' || (select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace) || '|' || (select count(*) from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace='$SCHEMA'::regnamespace))" 2>/dev/null || true)"
IFS='|' read -r sd_bt sd_bf sd_bg <<< "$sd_base_objects"
check 'AC-D19.1 exactly one table was added to the base, and no function or trigger' "$([ -n "$sd_base_objects" ] && [ "$sd_objects" = "$((sd_bt + 1))|$sd_bf|$sd_bg" ]; echo $?)"
check 'AC-D19.1 nothing new appears in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasechangelog%'")" = 0 ]; echo $?)"
sd_second="$(liquibase update 2>&1)"; printf '%s\n' "$sd_second"
check 'AC-D19.12 a second update applies zero changesets' "$(printf '%s\n' "$sd_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "delete from $sd_ob where payload ->> 'reservationId' in ('r','x') or reservation_id = '$sd_res'; delete from $SCHEMA.idempotency_key where key = 'sensitive-deletion-key-1'; delete from $sd_t; delete from $sd_cap where salida_id in ('$sd_sal1','$sd_sal2','$sd_sal3','$sd_sal4'); delete from $sd_ps; delete from $sd_cs; delete from $SCHEMA.reservation_companion where reservation_companion_id = '$sd_comp'; delete from $SCHEMA.reservation where reservation_id in ('$sd_res','$sd_res2','$sd_res_b'); delete from $SCHEMA.catalog_service where service_id = '$sd_svc'; delete from $SCHEMA.customer where customer_id in ('$sd_cust','$sd_cust_b')" >/dev/null 2>&1 || true
check 'the rows of the probes are gone before the revert' "$([ "$(sql "select (select count(*) from $sd_t) + (select count(*) from $SCHEMA.reservation where reservation_id in ('$sd_res','$sd_res2','$sd_res_b'))")" = 0 ]; echo $?)"
sd_n="$(sql "select count(*) from $CONTROL where labels ilike '%HU-COM-019%'" 2>/dev/null || echo 0)"
liquibase rollback-count "$sd_n"
sd_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$sd_base" "$sd_reverted"
[ "$sd_base" = "$sd_reverted" ] || diff <(printf '%s
' "$sd_base_lines") <(printf '%s
' "$(sd_lines)") || true
check 'AC-D19.12 the revert restores columns, constraints, indexes and privileges exactly and leaves 144 changesets' "$([ -n "$sd_base" ] && [ "$sd_reverted" = "$sd_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 144 ]; echo $?)"
check 'AC-D19.12 after the revert the delete on the customer sensitive table is refused again' "$(sd_as commercial_reservation_writer "delete from $sd_cs where customer_id = '$sd_cust'" | grep -q 'permission denied'; echo $?)"
db_labels='HU-COM-019'
liquibase update >/dev/null
check 'the changesets of the story reapply to 153' "$([ "$(sql "select count(*) from $CONTROL")" = 153 ]; echo $?)"
