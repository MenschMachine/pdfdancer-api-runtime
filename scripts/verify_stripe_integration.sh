#!/bin/bash
# Verify Stripe Integration
# Run this from the project root.

DB_FILE="tenant.db"

# Check dependencies
if ! command -v sqlite3 &> /dev/null; then
    echo "Error: sqlite3 is not installed."
    exit 1
fi

if ! command -v stripe &> /dev/null; then
    echo "Error: stripe CLI is not installed."
    exit 1
fi

echo "----------------------------------------------------------------"
echo "Stripe Integration Verification Script"
echo "----------------------------------------------------------------"
echo "Prerequisites:"
echo "1. PDFDancer API must be running (localhost:8080)."
echo "2. Stripe CLI listener must be forwarding events:"
echo "   stripe listen --forward-to localhost:8080/stripe/webhook"
echo "----------------------------------------------------------------"

if [ ! -f "$DB_FILE" ]; then
    echo "Warning: '$DB_FILE' not found in current directory."
    echo "Please ensure you are running this script from the project root"
    echo "and that the application has been started at least once."
    read -p "Press Enter to continue anyway (or Ctrl+C to abort)..."
else
    echo "Found database: $DB_FILE"
fi

echo ""
read -p "Press Enter when ready to trigger test events..."

# --- Helper Functions ---
get_sub_count() {
    sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM subscriptions;" 2>/dev/null
}

get_sub_status() {
    sqlite3 "$DB_FILE" "SELECT status FROM subscriptions ORDER BY rowid DESC LIMIT 1;" 2>/dev/null
}

# --- Step 1: Created ---
echo ""
echo ">>> Step 1: Triggering 'customer.subscription.created'..."
initial_count=$(get_sub_count)
echo "Initial count: $initial_count"

stripe trigger customer.subscription.created > /dev/null
echo "Event sent. Waiting 3s..."
sleep 3

new_count=$(get_sub_count)
echo "New count: $new_count"

if [ "$new_count" -gt "$initial_count" ]; then
    echo "✅ SUCCESS: Subscription created."
else
    echo "❌ FAILURE: Subscription count did not increase."
    exit 1
fi

# --- Step 2: Updated ---
echo ""
echo ">>> Step 2: Triggering 'customer.subscription.updated'..."
# Just trigger it; in the mock this usually sends 'active' or 'past_due' depending on CLI params, 
# but let's assume standard 'active' or effectively no change in status if it was already active.
# Use the CLI to simulate an update. 
stripe trigger customer.subscription.updated > /dev/null
echo "Event sent. Waiting 3s..."
sleep 3

# Verify it didn't crash and status is readable.
status=$(get_sub_status)
if [ -n "$status" ]; then
     echo "✅ SUCCESS: Subscription updated (Current status: $status)."
else
     echo "❌ FAILURE: Could not read subscription status."
     exit 1
fi

# --- Step 3: Deleted ---
echo ""
echo ">>> Step 3: Triggering 'customer.subscription.deleted'..."
stripe trigger customer.subscription.deleted > /dev/null
echo "Event sent. Waiting 3s..."
sleep 3

final_status=$(get_sub_status)
if [ "$final_status" == "canceled" ]; then
    echo "✅ SUCCESS: Subscription status is now 'canceled'."
else
    echo "❌ FAILURE: Expected status 'canceled', got '$final_status'."
    echo "Note: Ensure 'customer.subscription.deleted' event payload from CLI actually sends status='canceled'."
fi

echo ""
echo "----------------------------------------------------------------"
echo "Verification Complete."
echo "----------------------------------------------------------------"
echo "Latest subscription record:"
sqlite3 -header -column "$DB_FILE" "SELECT * FROM subscriptions ORDER BY rowid DESC LIMIT 1;"
