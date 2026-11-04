#!/usr/bin/env bash
# Sourced by db-ci.sh after the stackable checks, on the same disposable PostgreSQL instance, with the 99 changesets that exist before the story.
# HU-COM-016 -db (issue multi-tour-docs#182), plan D-02: the financial_decision table, one row per 24-running-hour decision. Two changesets in this
# slice, every one labelled HU-COM-016 (the second file of probes, refund-authorization-checks.sh, covers the refund table and the revert).
# Probes are written first: red before the changesets, green after (Annex J.1).
fd_t="$SCHEMA.financial_decision"
fd_cust="$(aid 3401)"; fd_svc="$(aid 3402)"
fd_res1="$(aid 3410)"; fd_res2="$(aid 3411)"; fd_res3="$(aid 3412)"; fd_res4="$(aid 3413)"; fd_res5="$(aid 3414)"
fd_id_cc="$(aid 3420)"; fd_id_pt="$(aid 3421)"; fd_id_rq="$(aid 3422)"; fd_id_me="$(aid 3423)"
fd_sql() { sql "$1" 2>/dev/null || true; }
fd_refusal() { # SQL, text of the engine answer, description
  local answer
  answer="$(engine "$1" 2>&1 || true)"; printf '%s\n' "$answer"
  check "HU-COM-016 db: $3 is refused by $2" "$(printf '%s\n' "$answer" | grep -q "$2"; echo $?)"
}
fd_accepted() { # SQL, description
  local status=0
  engine "$1" >/dev/null || status=$?
  check "HU-COM-016 db: $2 is accepted" "$status"
}
fd_row() { # column/value pairs (SQL literals) that replace the defaults of a valid customer-cancellation decision of the first reservation
  local -A v=([financial_decision_id]="gen_random_uuid()" [tenant_id]="'$tenant'" [reservation_id]="'$fd_res1'" [credit_balance_id]="NULL"
    [decision_kind]="'CUSTOMER_CANCELLATION'" [base_amount_cents]=100000 [penalty_amount_cents]=20000 [recognized_at]="now()" [frozen_at]="NULL"
    [remaining_at_freeze_minutes]="NULL" [outcome]="NULL" [decided_by_system]="NULL" [decided_by]="NULL" [decided_at]="NULL" [rejection_justification]="NULL")
  while [ $# -ge 2 ]; do v[$1]="$2"; shift 2; done
  echo "insert into $fd_t (financial_decision_id, tenant_id, reservation_id, credit_balance_id, decision_kind, base_amount_cents, penalty_amount_cents, recognized_at, frozen_at, remaining_at_freeze_minutes, outcome, decided_by_system, decided_by, decided_at, rejection_justification) values (${v[financial_decision_id]}, ${v[tenant_id]}, ${v[reservation_id]}, ${v[credit_balance_id]}, ${v[decision_kind]}, ${v[base_amount_cents]}, ${v[penalty_amount_cents]}, ${v[recognized_at]}, ${v[frozen_at]}, ${v[remaining_at_freeze_minutes]}, ${v[outcome]}, ${v[decided_by_system]}, ${v[decided_by]}, ${v[decided_at]}, ${v[rejection_justification]})"
}

echo 'HU-COM-016 db - base: the 99 changesets that exist before the story, with the probe reservations'
db_labels='!HU-COM-016'
liquibase update >/dev/null
fd_base="$(snapshot)"
fd_base_objects="$(sql "select (select count(*) from pg_tables where schemaname='$SCHEMA') || '|' || (select count(*) from pg_proc where pronamespace='$SCHEMA'::regnamespace) || '|' || (select count(*) from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace='$SCHEMA'::regnamespace))" 2>/dev/null || true)"
check 'base holds exactly 99 changesets' "$([ "$(sql "select count(*) from $CONTROL")" = 99 ]; echo $?)"
sql "insert into $SCHEMA.customer (customer_id, tenant_id, full_name, created_at, document_number, birth_date_or_age, contact_info, status, terms_accepted, terms_accepted_at) values ('$fd_cust', '$tenant', 'Refund probe A', now(), 'enc:v1:x', 'enc:v1:y', '{}'::jsonb, 'ACTIVE', true, now());
     insert into $SCHEMA.catalog_service (service_id, tenant_id, service_type, commercial_name, catalog_status, base_rate_cents, base_operational_cost_cents, configured_capacity, transport_required, high_risk, created_at, updated_at) values ('$fd_svc', '$tenant', 'TOUR', 'Refund probe tour', 'ACTIVE', 150000, 90000, 12, false, false, now(), now())" >/dev/null 2>&1 || true
