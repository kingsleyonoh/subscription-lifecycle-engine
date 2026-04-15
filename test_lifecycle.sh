#!/bin/bash
# =============================================================================
# SUBSCRIPTION LIFECYCLE ENGINE — Full End-to-End Smoke Test
# =============================================================================
# Tests every major feature with real HTTP calls against a running server.
# Requires: server running on localhost:4000, fresh database with seed tenant.
# =============================================================================

BASE="http://localhost:4000"
PASS=0
FAIL=0
TOTAL=0

check() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"
  local expected="$2"
  local actual="$3"
  if echo "$actual" | grep -q "$expected"; then
    PASS=$((PASS + 1))
    echo "  ✅ $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  ❌ $desc"
    echo "     Expected to contain: $expected"
    echo "     Got: $(echo "$actual" | head -c 200)"
  fi
}

check_status() {
  TOTAL=$((TOTAL + 1))
  local desc="$1"
  local expected_code="$2"
  local actual_code="$3"
  if [ "$actual_code" = "$expected_code" ]; then
    PASS=$((PASS + 1))
    echo "  ✅ $desc (HTTP $actual_code)"
  else
    FAIL=$((FAIL + 1))
    echo "  ❌ $desc (expected HTTP $expected_code, got $actual_code)"
  fi
}

echo ""
echo "==========================================="
echo "  SUBSCRIPTION LIFECYCLE ENGINE"
echo "  Full End-to-End Smoke Test"
echo "==========================================="
echo ""

# -------------------------------------------------------------------
echo "📋 SECTION 1: Health Checks"
echo "-------------------------------------------------------------------"

R=$(curl -s -w "\n%{http_code}" "$BASE/api/health")
BODY=$(echo "$R" | head -1)
CODE=$(echo "$R" | tail -1)
check_status "GET /api/health returns 200" "200" "$CODE"
check "Health shows database connected" "connected" "$BODY"

R=$(curl -s -w "\n%{http_code}" "$BASE/api/health/db")
BODY=$(echo "$R" | head -1)
CODE=$(echo "$R" | tail -1)
check_status "GET /api/health/db returns 200" "200" "$CODE"
check "DB health shows latency" "latencyMs" "$BODY"

R=$(curl -s -w "\n%{http_code}" "$BASE/api/health/ready")
BODY=$(echo "$R" | head -1)
CODE=$(echo "$R" | tail -1)
check_status "GET /api/health/ready returns 200" "200" "$CODE"

# -------------------------------------------------------------------
echo ""
echo "🔐 SECTION 2: Tenant Registration & Auth"
echo "-------------------------------------------------------------------"

R=$(curl -s -w "\n%{http_code}" -X POST "$BASE/api/tenants/register" \
  -H "Content-Type: application/json" \
  -d '{"name": "Acme Corp"}')
BODY=$(echo "$R" | head -1)
CODE=$(echo "$R" | tail -1)
check_status "POST /api/tenants/register returns 201" "201" "$CODE"
check "Registration returns API key" "apiKey" "$BODY"
check "Registration returns tenant name" "Acme Corp" "$BODY"

