#!/usr/bin/env bash
# Sourced by db-ci.sh after the stackable checks, on the same disposable PostgreSQL instance and with the 103 changesets of the earlier stories applied.
# HU-COM-012 -db (issue multi-tour-docs#178), plan D-02 to D-07: the append-only history of the changes of a reservation, the terms per tour and change
# type, the single pending-difference deadline, the closed key list of the modification event and the revoke. Seven changesets, every one labelled
# HU-COM-012. Probes are written first: red before the changesets, green after (Annex J.1).
md_t="$SCHEMA.reservation_modification"; md_p="$SCHEMA.service_change_policy"; md_dl="$SCHEMA.payment_deadline"; md_ob="$SCHEMA.outbox_event"
md_tenant_b="00000000-0000-0000-0000-000000000002"
md_cust="$(aid 4101)"; md_cust_b="$(aid 4102)"; md_svc="$(aid 4103)"; md_svc2="$(aid 4104)"
md_res1="$(aid 4110)"; md_res2="$(aid 4111)"; md_res_b="$(aid 4112)"
md_sal1="$(aid 4120)"; md_sal2="$(aid 4121)"
md_sql() { sql "$1" 2>/dev/null || true; }
md_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-012 db: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
md_accepted() { # SQL, description
  local status=0
  engine "$1" >/dev/null || status=$?
  check "HU-COM-012 db: $2 is accepted" "$status"
}
md_change() { # column/value pairs (SQL literals) that replace the defaults of a valid MODIFICATION (party 2 -> 3)
  local -A v=([reservation_modification_id]="gen_random_uuid()" [tenant_id]="'$tenant'" [reservation_id]="'$md_res1'" [change_type]="'MODIFICATION'"
    [reason]="'The group grew by one person'" [previous_final_value_cents]=270000 [new_final_value_cents]=405000 [previous_pending_balance_cents]=270000
    [new_pending_balance_cents]=405000 [excess_amount_cents]=0 [previous_party_size]=2 [new_party_size]=3 [previous_service_id]="'$md_svc'"
    [new_service_id]="'$md_svc'" [previous_salida_id]="'$md_sal1'" [new_salida_id]="'$md_sal1'" [registered_by]="'$actor'" [registered_at]="now()")
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  local cols="" vals="" k
  for k in reservation_modification_id tenant_id reservation_id change_type reason previous_final_value_cents new_final_value_cents previous_pending_balance_cents new_pending_balance_cents excess_amount_cents previous_party_size new_party_size previous_service_id new_service_id previous_salida_id new_salida_id registered_by registered_at; do
    cols+="$k, "; vals+="${v[$k]}, "
  done
  echo "insert into $md_t (${cols%, }) values (${vals%, })"
}
md_date() { md_change change_type "'DATE_CHANGE'" new_party_size 2 new_final_value_cents 270000 new_pending_balance_cents 270000 new_salida_id "'$md_sal2'" "$@"; }
md_policy() { # column/value pairs (SQL literals) that replace the defaults of valid terms
  local -A v=([service_change_policy_id]="gen_random_uuid()" [tenant_id]="'$tenant'" [service_id]="'$md_svc'" [change_type]="'MODIFICATION'" [change_allowed]=true [request_lead_minutes]=1440 [changed_by]="'$actor'" [changed_at]="now()")
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $md_p (service_change_policy_id, tenant_id, service_id, change_type, change_allowed, request_lead_minutes, changed_by, changed_at) values (${v[service_change_policy_id]}, ${v[tenant_id]}, ${v[service_id]}, ${v[change_type]}, ${v[change_allowed]}, ${v[request_lead_minutes]}, ${v[changed_by]}, ${v[changed_at]})"
}
md_deadline() { # reservation, kind
  echo "insert into $md_dl (payment_deadline_id, tenant_id, reservation_id, deadline_kind, due_at) values (gen_random_uuid(), '$tenant', '$1', '$2', now() + interval '24 hours')"
}
md_event() { # payload (SQL literal)
  echo "insert into $md_ob (tenant_id, event_type, reservation_id, actor_id, occurred_at, payload) values ('$tenant', 'ReservationModified', '$md_res1', '$actor', now(), $1)"
}
md_explain() { printf '%s\n' 'set enable_seqscan = off;' "explain $1;" | docker exec -i -e PGPASSWORD "$container" psql -X -U postgres -d postgres 2>&1 || true; }

