# Product Mix

Analyze menu performance, margins, and portfolio strategy.

**Trigger:** User asks about products, menu performance, margins, bestsellers, or what to promote.

## Steps

1. Top 10 products by revenue from product_sales
2. Top 10 by quantity sold
3. Margin analysis: (price - cost) / price for each product
4. Seasonal product trend (are they declining?)
5. Cross-reference with waste_log — high-waste products
6. Check menu_pricing_history for recent price changes

## Output Format

- Stars (high revenue + high margin)
- Cash cows (high revenue, lower margin)
- Question marks (low revenue, high margin — undermarketed?)
- Dogs (low revenue, low margin — cut candidates)
