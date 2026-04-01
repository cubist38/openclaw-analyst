# Trend Analysis

Track how a metric changes over time.

**Trigger:** User asks about trends, growth, changes over time, or "is X getting better/worse?"

**Arguments:** `[metric]` — e.g. revenue, traffic, mobile orders, deliveries, waste

**Tables (pick by metric):** `daily_sales` (revenue, mobile %), `store_traffic` (foot traffic), `delivery_orders` (deliveries), `waste_log` (waste), `product_sales` (product trends), `marketing_campaigns` (campaign timing context)

## Steps

1. Identify the metric (revenue, traffic, mobile orders, deliveries, waste, etc.)
2. Query daily or weekly aggregates over the full date range
3. Calculate week-over-week or month-over-month change
4. Identify inflection points or sudden changes
5. Compare weekday vs weekend if relevant
6. Correlate with known events (campaigns, seasonal shifts)

## Output Format

- Direction: trending up/down/flat
- Rate of change (% per week/month)
- Notable inflection points
- What's driving it (if identifiable)