engine "$(for r in "$fd_res1" "$fd_res2" "$fd_res3" "$fd_res4" "$fd_res5"; do rs_row reservation_id "'$r'" customer_id "'$fd_cust'" service_id "'$fd_svc'"; echo ';'; done)" >/dev/null || true
check 'the probe reservations exist on the base' "$([ "$(fd_sql "select count(*) from $SCHEMA.reservation where reservation_id in ('$fd_res1','$fd_res2','$fd_res3','$fd_res4','$fd_res5')")" = 5 ]; echo $?)"

echo 'HU-COM-016 db - probes written first: red before the changesets, green after'
db_labels='HU-COM-016'
liquibase update >/dev/null
check 'the changesets of the story bring the control table to 101' "$([ "$(sql "select count(*) from $CONTROL")" = 101 ]; echo $?)"

echo 'aDecisionRequiresEveryFieldAClosedKindAndPositiveAmounts (AC-D16.2)'
fd_accepted "$(fd_row financial_decision_id "'$fd_id_cc'")" 'a whole customer-cancellation decision with its penalty'
fd_refusal "$(fd_row reservation_id NULL);" 'null value in column "reservation_id".*not-null constraint' 'a decision without reservation'
fd_refusal "$(fd_row tenant_id NULL);" 'null value in column "tenant_id".*not-null constraint' 'a decision without tenant'
fd_refusal "$(fd_row decision_kind NULL);" 'null value in column "decision_kind".*not-null constraint' 'a decision without kind'
fd_refusal "$(fd_row base_amount_cents NULL);" 'null value in column "base_amount_cents".*not-null constraint' 'a decision without base amount'
fd_refusal "$(fd_row recognized_at NULL);" 'null value in column "recognized_at".*not-null constraint' 'a decision without recognition instant'
fd_refusal "$(fd_row decision_kind "'REFUND'");" chk_financial_decision_kind 'a kind outside the four codes'
fd_refusal "$(fd_row base_amount_cents 0);" chk_financial_decision_base_positive 'a base amount of zero'
fd_refusal "$(fd_row base_amount_cents -5);" chk_financial_decision_base_positive 'a negative base amount'
fd_refusal "$(fd_row penalty_amount_cents -1);" chk_financial_decision_penalty 'a negative penalty'
fd_refusal "$(fd_row reservation_id "'$(aid 3499)'");" fk_financial_decision_reservation 'a decision for a reservation that does not exist'

echo 'theCreditReferenceAndThePenaltyBelongToTheirKinds (AC-D16.3)'
fd_refusal "$(fd_row decision_kind "'CREDIT_BALANCE_REFUND_REQUEST'" penalty_amount_cents NULL);" chk_financial_decision_credit_reference 'a refund request without a credit-balance reference'
fd_refusal "$(fd_row credit_balance_id "'$(aid 3430)'");" chk_financial_decision_credit_reference 'a credit-balance reference on a customer cancellation'
fd_refusal "$(fd_row decision_kind "'PENDING_TREATMENT'" reservation_id "'$fd_res2'");" chk_financial_decision_penalty 'a penalty on a pending-treatment decision'
fd_accepted "$(fd_row financial_decision_id "'$fd_id_pt'" decision_kind "'PENDING_TREATMENT'" reservation_id "'$fd_res2'" penalty_amount_cents NULL)" 'a pending-treatment decision without penalty'
fd_accepted "$(fd_row decision_kind "'CUSTOMER_CANCELLATION'" reservation_id "'$fd_res5'" penalty_amount_cents NULL)" 'a customer cancellation without penalty'
fd_accepted "$(fd_row financial_decision_id "'$fd_id_me'" decision_kind "'MODIFICATION_EXCESS'" reservation_id "'$fd_res2'" penalty_amount_cents NULL)" 'a modification-excess decision'

