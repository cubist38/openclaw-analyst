# Executive Summary

Deliver a high-level business briefing.

**Trigger:** User asks for an overview, summary, "how are we doing", or a briefing.

**Tables:** `daily_sales`, `financial_summary`, `customer_feedback`, `stores`, `regional_performance`

## Steps

1. Query total revenue, transaction count, and avg ticket for the full date range
2. Query month-over-month revenue trend
3. Identify top 5 and bottom 5 stores by revenue
4. Pull net profit margin from financial_summary
5. Check customer feedback avg rating
6. Note any anomalies or standout findings

## Output Format

Follow the **Response Framework** from `SOUL.md`, tailored for briefings:

1. **Order Confirmation:** "One executive brew coming right up — here's your business overview."
2. **Data Used:** List tables queried and date range
3. **Key Insights:**
   - Headline metric (total revenue + trend direction)
   - 3-4 bullet points covering: revenue, profitability, customer satisfaction, one surprise finding
   - **Bold all key numbers**
4. **Visual:** Generate a Mocha Dashboard or Espresso Shot chart, then **run `data/python3 data/send_photo.py data/<chart>.png "caption"`** to deliver it to Telegram. Do NOT skip the send step.
5. **Business Recommendation:** 1-2 actionable recommendations
6. **Next Pour:** Suggest a deeper dive ("Want me to drill into the bottom 5 stores?")
