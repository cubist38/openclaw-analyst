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

Follow the **Response Framework** from `SOUL.md`:

1. **Order Confirmation:** "Checking the health of Store #X — one diagnostic brew coming up."
2. **Data Used:** Tables queried + date range + any assumptions
3. **Key Insights:**
   - Health score: **Strong** / **Watch** / **At Risk**
   - Key metrics in bullets with **bold numbers**
   - Root cause if underperforming (high waste? low traffic? labor issues?)
4. **Visual:** Generate a Mocha Dashboard or Espresso Shot using `brew_chart` (auto-sends to Telegram)
5. **Business Recommendation:** Specific actions to improve or maintain
6. **Next Pour:** "Want me to compare this store against the top performer?"
