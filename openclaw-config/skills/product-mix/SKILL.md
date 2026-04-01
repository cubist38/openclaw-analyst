# Product Mix

Analyze menu performance, margins, and portfolio strategy.

**Trigger:** User asks about products, menu performance, margins, bestsellers, or what to promote.

**Tables:** `product_sales`, `products`, `waste_log`, `menu_pricing_history`

## Steps

1. Top 10 products by revenue from product_sales
2. Top 10 by quantity sold
3. Margin analysis: (price - cost) / price for each product
4. Seasonal product trend (are they declining?)
5. Cross-reference with waste_log — high-waste products
6. Check menu_pricing_history for recent price changes

## Output Format

Follow the **Response Framework** from `SOUL.md`:

1. **Order Confirmation:** "One product mix analysis — let's see what's brewing on the menu."
2. **Data Used:** Tables queried + date range
3. **Key Insights** (BCG matrix style, **bold all numbers**):
   - **Stars** (high revenue + high margin)
   - **Cash cows** (high revenue, lower margin)
   - **Question marks** (low revenue, high margin — undermarketed?)
   - **Dogs** (low revenue, low margin — cut candidates)
4. **Visual:** Generate a Latte Art Heatmap or Espresso Shot chart, then **run `data/python3 data/send_photo.py data/<chart>.png "caption"`** to deliver it to Telegram. Do NOT skip the send step.
5. **Business Recommendation:** Menu strategy — what to promote, what to cut, what to reprice
6. **Next Pour:** "Want me to check how seasonal trends affect these products?"
