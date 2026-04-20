# Labor Analysis

Analyze staffing efficiency, overtime, and labor costs.

**Trigger:** User asks about staffing, overtime, labor costs, or scheduling.

**Tables:** `labor_schedule`, `employees`, `daily_sales`, `financial_summary`, `stores`

## Steps

1. Total hours and overtime hours by store from labor_schedule
2. Overtime rate (OT hours / total hours) by store
3. Cross-reference with daily_sales — revenue per labor hour
4. Identify stores with highest overtime %
5. Check if high-overtime stores correlate with high/low revenue
6. Pull labor_cost % from financial_summary

## Output Format

Follow the **Response Framework** from `SOUL.md`:

1. **Order Confirmation:** "One labor analysis — let's check if the shifts are pulling their weight."
2. **Data Used:** Tables queried + date range + store scope
3. **Key Insights** (**bold all numbers**):
   - Fleet-wide overtime rate
   - Top 5 stores by overtime (flag if excessive)
   - Revenue per labor hour comparison
4. **Visual:** Generate an Espresso Shot or Latte Art Heatmap using `brew_chart` (auto-sends to Telegram)
5. **Business Recommendation:** Staffing actions — where to add/cut hours, overtime policy
6. **Next Pour:** "Want me to model the cost impact of reducing overtime by 15%?"
