#!/bin/bash
API_KEY="d2cd62fd0530c9d95b25e1e8845dd3003e825bcd702a085f"
HUB="https://notify.kingsleyonoh.com"
RECIPIENT="harrisononh3@gmail.com"

echo "=== Creating 12 templates ==="

create_template() {
  local name="$1" subject="$2" body="$3"
  RESP=$(curl -s -X POST "$HUB/api/templates" \
    -H "X-API-Key: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$name\",\"channel\":\"email\",\"subject\":\"$subject\",\"body\":\"$body\"}")
  TID=$(echo "$RESP" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
  STATUS=$(echo "$RESP" | grep -o '"error"' || echo "ok")
  if [ "$STATUS" = "ok" ]; then
    echo "  OK $name -> $TID"
  else
    echo "  CONFLICT $name (already exists)"
    TID=""
  fi
  echo "$TID"
}

create_rule() {
  local event_type="$1" template_id="$2"
  if [ -z "$template_id" ]; then
    echo "  SKIP rule for $event_type (no template ID)"
    return
  fi
  RESP=$(curl -s -X POST "$HUB/api/rules" \
    -H "X-API-Key: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"event_type\":\"$event_type\",\"channel\":\"email\",\"template_id\":\"$template_id\",\"recipient_type\":\"static\",\"recipient_value\":\"$RECIPIENT\"}")
  RID=$(echo "$RESP" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
  STATUS=$(echo "$RESP" | grep -o '"error"' || echo "ok")
  if [ "$STATUS" = "ok" ]; then
    echo "  RULE $event_type -> email -> $RECIPIENT"
  else
    echo "  RULE SKIP $event_type (already exists)"
  fi
}

# Templates
T1=$(create_template "subscription-created-email" \
  "Welcome! Your subscription is active" \
  "<h2>Welcome!</h2><p>Hi {{customerName}},</p><p>Your subscription to <strong>{{planName}}</strong> has been created. Status: {{status}}</p>")

T2=$(create_template "subscription-trial-ending-email" \
  "Your trial ends soon" \
  "<h2>Trial Ending Soon</h2><p>Hi {{customerName}},</p><p>Your trial for <strong>{{planName}}</strong> ends on {{trialEnd}}. Make sure your payment method is up to date.</p>")

T3=$(create_template "subscription-activated-email" \
  "Subscription activated" \
  "<h2>Subscription Active</h2><p>Hi {{customerName}},</p><p>Your <strong>{{planName}}</strong> subscription is now active. Next billing: {{currentPeriodEnd}}</p>")

T4=$(create_template "subscription-canceled-email" \
  "Subscription canceled" \
  "<h2>Subscription Canceled</h2><p>Hi {{customerName}},</p><p>Your <strong>{{planName}}</strong> subscription has been canceled. You can resubscribe at any time.</p>")

T5=$(create_template "dunning-payment-failed-first-email" \
  "Payment failed - action needed" \
  "<h2>Payment Failed</h2><p>Hi {{customerName}},</p><p>We could not process your payment of <strong>{{amount}}</strong>. Please update your payment method.</p>")

T6=$(create_template "dunning-payment-failed-reminder-email" \
  "Reminder: Payment still failing" \
  "<h2>Payment Reminder</h2><p>Hi {{customerName}},</p><p>Your payment of <strong>{{amount}}</strong> is still outstanding (attempt {{attemptNumber}}/{{maxAttempts}}).</p>")

T7=$(create_template "dunning-payment-failed-urgent-email" \
  "URGENT: Subscription at risk" \
  "<h2>Urgent</h2><p>Hi {{customerName}},</p><p>Your payment has failed <strong>{{attemptNumber}} times</strong>. Your subscription will be canceled soon.</p>")

T8=$(create_template "dunning-payment-failed-final-warning-email" \
  "FINAL WARNING: Subscription will be canceled" \
  "<h2>Final Warning</h2><p>Hi {{customerName}},</p><p>Last chance to update your payment. Amount due: <strong>{{amount}}</strong>. Your subscription will be canceled automatically.</p>")

T9=$(create_template "dunning-recovered-email" \
  "Payment recovered - all set!" \
  "<h2>Payment Recovered!</h2><p>Hi {{customerName}},</p><p>Your payment of <strong>{{amount}}</strong> was processed. Your subscription is active again.</p>")

T10=$(create_template "subscription-churned-email" \
  "[OPERATOR] Subscription churned - {{customerName}}" \
  "<h2>Churn Alert</h2><p><strong>Customer:</strong> {{customerName}} ({{customerEmail}})<br><strong>Plan:</strong> {{planName}}<br><strong>Amount:</strong> {{amountDue}}<br><strong>Attempts:</strong> {{attemptCount}}</p>")

T11=$(create_template "metrics-weekly-report-email" \
  "Weekly Metrics Report" \
  "<h2>Weekly Metrics</h2><p>MRR: {{mrr}} | ARR: {{arr}} | Active: {{activeCount}} | Churn: {{churnRate}} | Dunning: {{dunningActive}}</p>")

T12=$(create_template "__digest" \
  "Subscription Engine Digest - {{count}} notifications" \
  "<h2>Digest</h2>{{#each notifications}}<div style='margin-bottom:12px;padding:8px;border-left:3px solid #007bff'><strong>{{this.subject}}</strong><br>{{{this.body}}}</div>{{/each}}")

echo ""
echo "=== Creating routing rules ==="

# Extract just the ID (last line of create_template output)
get_id() { echo "$1" | tail -1; }

create_rule "subscription.created" "$(get_id "$T1")"
create_rule "subscription.trial_ending" "$(get_id "$T2")"
create_rule "subscription.activated" "$(get_id "$T3")"
create_rule "subscription.canceled" "$(get_id "$T4")"
create_rule "dunning.payment_failed.first" "$(get_id "$T5")"
create_rule "dunning.payment_failed.reminder" "$(get_id "$T6")"
create_rule "dunning.payment_failed.urgent" "$(get_id "$T7")"
create_rule "dunning.payment_failed.final_warning" "$(get_id "$T8")"
create_rule "dunning.recovered" "$(get_id "$T9")"
create_rule "subscription.churned" "$(get_id "$T10")"
create_rule "metrics.weekly_report" "$(get_id "$T11")"

echo ""
echo "=== Sending test event ==="
curl -s -X POST "$HUB/api/events" \
  -H "X-API-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"event_type\":\"subscription.created\",\"event_id\":\"onboard-test-001\",\"payload\":{\"customerName\":\"Test User\",\"planName\":\"Pro Monthly\",\"status\":\"trialing\",\"subscriptionId\":\"sub_test_onboard\"}}"

echo ""
echo ""
echo "=== Checking delivery ==="
sleep 2
curl -s "$HUB/api/notifications?limit=3" -H "X-API-Key: $API_KEY"
echo ""
echo ""
echo "=== DONE ==="
echo "Tenant: Subscription Lifecycle Engine"
echo "API Key: $API_KEY"
echo "Templates: 12"
echo "Rules: 11 (all -> email -> $RECIPIENT)"