echo 'HU-COM-012 db - base: the 103 changesets that exist before the story'
liquibase rollback-count 999 >/dev/null
db_labels='!HU-COM-012 and !HU-COM-015 and !HU-COM-016'
liquibase update >/dev/null
md_base="$(snapshot)"
md_base_objects="$(sql "select (select count(*) from pg_tables where schemaname='$SCHEMA') || '|' || (select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace) || '|' || (select count(*) from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace='$SCHEMA'::regnamespace))" 2>/dev/null || true)"
check 'base holds exactly 103 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 103 ]; echo $?)"
sql "insert into $SCHEMA.customer (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status, terms_accepted, terms_accepted_at) values ('$md_cust', '$tenant', 'Modification probe A', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now()), ('$md_cust_b', '$md_tenant_b', 'Modification probe B', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now());
     insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values ('$md_svc', '$tenant', 'TOUR', 'Modification probe tour', 'ACTIVE', 150000, 90000, 12, false, false, now(), now()), ('$md_svc2', '$tenant', 'TOUR', 'Modification probe tour two', 'ACTIVE', 150000, 90000, 12, false, false, now(), now())" >/dev/null 2>&1 || true
engine "$(rs_row reservation_id "'$md_res1'" customer_id "'$md_cust'" service_id "'$md_svc'" salida_id "'$md_sal1'"); $(rs_row reservation_id "'$md_res2'" customer_id "'$md_cust'" service_id "'$md_svc'"); $(rs_row reservation_id "'$md_res_b'" tenant_id "'$md_tenant_b'" customer_id "'$md_cust_b'" service_id "'$md_svc'");" >/dev/null || true
check 'the probe reservations exist on the base' "$([ "$(md_sql "select count(*) from $SCHEMA.reservation where reservation_id in ('$md_res1','$md_res2','$md_res_b')")" = 3 ]; echo $?)"

echo 'HU-COM-012 db - probes written first: red before the changesets, green after'
db_labels='HU-COM-012'
liquibase update >/dev/null
check 'the seven changesets of the story bring the control table to 110' "$([ "$(sql "select count(*) from $CONTROL")" = 110 ]; echo $?)"

echo 'historyRequiresEveryFieldAndANonBlankReason (AC-D12.2)'
for md_col in reservation_modification_id tenant_id reservation_id change_type reason previous_final_value_cents new_final_value_cents previous_pending_balance_cents new_pending_balance_cents excess_amount_cents previous_party_size new_party_size previous_service_id new_service_id previous_salida_id new_salida_id registered_by registered_at; do
  md_refusal "$(md_change "$md_col" NULL);" "null value in column \"$md_col\".*not-null constraint" "a history row without $md_col"
done
md_refusal "$(md_change reason "'   '");" chk_reservation_modification_reason 'a history row with a blank reason'
md_refusal "$(md_change reservation_id "'$(aid 4199)'");" fk_reservation_modification_reservation 'a history row of a reservation that does not exist'
md_h1="$(aid 4130)"
md_accepted "$(md_change reservation_modification_id "'$md_h1'")" 'a complete modification row'
check 'AC-D12.2 no column of the history or of the terms has a DEFAULT' "$([ "$(md_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name in ('reservation_modification','service_change_policy') and column_default is not null")" = 0 ]; echo $?)"

echo 'valuesStayInRangeAndTheChangeTypeIsKnown (AC-D12.3)'
md_refusal "$(md_change new_final_value_cents -1);" chk_reservation_modification_values 'a negative final value'
md_refusal "$(md_change new_pending_balance_cents -1);" chk_reservation_modification_values 'a negative pending balance'
md_refusal "$(md_change new_party_size 0);" chk_reservation_modification_values 'a party size below 1'
md_refusal "$(md_change change_type "'REWRITE'");" chk_reservation_modification_type 'an unknown change type'
md_refusal "$(md_change excess_amount_cents 5000 new_pending_balance_cents 1000);" chk_reservation_modification_excess 'an excess with a pending balance above zero'
md_accepted "$(md_change excess_amount_cents 5000 new_pending_balance_cents 0)" 'an excess with nothing pending'

