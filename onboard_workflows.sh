#!/bin/bash
ENGINE="https://workflows.kingsleyonoh.com"
API_KEY="wae_live_37908c9cbbc1725c2be622e4db744784"
HUB_URL="https://notify.kingsleyonoh.com"
HUB_API_KEY="d2cd62fd0530c9d95b25e1e8845dd3003e825bcd702a085f"

echo "=== Verify tenant ==="
curl -s "$ENGINE/api/tenants/me" -H "X-API-Key: $API_KEY" | grep -o '"name":"[^"]*"'
echo ""

echo ""
echo "=== Workflow 1: subscription-payment-routing (manual trigger) ==="
echo "Routes payment events: invoice.paid -> receipt, invoice.payment_failed -> dunning"
echo ""

W1=$(curl -s -X POST "$ENGINE/api/workflows" \
  -H "X-API-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "subscription-payment-routing",
    "description": "Routes payment events from SLE: invoice.paid sends receipt via Hub, invoice.payment_failed triggers dunning notification",
    "trigger_type": "manual",
    "is_active": true,
    "steps": [
      {
        "id": "check_event_type",
        "type": "condition",
        "config": {
          "expression": "{{ trigger.data.event_type == '"'"'invoice.paid'"'"' }}",
          "true_branch": ["send_receipt"],
          "false_branch": ["send_failure_alert"]
        },
        "depends_on": []
      },
      {
        "id": "send_receipt",
        "type": "http",
        "config": {
          "url": "'"$HUB_URL"'/api/events",
          "method": "POST",
          "headers": {
            "Content-Type": "application/json",
            "X-API-Key": "'"$HUB_API_KEY"'"
          },
          "body": "{\"event_type\": \"payment.receipt\", \"event_id\": \"receipt-{{ trigger.data.invoice_id }}\", \"payload\": { \"customerName\": \"{{ trigger.data.customer_name }}\", \"amount\": \"{{ trigger.data.amount }}\", \"invoiceId\": \"{{ trigger.data.invoice_id }}\" }}"
        },
        "depends_on": ["check_event_type"]
      },
      {
        "id": "send_failure_alert",
        "type": "http",
        "config": {
          "url": "'"$HUB_URL"'/api/events",
          "method": "POST",
          "headers": {
            "Content-Type": "application/json",
            "X-API-Key": "'"$HUB_API_KEY"'"
          },
          "body": "{\"event_type\": \"dunning.payment_failed.first\", \"event_id\": \"dunning-{{ trigger.data.invoice_id }}\", \"payload\": { \"customerName\": \"{{ trigger.data.customer_name }}\", \"amount\": \"{{ trigger.data.amount }}\", \"invoiceUrl\": \"{{ trigger.data.invoice_url }}\" }}"
        },
        "depends_on": ["check_event_type"]
      }
    ]
  }')

W1_ID=$(echo "$W1" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
echo "Created workflow 1: $W1_ID"
echo "$W1" | grep -o '"name":"[^"]*"'

echo ""
echo "=== Workflow 2: subscription-metrics-report (cron: Monday 09:00) ==="
echo "Fetches weekly metrics from SLE API and sends report via Hub"
echo ""

W2=$(curl -s -X POST "$ENGINE/api/workflows" \
  -H "X-API-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "subscription-metrics-report",
    "description": "Weekly Monday 09:00 UTC report: fetches MRR/churn/active metrics from SLE and sends summary via Notification Hub",
    "trigger_type": "cron",
    "trigger_config": {"cron_expression": "0 9 * * 1"},
    "is_active": true,
    "steps": [
      {
        "id": "fetch_metrics",
        "type": "http",
        "config": {
          "url": "https://subscriptions.kingsleyonoh.com/api/metrics/overview",
          "method": "GET",
          "headers": {
            "X-API-Key": "'"$HUB_API_KEY"'"
          }
        },
        "depends_on": []
      },
      {
        "id": "format_report",
        "type": "transform",
        "config": {
          "expression": "MRR: ${{ steps.fetch_metrics.output.body.mrr }} | Active: {{ steps.fetch_metrics.output.body.activeCount }} | Churn: {{ steps.fetch_metrics.output.body.churnRate }}"
        },
        "depends_on": ["fetch_metrics"]
      },
      {
        "id": "send_report",
        "type": "http",
        "config": {
          "url": "'"$HUB_URL"'/api/events",
          "method": "POST",
          "headers": {
            "Content-Type": "application/json",
            "X-API-Key": "'"$HUB_API_KEY"'"
          },
          "body": "{\"event_type\": \"metrics.weekly_report\", \"event_id\": \"weekly-{{ trigger.timestamp }}\", \"payload\": { \"mrr\": \"{{ steps.fetch_metrics.output.body.mrr }}\", \"arr\": \"{{ steps.fetch_metrics.output.body.arr }}\", \"activeCount\": \"{{ steps.fetch_metrics.output.body.activeCount }}\", \"churnRate\": \"{{ steps.fetch_metrics.output.body.churnRate }}\", \"dunningActive\": \"{{ steps.fetch_metrics.output.body.dunningActive }}\" }}"
        },
        "depends_on": ["format_report"]
      }
    ]
  }')

W2_ID=$(echo "$W2" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
echo "Created workflow 2: $W2_ID"
echo "$W2" | grep -o '"name":"[^"]*"'

echo ""
echo "=== Testing workflow 1 (manual trigger) ==="
EXEC=$(curl -s -X POST "$ENGINE/api/workflows/$W1_ID/execute" \
  -H "X-API-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"trigger_data": {"event_type": "invoice.paid", "customer_name": "Test User", "amount": "$29.99", "invoice_id": "in_test_wf"}}')
echo "$EXEC"

echo ""
echo "==========================================="
echo "  WORKFLOW ENGINE ONBOARDING COMPLETE"
echo "==========================================="
echo ""
echo "Workflow 1: subscription-payment-routing"
echo "  ID: $W1_ID"
echo "  Trigger: manual (called from SLE via Ecosystem facade)"
echo "  Steps: condition -> send_receipt OR send_failure_alert"
echo ""
echo "Workflow 2: subscription-metrics-report"
echo "  ID: $W2_ID"
echo "  Trigger: cron (Monday 09:00 UTC)"
echo "  Steps: fetch_metrics -> format_report -> send_report"
echo ""
echo "Env vars to set:"
echo "  WORKFLOW_ENGINE_ENABLED=true"
echo "  WORKFLOW_ENGINE_URL=$ENGINE"
echo "  WORKFLOW_ENGINE_API_KEY=$API_KEY"
echo "  WORKFLOW_PAYMENT_ROUTING_ID=$W1_ID"
echo "  WORKFLOW_METRICS_REPORT_ID=$W2_ID"