echo 'anOutcomeNeedsItsKindItsAuthorAndItsJustificationAndAFreezeIsWhole (AC-D16.4, AC-D16.5)'
fd_refusal "$(fd_row reservation_id "'$fd_res3'" decision_kind "'PENDING_TREATMENT'" penalty_amount_cents NULL outcome "'AUTHORIZED'" decided_by_system true decided_at "now()");" chk_financial_decision_outcome_kind 'AUTHORIZED on a pending-treatment decision'
fd_refusal "$(fd_row reservation_id "'$fd_res3'" decision_kind "'CREDIT_BALANCE_REFUND_REQUEST'" credit_balance_id "'$(aid 3430)'" penalty_amount_cents NULL outcome "'REFUND_FULL'" decided_by_system true decided_at "now()");" chk_financial_decision_outcome_kind 'REFUND_FULL on a refund request'
fd_refusal "$(fd_row outcome "'REFUND_FULL'" decided_by_system true);" chk_financial_decision_decided_coherent 'an outcome without its instant'
fd_refusal "$(fd_row outcome "'REFUND_FULL'" decided_at "now()");" chk_financial_decision_decided_coherent 'an outcome with neither system nor person'
fd_refusal "$(fd_row outcome "'REFUND_FULL'" decided_by_system true decided_by "'$actor'" decided_at "now()");" chk_financial_decision_decided_coherent 'an outcome by the system and by a person at once'
fd_refusal "$(fd_row decided_at "now()");" chk_financial_decision_decided_coherent 'an instant with no outcome'
fd_refusal "$(fd_row decided_by "'$actor'");" chk_financial_decision_decided_coherent 'a person with no outcome'
fd_refusal "$(fd_row reservation_id "'$fd_res3'" decision_kind "'CREDIT_BALANCE_REFUND_REQUEST'" credit_balance_id "'$(aid 3430)'" penalty_amount_cents NULL outcome "'REJECTED'" decided_by_system false decided_by "'$actor'" decided_at "now()");" chk_financial_decision_justification 'REJECTED without a justification'
fd_refusal "$(fd_row reservation_id "'$fd_res3'" decision_kind "'CREDIT_BALANCE_REFUND_REQUEST'" credit_balance_id "'$(aid 3430)'" penalty_amount_cents NULL outcome "'REJECTED'" decided_by_system false decided_by "'$actor'" decided_at "now()" rejection_justification "'   '");" chk_financial_decision_justification 'REJECTED with a blank justification'
fd_refusal "$(fd_row outcome "'REFUND_FULL'" decided_by_system true decided_at "now()" rejection_justification "'because'");" chk_financial_decision_justification 'a justification on an outcome that is not REJECTED'
fd_refusal "$(fd_row frozen_at "now()");" chk_financial_decision_freeze 'a freeze instant without the remaining minutes'
fd_refusal "$(fd_row remaining_at_freeze_minutes 30);" chk_financial_decision_freeze 'remaining minutes without a freeze instant'
fd_refusal "$(fd_row frozen_at "now()" remaining_at_freeze_minutes -1);" chk_financial_decision_freeze 'negative remaining minutes'
fd_accepted "$(fd_row financial_decision_id "'$fd_id_rq'" reservation_id "'$fd_res3'" decision_kind "'CREDIT_BALANCE_REFUND_REQUEST'" credit_balance_id "'$(aid 3430)'" penalty_amount_cents NULL outcome "'REJECTED'" decided_by_system false decided_by "'$actor'" decided_at "now()" rejection_justification "'The balance is not refundable'")" 'a rejected refund request by a person with its justification'
fd_accepted "$(fd_row reservation_id "'$fd_res4'" decision_kind "'PENDING_TREATMENT'" penalty_amount_cents NULL outcome "'CREDIT_FULL'" decided_by_system true decided_at "now()")" 'a credit outcome recorded by the system'
fd_accepted "$(fd_row reservation_id "'$fd_res4'" decision_kind "'MODIFICATION_EXCESS'" penalty_amount_cents NULL frozen_at "now()" remaining_at_freeze_minutes 90)" 'a whole freeze (instant and minutes)'
check 'no column of the decision table has a DEFAULT' "$([ "$(fd_sql "select count(*) from information_schema.columns where table_schema='$SCHEMA' and table_name='financial_decision' and column_default is not null")" = 0 ]; echo $?)"
check 'the application user holds no DELETE on the decision table' "$([ "$(fd_sql "select has_table_privilege('commercial_reservation_app', '$fd_t', 'DELETE')")" = f ]; echo $?)"