echo 'aDateChangeTouchesTheDepartureOnlyAndAModificationChangesSomething (AC-D12.4)'
md_refusal "$(md_date new_salida_id "'$md_sal1'");" chk_reservation_modification_date_change 'a date change with the same departure'
md_refusal "$(md_date new_party_size 3);" chk_reservation_modification_date_change 'a date change that also changes the party'
md_refusal "$(md_date new_service_id "'$md_svc2'");" chk_reservation_modification_date_change 'a date change that also changes the tour'
md_refusal "$(md_change new_party_size 2 new_final_value_cents 270000 new_pending_balance_cents 270000);" chk_reservation_modification_changes_something 'a modification where nothing changed'
md_accepted "$(md_date)" 'a date change that moves the departure only'
md_accepted "$(md_change new_party_size 2 new_service_id "'$md_svc2'")" 'a modification that changes the tour'

echo 'aHistoryRowCannotBeUpdatedOrDeleted (AC-D12.5)'
md_refusal "update $md_t set reason = 'edited' where reservation_modification_id = '$md_h1';" 'permission denied for table reservation_modification' 'an UPDATE of a history row as the application user'
md_refusal "delete from $md_t where reservation_modification_id = '$md_h1';" 'permission denied for table reservation_modification' 'a DELETE of a history row as the application user'
check 'AC-D12.5 the writer and the application user hold SELECT and INSERT on the history, not UPDATE or DELETE; the reader reads' "$([ "$(sql "select has_table_privilege('$writer','$md_t','SELECT') and has_table_privilege('$writer','$md_t','INSERT') and has_table_privilege('$app','$md_t','INSERT') and not has_table_privilege('$writer','$md_t','UPDATE') and not has_table_privilege('$app','$md_t','UPDATE') and not has_table_privilege('$writer','$md_t','DELETE') and not has_table_privilege('$app','$md_t','DELETE') and has_table_privilege('$reader','$md_t','SELECT')")" = t ]; echo $?)"

echo 'termsNeedTheLeadTimeOnlyWhenAllowedAndEnforceNoList (AC-D12.6)'
for md_col in service_change_policy_id tenant_id service_id change_type change_allowed changed_by changed_at; do
  md_refusal "$(md_policy "$md_col" NULL);" "null value in column \"$md_col\".*not-null constraint" "terms without $md_col"
done
md_refusal "$(md_policy change_type "'  '");" chk_service_change_policy_change_type 'terms with a blank change type'
md_refusal "$(md_policy request_lead_minutes NULL);" chk_service_change_policy_lead 'allowed terms without the lead time'
md_refusal "$(md_policy change_type "'DATE_CHANGE'" change_allowed false);" chk_service_change_policy_lead 'refused terms that carry a lead time'
md_refusal "$(md_policy change_type "'DATE_CHANGE'" request_lead_minutes -5);" chk_service_change_policy_lead 'terms with a negative lead time'
md_refusal "$(md_policy service_id "'$(aid 4198)'");" fk_service_change_policy_service 'terms of a tour that does not exist'
md_accepted "$(md_policy)" 'whole allowed terms'
md_accepted "$(md_policy change_type "'DATE_CHANGE'" change_allowed false request_lead_minutes NULL)" 'refused terms without a lead time'
md_accepted "$(md_policy change_type "'SOME_FUTURE_TYPE'")" 'a change type that is neither wire code (no list is enforced)'

echo 'oneTermsRowPerTenantTourAndType (AC-D12.7)'
md_refusal "$(md_policy);" uq_service_change_policy_tenant_service_type 'a second terms row for the same tenant, tour and type'
md_accepted "$(md_policy service_id "'$md_svc2'")" 'the same type for another tour'

echo 'onlyOnePendingDifferenceDeadlinePerReservation (AC-D12.8)'
md_accepted "$(md_deadline "$md_res1" PENDING_DIFFERENCE)" 'the first pending-difference deadline'
md_refusal "$(md_deadline "$md_res1" PENDING_DIFFERENCE);" uq_payment_deadline_pending_difference_reservation 'a second pending-difference deadline for one reservation'
md_accepted "$(md_deadline "$md_res2" PENDING_DIFFERENCE)" 'a pending-difference deadline of another reservation'
md_accepted "$(md_deadline "$md_res1" BALANCE)" 'a balance deadline next to the pending difference'

