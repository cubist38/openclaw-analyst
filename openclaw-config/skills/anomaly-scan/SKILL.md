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

Follow the **Response Framework** from `SOUL.md`:

1. **Order Confirmation:** "Running the anomaly scan — let's find what needs your attention."
2. **Data Used:** Tables scanned + thresholds used + date range
3. **Key Insights** (**bold all numbers**):
   - **Red flags** (needs immediate attention)
   - **Yellow flags** (worth monitoring)
   - For each flag: what, where, how bad, suggested action
4. **Visual:** Offer a Mocha Dashboard (multi-flag overview) or Espresso Shot (outlier bars) — see `TECHNICAL_SKILLS.md`
5. **Business Recommendation:** Priority actions — what to fix first and why
6. **Next Pour:** "Want me to deep-dive into any of these flags?"
