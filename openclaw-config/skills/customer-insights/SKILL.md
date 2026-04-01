# Customer Insights

Analyze customer behavior, loyalty tiers, and spending patterns.

**Trigger:** User asks about customers, loyalty, retention, tiers, or spending behavior.

**Tables:** `customers`, `customer_orders`, `loyalty_transactions`, `delivery_orders`

## Steps

1. Customer count by tier (none/green/gold)
2. Avg order value and frequency by tier
3. Loyalty transaction patterns — stars earned vs redeemed
4. Mobile order adoption rate by tier
5. Top 10 customers by lifetime spend
6. Delivery vs in-store preference by tier

## Output Format

Follow the **Response Framework** from `SOUL.md`:

1. **Order Confirmation:** "Brewing up your customer insights — let's see who's loyal."
2. **Data Used:** Tables queried + customer count + date range
3. **Key Insights** (**bold all numbers**):
   - Tier comparison (bullet format — no tables on Telegram)
   - Key finding: how gold members differ
   - Conversion opportunity: green to gold potential
4. **Visual:** Generate a Cappuccino Cohort or Espresso Shot chart, then **run `data/python3 data/send_photo.py data/<chart>.png "caption"`** to deliver it to Telegram. Do NOT skip the send step.
5. **Business Recommendation:** Loyalty program actions — who to target, how to convert
6. **Next Pour:** "Want me to identify the customers most likely to upgrade to Gold?"