echo 'historyAndTermsNeverCrossTenants (AC-D12.9)'
engine "$(md_change tenant_id "'$md_tenant_b'" reservation_id "'$md_res_b'" reason "'Tenant B change'");" >/dev/null || true
engine "$(md_policy tenant_id "'$md_tenant_b'" change_type "'TENANT_B_TYPE'");" >/dev/null || true
check 'AC-D12.9 the history of tenant A never carries the row of tenant B, which exists' "$([ "$(md_sql "select count(*) from $md_t where tenant_id='$tenant' and reason='Tenant B change'")" = 0 ] && [ "$(md_sql "select count(*) from $md_t where tenant_id='$md_tenant_b'")" = 1 ]; echo $?)"
check 'AC-D12.9 the terms of tenant A never carry the type of tenant B, which exists' "$([ "$(md_sql "select count(*) from $md_p where tenant_id='$tenant' and change_type='TENANT_B_TYPE'")" = 0 ] && [ "$(md_sql "select count(*) from $md_p where tenant_id='$md_tenant_b'")" = 1 ]; echo $?)"

echo 'historyAndTermsReadsUseTheirIndexes (AC-D12.10)'
sql "insert into $md_t select gen_random_uuid(), '$tenant', '$md_res2', 'MODIFICATION', 'Bulk change ' || n, 270000, 405000, 270000, 405000, 0, 2, 3, '$md_svc', '$md_svc', '$md_sal1', '$md_sal1', '$actor', now() - (n || ' minutes')::interval from generate_series(1, 3000) n;
     insert into $md_p select gen_random_uuid(), '$tenant', '$md_svc', 'BULK_' || n, true, 60, '$actor', now() from generate_series(1, 3000) n;
     analyze $md_t; analyze $md_p" >/dev/null 2>&1 || true
md_plan_h="$(md_explain "select * from $md_t where tenant_id='$tenant' and reservation_id='$md_res2' order by registered_at desc limit 20")"; printf '%s\n' "$md_plan_h"
check 'AC-D12.10 the history of one reservation uses idx_reservation_modification_tenant_reservation_registered_at' "$(printf '%s\n' "$md_plan_h" | grep -q 'idx_reservation_modification_tenant_reservation_registered_at'; echo $?)"
md_plan_p="$(md_explain "select * from $md_p where tenant_id='$tenant' and service_id='$md_svc' and change_type='BULK_77'")"; printf '%s\n' "$md_plan_p"
check 'AC-D12.10 the terms of one tour and type use uq_service_change_policy_tenant_service_type' "$(printf '%s\n' "$md_plan_p" | grep -q 'uq_service_change_policy_tenant_service_type'; echo $?)"
check 'AC-D12.10 the three indexes lead with tenant_id and the pending-difference one is partial' "$([ "$(md_sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and ((indexname='idx_reservation_modification_tenant_reservation_registered_at' and indexdef like '%(tenant_id, reservation_id, registered_at DESC)%') or (indexname='idx_service_change_policy_tenant_service' and indexdef like '%(tenant_id, service_id)%') or (indexname='uq_payment_deadline_pending_difference_reservation' and indexdef like '%(tenant_id, reservation_id) WHERE (deadline_kind = ''PENDING_DIFFERENCE''%'))")" = 3 ]; echo $?)"

echo 'reservationModifiedPayloadHasOnlyItsKeyListAndTheOldShapeStillPasses (AC-D12.11)'
md_keys='"reservationId":"x","changeType":"MODIFICATION","previousFinalValueCents":270000,"newFinalValueCents":405000,"previousPendingBalanceCents":270000,"newPendingBalanceCents":405000,"partySize":3,"departureChanged":false,"reasonCode":"GROUP_CHANGE"'
md_accepted "$(md_event "'{$md_keys}'::jsonb")" 'ReservationModified with exactly the modification key list'
md_refusal "$(md_event "'{$md_keys,\"customerName\":\"Ana\"}'::jsonb");" chk_outbox_event_payload_keys_reservation_modified_change 'a modification event carrying one extra key'
md_refusal "$(md_event "'{$md_keys,\"reason\":\"The group grew\"}'::jsonb");" chk_outbox_event_payload_keys_reservation_modified_change 'a modification event carrying the free-text reason'
md_refusal "$(md_event "'{\"reservationId\":\"x\",\"changeType\":\"MODIFICATION\"}'::jsonb");" chk_outbox_event_payload_keys_reservation_modified_change 'a modification event with missing keys'
md_accepted "$(md_event "'{\"reason\":\"x\"}'::jsonb")" 'ReservationModified in the old shape of the additional discount'

