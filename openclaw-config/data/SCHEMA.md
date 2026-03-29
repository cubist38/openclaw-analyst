# Starbucks Business Database Schema

**Location:** `data/starbucks_business.db` (SQLite)

## Tables

| Table | Rows | Description |
|-------|------|-------------|
| regions | 6 | US regions (Pacific_NW, West, Southwest, Midwest, Southeast, Northeast) |
| stores | 50 | Store locations with type (drive-thru/cafe/reserve), city, region |
| employees | ~250 | Staff across stores: baristas, shift supervisors, store/district managers |
| products | 60 | Full menu: espresso, cold brew, frappuccino, tea, refreshers, food, merch, addons |
| suppliers | 20 | Supply chain partners: beans, dairy, syrups, food, packaging, equipment |
| customers | 200 | Rewards members: green/gold/none tiers with lifetime spend |
| daily_sales | 4,500 | Daily revenue per store, Jan-Mar 2026 (50 stores x 90 days) |
| product_sales | 3,900 | Weekly product-level sales by store (sampled) |
| customer_orders | ~1,700 | Individual orders with payment method, mobile flag |
| inventory | 2,400 | Monthly stock snapshots (3 months x 50 stores x 16 items) |
| customer_feedback | 200 | Ratings (1-5) with category (service/quality/speed/cleanliness/app) |
| marketing_campaigns | 15 | Q1 2026 campaigns across email/social/in-store/app channels |
| loyalty_transactions | ~1,300 | Stars earned/redeemed by rewards members |
| labor_schedule | ~15,000 | Shift records with overtime tracking |
| financial_summary | 150 | Monthly P&L by store (revenue, COGS, labor, rent, etc.) |
| store_traffic | 9,100 | Hourly foot traffic with conversion rates |
| waste_log | ~660 | Product waste by reason (expired/damaged/overproduction/quality) |
| delivery_orders | ~500 | Uber Eats/DoorDash orders with delivery time and ratings |
| training_records | ~360 | Employee training completions with scores |
| regional_performance | 12 | Q1 2025 vs Q1 2026 regional comparison with YoY growth |
| menu_pricing_history | ~100 | Price changes with reasons (inflation/promotion/seasonal) |

## Key Relationships

- `stores.region` → `regions.region_name`
- `stores.manager_id` → `employees.employee_id`
- `employees.store_id` → `stores.store_id`
- `daily_sales.store_id` → `stores.store_id`
- `product_sales.product_id` → `products.product_id`
- `customer_orders.customer_id` → `customers.customer_id`
- `inventory.supplier_id` → `suppliers.supplier_id`
- `delivery_orders.customer_id` → `customers.customer_id`

## Data Patterns (for analysis)

- **Top stores** (id 1-10): ~20% higher revenue
- **Struggling stores** (id 46-50): ~30% lower revenue, higher waste, worse feedback
- **Seasonal products** (id 11-13): PSL, Peppermint Mocha, Gingerbread — volume declines Jan→Mar
- **Weekend effect**: Revenue spikes Sat/Sun
- **Monday dip**: Revenue drops ~10%
- **March growth**: ~5% uplift across the board
- **Mobile orders**: Growing trend, higher in March
- **Delivery growth**: Month-over-month increase in delivery volume
- **Gold tier customers**: Order 3-5x more frequently, higher redemption rates
- **Stores 46-50**: Lower ratings in customer feedback (intentional underperformers)