# Extract API key
API_KEY=$(echo "$BODY" | grep -o '"apiKey":"[^"]*"' | cut -d'"' -f4)
TENANT_ID=$(echo "$BODY" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
echo "     → Tenant ID: $TENANT_ID"
echo "     → API Key: $API_KEY"

R=$(curl -s -w "\n%{http_code}" "$BASE/api/tenants/me" -H "X-API-Key: $API_KEY")
BODY=$(echo "$R" | head -1)
CODE=$(echo "$R" | tail -1)
check_status "GET /api/tenants/me with valid key returns 200" "200" "$CODE"
check "Tenant profile returns name" "Acme Corp" "$BODY"
check "Tenant profile returns isActive" "isActive" "$BODY"

R=$(curl -s -w "\n%{http_code}" "$BASE/api/tenants/me")
CODE=$(echo "$R" | tail -1)
check_status "GET /api/tenants/me without key returns 401" "401" "$CODE"

R=$(curl -s -w "\n%{http_code}" "$BASE/api/tenants/me" -H "X-API-Key: bad_key_123")
CODE=$(echo "$R" | tail -1)
check_status "GET /api/tenants/me with bad key returns 401" "401" "$CODE"

# -------------------------------------------------------------------
echo ""
echo "📦 SECTION 3: Plan Management"
echo "-------------------------------------------------------------------"

R=$(curl -s -w "\n%{http_code}" -X POST "$BASE/api/plans" \
  -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
  -d '{"stripe_price_id":"price_pro_monthly","name":"Pro Monthly","amount_cents":4999,"interval":"month"}')
BODY=$(echo "$R" | head -1)
CODE=$(echo "$R" | tail -1)
check_status "POST /api/plans creates monthly plan" "201" "$CODE"
check "Plan has correct amount" "4999" "$BODY"
PLAN_ID=$(echo "$BODY" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)

R=$(curl -s -w "\n%{http_code}" -X POST "$BASE/api/plans" \
  -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
  -d '{"stripe_price_id":"price_pro_yearly","name":"Pro Yearly","amount_cents":47988,"interval":"year"}')
BODY=$(echo "$R" | head -1)
CODE=$(echo "$R" | tail -1)
check_status "POST /api/plans creates yearly plan" "201" "$CODE"

R=$(curl -s -w "\n%{http_code}" "$BASE/api/plans" -H "X-API-Key: $API_KEY")
BODY=$(echo "$R" | head -1)
CODE=$(echo "$R" | tail -1)
check_status "GET /api/plans returns 200" "200" "$CODE"
check "Plans list contains Pro Monthly" "Pro Monthly" "$BODY"
check "Plans list contains Pro Yearly" "Pro Yearly" "$BODY"

R=$(curl -s -w "\n%{http_code}" -X PUT "$BASE/api/plans/$PLAN_ID" \
  -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
  -d '{"name":"Pro Monthly (Updated)"}')
BODY=$(echo "$R" | head -1)
CODE=$(echo "$R" | tail -1)
check_status "PUT /api/plans/:id updates plan" "200" "$CODE"
check "Plan name updated" "Updated" "$BODY"

# -------------------------------------------------------------------
echo ""
echo "🔔 SECTION 4: Webhook Pipeline — Full Subscription Lifecycle"
echo "-------------------------------------------------------------------"

# Step 1: subscription.created (trialing)
echo "  → Sending: customer.subscription.created (trialing)"
R=$(curl -s -w "\n%{http_code}" -X POST "$BASE/api/webhook-handler" \
  -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
  -d "{\"id\":\"evt_001\",\"type\":\"customer.subscription.created\",\"data\":{\"object\":{\"id\":\"sub_acme_001\",\"customer\":\"cus_acme_001\",\"status\":\"trialing\",\"items\":{\"data\":[{\"price\":{\"id\":\"price_pro_monthly\",\"unit_amount\":4999,\"currency\":\"usd\",\"recurring\":{\"interval\":\"month\"}}}]},\"current_period_start\":1713100000,\"current_period_end\":1715692000,\"trial_start\":1713100000,\"trial_end\":1714309600,\"cancel_at_period_end\":false}}}")
BODY=$(echo "$R" | head -1)
CODE=$(echo "$R" | tail -1)
check_status "Webhook: subscription.created accepted" "200" "$CODE"
check "Webhook returns received:true" "received" "$BODY"

R=$(curl -s "$BASE/api/subscriptions?status=trialing" -H "X-API-Key: $API_KEY")
check "Subscription created in trialing status" "trialing" "$R"
SUB_ID=$(echo "$R" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
echo "     → Subscription ID: $SUB_ID"

R=$(curl -s "$BASE/api/customers" -H "X-API-Key: $API_KEY")
check "Customer auto-created from webhook" "cus_acme_001" "$R"
CUST_ID=$(echo "$R" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

# Step 2: subscription.updated (trialing → active)
echo "  → Sending: customer.subscription.updated (trialing → active)"
R=$(curl -s -w "\n%{http_code}" -X POST "$BASE/api/webhook-handler" \
  -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
  -d "{\"id\":\"evt_002\",\"type\":\"customer.subscription.updated\",\"data\":{\"object\":{\"id\":\"sub_acme_001\",\"customer\":\"cus_acme_001\",\"status\":\"active\",\"items\":{\"data\":[{\"price\":{\"id\":\"price_pro_monthly\",\"unit_amount\":4999,\"currency\":\"usd\",\"recurring\":{\"interval\":\"month\"}}}]},\"current_period_start\":1714309600,\"current_period_end\":1716901600,\"trial_start\":1713100000,\"trial_end\":1714309600,\"cancel_at_period_end\":false},\"previous_attributes\":{\"status\":\"trialing\"}}}")
CODE=$(echo "$R" | tail -1)
check_status "Webhook: subscription.updated accepted" "200" "$CODE"

R=$(curl -s "$BASE/api/subscriptions/$SUB_ID" -H "X-API-Key: $API_KEY")
check "Subscription transitioned to active" "\"status\":\"active\"" "$R"
check "Subscription detail includes customer" "customer" "$R"
check "Subscription detail includes plan" "plan" "$R"

# Step 3: invoice.payment_failed (active → past_due)
echo "  → Sending: invoice.payment_failed"
R=$(curl -s -w "\n%{http_code}" -X POST "$BASE/api/webhook-handler" \
  -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
  -d "{\"id\":\"evt_003\",\"type\":\"invoice.payment_failed\",\"data\":{\"object\":{\"id\":\"in_acme_001\",\"customer\":\"cus_acme_001\",\"subscription\":\"sub_acme_001\",\"status\":\"open\",\"amount_due\":4999,\"amount_paid\":0,\"currency\":\"usd\",\"attempt_count\":1,\"next_payment_attempt\":1714400000,\"hosted_invoice_url\":\"https://pay.stripe.com/invoice/acme\"}}}")
CODE=$(echo "$R" | tail -1)
check_status "Webhook: invoice.payment_failed accepted" "200" "$CODE"

R=$(curl -s "$BASE/api/invoices" -H "X-API-Key: $API_KEY")
check "Invoice created from webhook" "in_acme_001" "$R"
check "Invoice status is open" "open" "$R"

# Step 4: subscription transitions to past_due
echo "  → Sending: customer.subscription.updated (active → past_due)"
R=$(curl -s -w "\n%{http_code}" -X POST "$BASE/api/webhook-handler" \
  -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
  -d "{\"id\":\"evt_004\",\"type\":\"customer.subscription.updated\",\"data\":{\"object\":{\"id\":\"sub_acme_001\",\"customer\":\"cus_acme_001\",\"status\":\"past_due\",\"items\":{\"data\":[{\"price\":{\"id\":\"price_pro_monthly\",\"unit_amount\":4999,\"currency\":\"usd\",\"recurring\":{\"interval\":\"month\"}}}]},\"current_period_start\":1714309600,\"current_period_end\":1716901600,\"cancel_at_period_end\":false},\"previous_attributes\":{\"status\":\"active\"}}}")
CODE=$(echo "$R" | tail -1)
check_status "Webhook: subscription past_due accepted" "200" "$CODE"

R=$(curl -s "$BASE/api/subscriptions/$SUB_ID" -H "X-API-Key: $API_KEY")
check "Subscription is now past_due" "past_due" "$R"

R=$(curl -s "$BASE/api/dunning" -H "X-API-Key: $API_KEY")
check "Dunning attempt created automatically" "pending\|retrying" "$R"

# Step 5: invoice.paid (recovery!)
echo "  → Sending: invoice.paid (recovery)"
R=$(curl -s -w "\n%{http_code}" -X POST "$BASE/api/webhook-handler" \
  -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
  -d "{\"id\":\"evt_005\",\"type\":\"invoice.paid\",\"data\":{\"object\":{\"id\":\"in_acme_001\",\"customer\":\"cus_acme_001\",\"subscription\":\"sub_acme_001\",\"status\":\"paid\",\"amount_due\":4999,\"amount_paid\":4999,\"currency\":\"usd\"}}}")
CODE=$(echo "$R" | tail -1)
check_status "Webhook: invoice.paid accepted" "200" "$CODE"

R=$(curl -s "$BASE/api/invoices" -H "X-API-Key: $API_KEY")
check "Invoice marked as paid" "paid" "$R"

# -------------------------------------------------------------------
echo ""
echo "🔁 SECTION 5: Idempotency"
echo "-------------------------------------------------------------------"

R=$(curl -s "$BASE/api/webhook-handler" -X POST \
  -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
  -d "{\"id\":\"evt_001\",\"type\":\"customer.subscription.created\",\"data\":{\"object\":{\"id\":\"sub_acme_001\",\"customer\":\"cus_acme_001\",\"status\":\"trialing\"}}}")
check "Duplicate event returns duplicate status" "duplicate" "$R"

R=$(curl -s "$BASE/api/webhook-handler" -X POST \
  -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
  -d "{\"id\":\"evt_005\",\"type\":\"invoice.paid\",\"data\":{\"object\":{\"id\":\"in_acme_001\"}}}")
check "Duplicate invoice event also deduped" "duplicate" "$R"

# -------------------------------------------------------------------
echo ""
echo "⏸️  SECTION 6: Subscription Actions (cancel/pause/resume)"
echo "-------------------------------------------------------------------"

# Create a second subscription for action tests
curl -s -X POST "$BASE/api/webhook-handler" \
  -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
  -d "{\"id\":\"evt_010\",\"type\":\"customer.subscription.created\",\"data\":{\"object\":{\"id\":\"sub_acme_002\",\"customer\":\"cus_acme_001\",\"status\":\"active\",\"items\":{\"data\":[{\"price\":{\"id\":\"price_pro_monthly\"}}]},\"current_period_start\":1714309600,\"current_period_end\":1716901600,\"cancel_at_period_end\":false}}}" > /dev/null

R=$(curl -s "$BASE/api/subscriptions?status=active" -H "X-API-Key: $API_KEY")
SUB2_ID=$(echo "$R" | grep -o '"id":"[^"]*"' | tail -1 | cut -d'"' -f4)

R=$(curl -s -w "\n%{http_code}" -X POST "$BASE/api/subscriptions/$SUB2_ID/pause" \
  -H "X-API-Key: $API_KEY" -H "Content-Type: application/json")
BODY=$(echo "$R" | head -1)
CODE=$(echo "$R" | tail -1)
check_status "POST /subscriptions/:id/pause returns 200" "200" "$CODE"
check "Subscription paused successfully" "paused" "$BODY"

R=$(curl -s -w "\n%{http_code}" -X POST "$BASE/api/subscriptions/$SUB2_ID/resume" \
  -H "X-API-Key: $API_KEY" -H "Content-Type: application/json")
BODY=$(echo "$R" | head -1)
CODE=$(echo "$R" | tail -1)
check_status "POST /subscriptions/:id/resume returns 200" "200" "$CODE"
check "Subscription resumed to active" "active" "$BODY"

R=$(curl -s -w "\n%{http_code}" -X POST "$BASE/api/subscriptions/$SUB2_ID/cancel" \
  -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
  -d '{"at_period_end": false}')
BODY=$(echo "$R" | head -1)
CODE=$(echo "$R" | tail -1)
check_status "POST /subscriptions/:id/cancel returns 200" "200" "$CODE"
check "Subscription canceled" "canceled" "$BODY"

# Try to pause a canceled subscription (should fail)
R=$(curl -s -w "\n%{http_code}" -X POST "$BASE/api/subscriptions/$SUB2_ID/pause" \
  -H "X-API-Key: $API_KEY" -H "Content-Type: application/json")
CODE=$(echo "$R" | tail -1)
check_status "Cannot pause canceled subscription (409 or 422)" "409" "$CODE"

# -------------------------------------------------------------------
echo ""
echo "📊 SECTION 7: Events Timeline & Pagination"
echo "-------------------------------------------------------------------"

R=$(curl -s "$BASE/api/subscriptions/$SUB_ID/events" -H "X-API-Key: $API_KEY")
check "Events timeline has entries" "eventType" "$R"
check "Events show subscription.created" "customer.subscription.created" "$R"
check "Events show subscription.updated" "customer.subscription.updated" "$R"
check "Events have cursor pagination" "cursor" "$R"

# Test pagination with limit
R=$(curl -s "$BASE/api/subscriptions/$SUB_ID/events?limit=1" -H "X-API-Key: $API_KEY")
check "Pagination with limit=1 returns hasMore" "hasMore" "$R"

# -------------------------------------------------------------------
echo ""
echo "👤 SECTION 8: Customer & Invoice Detail"
echo "-------------------------------------------------------------------"

R=$(curl -s -w "\n%{http_code}" "$BASE/api/customers/$CUST_ID" -H "X-API-Key: $API_KEY")
BODY=$(echo "$R" | head -1)
CODE=$(echo "$R" | tail -1)
check_status "GET /api/customers/:id returns 200" "200" "$CODE"
check "Customer detail includes subscriptions" "subscriptions" "$BODY"
check "Customer has correct stripe ID" "cus_acme_001" "$BODY"

R=$(curl -s "$BASE/api/invoices" -H "X-API-Key: $API_KEY")
INV_ID=$(echo "$R" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

R=$(curl -s -w "\n%{http_code}" "$BASE/api/invoices/$INV_ID" -H "X-API-Key: $API_KEY")
BODY=$(echo "$R" | head -1)
CODE=$(echo "$R" | tail -1)
check_status "GET /api/invoices/:id returns 200" "200" "$CODE"
check "Invoice detail has stripe ID" "in_acme_001" "$BODY"

# -------------------------------------------------------------------
echo ""
echo "🚫 SECTION 9: Error Handling"
echo "-------------------------------------------------------------------"

R=$(curl -s -w "\n%{http_code}" "$BASE/api/subscriptions/00000000-0000-0000-0000-000000000000" \
  -H "X-API-Key: $API_KEY")
CODE=$(echo "$R" | tail -1)
BODY=$(echo "$R" | head -1)
check_status "Non-existent subscription returns 404" "404" "$CODE"
check "404 has error envelope" "NOT_FOUND" "$BODY"

R=$(curl -s -w "\n%{http_code}" -X POST "$BASE/api/plans" \
  -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
  -d '{}')
CODE=$(echo "$R" | tail -1)
BODY=$(echo "$R" | head -1)
check_status "Validation error returns 400 or 422" "422" "$CODE"
check "Validation error has error details" "error" "$BODY"

R=$(curl -s -w "\n%{http_code}" -X POST "$BASE/api/webhook-handler" \
  -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
  -d 'not json')
CODE=$(echo "$R" | tail -1)
check_status "Malformed JSON returns 400" "400" "$CODE"

# -------------------------------------------------------------------
echo ""
echo "🏢 SECTION 10: Multi-Tenant Isolation"
echo "-------------------------------------------------------------------"

# Register second tenant
R=$(curl -s -X POST "$BASE/api/tenants/register" \
  -H "Content-Type: application/json" \
  -d '{"name": "Evil Corp"}')
API_KEY2=$(echo "$R" | grep -o '"apiKey":"[^"]*"' | cut -d'"' -f4)

# Evil Corp should see ZERO subscriptions
R=$(curl -s "$BASE/api/subscriptions" -H "X-API-Key: $API_KEY2")
check "Tenant isolation: Evil Corp sees 0 subscriptions" "\"data\":\[\]" "$R"

R=$(curl -s "$BASE/api/customers" -H "X-API-Key: $API_KEY2")
check "Tenant isolation: Evil Corp sees 0 customers" "\"data\":\[\]" "$R"

R=$(curl -s "$BASE/api/invoices" -H "X-API-Key: $API_KEY2")
check "Tenant isolation: Evil Corp sees 0 invoices" "\"data\":\[\]" "$R"

R=$(curl -s "$BASE/api/plans" -H "X-API-Key: $API_KEY2")
check "Tenant isolation: Evil Corp sees 0 plans" "\"data\":\[\]" "$R"

# Evil Corp can't access Acme's subscription
R=$(curl -s -w "\n%{http_code}" "$BASE/api/subscriptions/$SUB_ID" -H "X-API-Key: $API_KEY2")
CODE=$(echo "$R" | tail -1)
check_status "Tenant isolation: cross-tenant access returns 404" "404" "$CODE"

# -------------------------------------------------------------------
echo ""
echo "==========================================="
echo "  RESULTS"
echo "==========================================="
echo ""
echo "  Total:  $TOTAL"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""
if [ $FAIL -eq 0 ]; then
  echo "  🎉 ALL TESTS PASSED!"
else
  echo "  ⚠️  $FAIL TESTS FAILED"
fi
echo ""
echo "==========================================="