echo 'theSameKeyTwiceIsRefusedPerTenant (AC-D12.12)'
md_key() { echo "insert into $SCHEMA.idempotency_key (key, tenant_id, resource_type, resource_id) values ('$1', '$2', 'reservation_modification', '$md_h1')"; }
md_accepted "$(md_key modification-key-1 "$tenant")" 'a modification key'
md_refusal "$(md_key modification-key-1 "$tenant");" pk_idempotency_key 'the same key twice in one tenant'
md_accepted "$(md_key modification-key-1 "$md_tenant_b")" 'the same key in another tenant'

echo 'onlyThePlannedObjectsAreAddedAndRevertLeavesNoTrace (AC-D12.1, AC-D12.13)'
md_objects="$(sql "select (select count(*) from pg_tables where schemaname='$SCHEMA') || '|' || (select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace) || '|' || (select count(*) from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace='$SCHEMA'::regnamespace))" 2>/dev/null || true)"
IFS='|' read -r md_bt md_bf md_bg <<< "$md_base_objects"
md_expected="$((md_bt + 2))|$md_bf|$md_bg"
printf 'Base objects (tables|functions|triggers): %s\nExpected: %s\nFound:    %s\n' "$md_base_objects" "$md_expected" "$md_objects"
check 'AC-D12.1 exactly two tables were added to the base, no function and no trigger, and they are the planned ones' "$([ -n "$md_base_objects" ] && [ "$md_objects" = "$md_expected" ] && [ "$(md_sql "select count(*) from pg_tables where schemaname='$SCHEMA' and tablename in ('reservation_modification','service_change_policy')")" = 2 ]; echo $?)"
check 'AC-D12.1 nothing new appears in public' "$([ "$(sql "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p','v','m','S','f') and c.relname not like 'databasechangelog%'")" = 0 ]; echo $?)"
md_second="$(liquibase update 2>&1)"; printf '%s\n' "$md_second"
check 'AC-D12.13 a second update applies zero changesets' "$(printf '%s\n' "$md_second" | grep -Eq 'Run:[[:space:]]+0([^0-9]|$)|up to date|no changesets'; echo $?)"
sql "delete from $SCHEMA.idempotency_key where key = 'modification-key-1'; delete from $md_ob where reservation_id = '$md_res1'; delete from $md_t; delete from $md_p; delete from $md_dl where reservation_id in ('$md_res1','$md_res2','$md_res_b'); delete from $SCHEMA.reservation where reservation_id in ('$md_res1','$md_res2','$md_res_b'); delete from $SCHEMA.catalog_service where service_id in ('$md_svc','$md_svc2'); delete from $SCHEMA.customer where customer_id in ('$md_cust','$md_cust_b')" >/dev/null 2>&1 || true
check 'the rows of the probes are gone before the revert' "$([ "$(sql "select (select count(*) from $md_t) + (select count(*) from $md_p)")" = 0 ]; echo $?)"
liquibase rollback-count 7
md_reverted="$(snapshot)"
printf 'Base MD5: %s\nReverted MD5: %s\n' "$md_base" "$md_reverted"
check 'AC-D12.13 the seven-change revert restores columns, constraints, indexes and privileges exactly and leaves 103 changesets' "$([ -n "$md_base" ] && [ "$md_reverted" = "$md_base" ] && [ "$(sql "select count(*) from $CONTROL")" = 103 ]; echo $?)"
check 'the two tables, the key list and the pending-difference index are gone after the revert' "$([ "$(sql "select count(*) from pg_tables where schemaname='$SCHEMA' and tablename in ('reservation_modification','service_change_policy')")" = 0 ] && [ "$(sql "select count(*) from pg_indexes where schemaname='$SCHEMA' and indexname='uq_payment_deadline_pending_difference_reservation'")" = 0 ] && [ "$(sql "select count(*) from pg_constraint where conname='chk_outbox_event_payload_keys_reservation_modified_change'")" = 0 ]; echo $?)"
db_labels=''
liquibase update >/dev/null
liquibase rollback-count 999 >/dev/null
liquibase update >/dev/null
liquibase validate >/dev/null
check 'a full build from empty without any label filter applies exactly 123 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 123 ]; echo $?)"
