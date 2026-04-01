# Store Health

Assess a store's performance and diagnose issues.

**Trigger:** User asks about a specific store's performance, or wants to compare stores.

**Arguments:** `[store_id or "all"]`

**Tables:** `daily_sales`, `financial_summary`, `customer_feedback`, `waste_log`, `labor_schedule`, `inventory`, `stores`

## Steps

1. Revenue + transaction trend for the store(s)
2. Financial P&L from financial_summary (margin, labor cost %)
3. Customer feedback avg rating + common complaints
4. Waste log totals vs average
5. Labor overtime hours vs average
6. Inventory items below reorder point

## Output Format

- Health score: Strong / Watch / At Risk
- Key metrics in bullets
- Root cause if underperforming (high waste? low traffic? labor issues?)
- Recommendation
