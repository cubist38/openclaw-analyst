# Compare

Side-by-side comparison of any two things.

**Trigger:** User asks to compare two things — stores, regions, products, channels, time periods, delivery partners.

**Arguments:** `[A] vs [B]`

**Tables (pick by comparison type):** `stores` + `daily_sales` (store vs store), `regional_performance` (region vs region), `products` + `product_sales` (product vs product), `marketing_campaigns` (channel vs channel), `delivery_orders` (Uber Eats vs DoorDash)

## Steps

1. Identify what's being compared
2. Pull the same metrics for both sides
3. Calculate absolute and percentage differences
4. Check if the difference is meaningful (sample size matters — flag if <30 data points)
5. Look for confounding factors

## Output Format

Follow the **Response Framework** from `SOUL.md`:

1. **Order Confirmation:** "One side-by-side comparison — let's see how [A] stacks up against [B]."
2. **Data Used:** Tables queried + date range + sample sizes
3. **Key Insights** (**bold all numbers**):
   - Side-by-side comparison in bullets
   - Winner and by how much
   - Caveats (sample size, confounders)
4. **Visual:** Offer an Espresso Shot (grouped bar chart) or Latte Art Heatmap (multi-metric comparison) — see `TECHNICAL_SKILLS.md`
5. **Business Recommendation:** What to do based on the comparison
6. **Next Pour:** "Want me to dig into what's driving the difference?"
