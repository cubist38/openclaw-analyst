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

- Headline metric (total revenue + trend direction)
- 3-4 bullet points covering: revenue, profitability, customer satisfaction, one surprise finding
- Close with 1-2 actionable recommendations
