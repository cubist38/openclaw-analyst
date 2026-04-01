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

Follow the **Response Framework** from `SOUL.md`:

1. **Order Confirmation:** "One pour-over trend coming up — let's see where this metric is heading."
2. **Data Used:** Tables queried + date range + aggregation level
3. **Key Insights** (**bold all numbers**):
   - Direction: trending **up** / **down** / **flat**
   - Rate of change (% per week/month)
   - Notable inflection points
   - What's driving it (if identifiable)
4. **Visual:** Offer a Pour-Over Trend (line chart) or Cold Brew Forecast (with projection) — see `TECHNICAL_SKILLS.md`
5. **Business Recommendation:** What the trend means and what to do about it
6. **Next Pour:** "Want me to forecast where this is heading in the next 13 weeks?"
