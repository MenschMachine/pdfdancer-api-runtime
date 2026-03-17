#!/bin/bash

# Stripe Integration Test Helper
# Usage: ./test_stripe_events.sh [event_type]
# Prerequisites: stripe cli installed and logged in.
#
# Listens to events:
# stripe listen --forward-to localhost:8080/stripe/webhook

echo "Triggering Stripe Events for Testing..."

if [ -z "$1" ]; then
    echo "No event specified, running standard flow..."
    
    echo "1. Creating customer..."
    # This might not create a subscription, just a customer
    stripe trigger customer.created
    
    echo "2. Creating subscription..."
    stripe trigger customer.subscription.created
    
    echo "3. Updating subscription..."
    stripe trigger customer.subscription.updated
    
    echo "4. Marking invoice paid..."
    stripe trigger invoice.payment_succeeded
    
    echo "5. Deleting subscription..."
    stripe trigger customer.subscription.deleted
    
else
    echo "Triggering specific event: $1"
    stripe trigger $1
fi

echo "Done. Check app logs for 'Received Stripe event' and database for 'subscriptions' updates."
