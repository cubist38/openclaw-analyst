# Anomaly Scan

Exception reporting — find what needs attention.

**Trigger:** User asks "anything unusual?", "what should I worry about?", or wants exception reporting.

**Tables:** `daily_sales`, `waste_log`, `customer_feedback`, `inventory`, `delivery_orders`, `financial_summary`, `marketing_campaigns`

## Steps

1. Stores with revenue >1.5 stddev below average
2. Products with waste >2x the average
3. Stores with feedback rating <3.0
4. Inventory items at 0 quantity (stockouts)
5. Delivery orders with rating <3.5
6. Stores where labor cost % > 35%
7. Any campaign with negative ROI

## Output Format

- Red flags (needs immediate attention)
- Yellow flags (worth monitoring)
- For each flag: what, where, how bad, suggested action
