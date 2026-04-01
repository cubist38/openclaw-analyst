# Starbucks Business Database Schema

**Location:** `data/starbucks_business.db` (SQLite)

## Tables

### regions (6 rows)
US geographic regions with leadership.

| Column | Type | Description |
|--------|------|-------------|
| region_id | INTEGER PK | |
| region_name | TEXT | Pacific_NW, West, Southwest, Midwest, Southeast, Northeast |
| regional_director | TEXT | Director's full name |

### stores (50 rows)
Store locations with type and metadata.

| Column | Type | Description |
|--------|------|-------------|
| store_id | INTEGER PK | |
| store_name | TEXT | e.g. "Starbucks Seattle #1" |
| city | TEXT | |
| state | TEXT | 2-letter code |
| country | TEXT | Always "US" |
| region | TEXT | FK → regions.region_name |
| store_type | TEXT | drive-thru / cafe / reserve |
| open_date | TEXT | YYYY-MM-DD |
| square_feet | INTEGER | 1200-6000 |
| manager_id | INTEGER | FK → employees.employee_id |

### employees (~250 rows)
Staff across all stores: baristas, supervisors, managers.

| Column | Type | Description |
|--------|------|-------------|
| employee_id | INTEGER PK | |
| store_id | INTEGER | FK → stores.store_id (NULL for district managers) |
| first_name | TEXT | |
| last_name | TEXT | |
| role | TEXT | barista / shift_supervisor / store_manager / district_manager |
| hire_date | TEXT | YYYY-MM-DD |
| hourly_rate | REAL | Baristas $14-18, supervisors $17-21, managers $22-42 |
| status | TEXT | active / inactive |
| performance_rating | INTEGER | 1-5 |

### products (60 rows)
Full menu: espresso, cold brew, frappuccino, tea, refreshers, food, merch, addons.

| Column | Type | Description |
|--------|------|-------------|
| product_id | INTEGER PK | |
| product_name | TEXT | |
| category | TEXT | espresso / cold_brew / frappuccino / tea / refreshers / food / merch / addon |
| subcategory | TEXT | hot / iced / seasonal / blended / bakery / sandwich / snack / etc. |
| unit_price | REAL | Customer-facing price |
| cost | REAL | COGS per unit |
| is_seasonal | INTEGER | 0 or 1 (IDs 11-13 and 53 are seasonal) |
| launch_date | TEXT | YYYY-MM-DD |

### suppliers (20 rows)
Supply chain partners.

| Column | Type | Description |
|--------|------|-------------|
| supplier_id | INTEGER PK | |
| supplier_name | TEXT | |
| category | TEXT | coffee_beans / dairy / syrups / food / packaging / tea / equipment / cleaning / ingredients |
| country | TEXT | |
| lead_time_days | INTEGER | |
| reliability_score | INTEGER | 0-100 |
| contract_start | TEXT | YYYY-MM-DD |
| contract_end | TEXT | YYYY-MM-DD |

### customers (200 rows)
Rewards members with tier and spending data.

| Column | Type | Description |
|--------|------|-------------|
| customer_id | INTEGER PK | |
| first_name | TEXT | |
| last_name | TEXT | |
| email | TEXT | |
| city | TEXT | |
| state | TEXT | |
| join_date | TEXT | YYYY-MM-DD |
| rewards_tier | TEXT | none / green / gold |
| lifetime_spend | REAL | Cumulative spend ($50-$8000 depending on tier) |
| visits_last_90_days | INTEGER | none: 1-10, green: 5-25, gold: 15-60 |

### daily_sales (4,500 rows)
Daily revenue per store — 50 stores × 90 days (Jan–Mar 2026).

| Column | Type | Description |
|--------|------|-------------|
| sale_date | TEXT | YYYY-MM-DD |
| store_id | INTEGER | FK → stores.store_id |
| total_revenue | REAL | Daily revenue for that store |
| total_transactions | INTEGER | |
| avg_ticket_size | REAL | revenue / transactions |
| mobile_order_pct | REAL | % of orders via mobile (25-47%) |

### product_sales (3,900 rows)
Weekly product-level sales by store (sampled).

| Column | Type | Description |
|--------|------|-------------|
| week_start | TEXT | YYYY-MM-DD (Monday) |
| store_id | INTEGER | FK → stores.store_id |
| product_id | INTEGER | FK → products.product_id |
| quantity_sold | INTEGER | |
| revenue | REAL | quantity × unit_price |
| discount_amount | REAL | 0-8% of revenue |

### customer_orders (~1,700 rows)
Individual customer orders.

| Column | Type | Description |
|--------|------|-------------|
| order_id | INTEGER PK | |
| customer_id | INTEGER | FK → customers.customer_id |
| store_id | INTEGER | FK → stores.store_id |
| order_date | TEXT | YYYY-MM-DD |
| order_total | REAL | |
| items_count | INTEGER | 1-5 |
| payment_method | TEXT | card / mobile / cash |
| is_mobile_order | INTEGER | 0 or 1 |

### inventory (2,400 rows)
Monthly stock snapshots — 3 months × 50 stores × 16 items.

| Column | Type | Description |
|--------|------|-------------|
| record_id | INTEGER PK | Auto-increment |
| record_date | TEXT | YYYY-MM-01 (first of month) |
| store_id | INTEGER | FK → stores.store_id |
| item_name | TEXT | e.g. "Espresso Beans (kg)", "Whole Milk (gal)" |
| category | TEXT | coffee_beans / dairy / syrups / packaging / food / tea |
| quantity_on_hand | INTEGER | Can be 0 (stockout) |
| reorder_point | INTEGER | Threshold for reordering |
| unit_cost | REAL | |
| supplier_id | INTEGER | FK → suppliers.supplier_id |

### customer_feedback (200 rows)
Customer ratings with category and comments.

| Column | Type | Description |
|--------|------|-------------|
| feedback_id | INTEGER PK | |
| store_id | INTEGER | FK → stores.store_id |
| customer_id | INTEGER | FK → customers.customer_id |
| feedback_date | TEXT | YYYY-MM-DD |
| rating | INTEGER | 1-5 |
| category | TEXT | service / quality / speed / cleanliness / app |
| comment | TEXT | |

### marketing_campaigns (15 rows)
Q1 2026 campaigns across channels.

| Column | Type | Description |
|--------|------|-------------|
| campaign_id | INTEGER PK | |
| campaign_name | TEXT | |
| channel | TEXT | email / social / in-store / app |
| start_date | TEXT | YYYY-MM-DD |
| end_date | TEXT | YYYY-MM-DD |
| budget | REAL | |
| impressions | INTEGER | |
| clicks | INTEGER | NULL for in-store campaigns |
| conversions | INTEGER | |
| revenue_attributed | REAL | |

### loyalty_transactions (~1,300 rows)
Stars earned and redeemed by rewards members (green + gold only).

| Column | Type | Description |
|--------|------|-------------|
| transaction_id | INTEGER PK | |
| customer_id | INTEGER | FK → customers.customer_id |
| transaction_date | TEXT | YYYY-MM-DD |
| stars_earned | INTEGER | ~2× transaction amount |
| stars_redeemed | INTEGER | 0 or 25/50/150/200 (gold only, ~25% chance) |
| reward_type | TEXT | free_drink / free_food / discount / NULL |
| transaction_amount | REAL | |

### labor_schedule (~15,000 rows)
Shift records with overtime tracking.

| Column | Type | Description |
|--------|------|-------------|
| schedule_id | INTEGER PK | |
| store_id | INTEGER | FK → stores.store_id |
| employee_id | INTEGER | FK → employees.employee_id |
| shift_date | TEXT | YYYY-MM-DD |
| shift_start | TEXT | HH:00 |
| shift_end | TEXT | HH:00 |
| hours_worked | REAL | 6-10 hours |
| is_overtime | INTEGER | 1 if hours_worked > 8 |

### financial_summary (150 rows)
Monthly P&L by store — 3 months × 50 stores.

| Column | Type | Description |
|--------|------|-------------|
| month | TEXT | YYYY-MM |
| store_id | INTEGER | FK → stores.store_id |
| revenue | REAL | Derived from daily_sales totals |
| cogs | REAL | 28-35% of revenue |
| labor_cost | REAL | 25-32% of revenue |
| rent | REAL | $8K-$18K/month |
| utilities | REAL | $1.5K-$4K/month |
| marketing_cost | REAL | $500-$3K/month |
| other_expenses | REAL | $1K-$5K/month |
| net_profit | REAL | revenue minus all costs |

### store_traffic (9,100 rows)
Hourly foot traffic with conversion rates (sampled 1 day/week).

| Column | Type | Description |
|--------|------|-------------|
| record_date | TEXT | YYYY-MM-DD |
| store_id | INTEGER | FK → stores.store_id |
| hour_block | TEXT | e.g. "08-09", "12-13" (14 blocks: 06-20) |
| foot_traffic | INTEGER | |
| conversion_rate | REAL | 0.55-0.85 |

### waste_log (~660 rows)
Product waste tracking (sampled 40% of stores/week).

| Column | Type | Description |
|--------|------|-------------|
| log_id | INTEGER PK | |
| log_date | TEXT | YYYY-MM-DD |
| store_id | INTEGER | FK → stores.store_id |
| product_id | INTEGER | FK → products.product_id |
| quantity_wasted | INTEGER | Higher at struggling stores |
| waste_reason | TEXT | expired / damaged / overproduction / quality |
| estimated_cost | REAL | quantity × product cost |

### delivery_orders (~500 rows)
Third-party delivery orders.

| Column | Type | Description |
|--------|------|-------------|
| order_id | INTEGER PK | |
| customer_id | INTEGER | FK → customers.customer_id |
| store_id | INTEGER | FK → stores.store_id |
| order_date | TEXT | YYYY-MM-DD |
| delivery_partner | TEXT | uber_eats / doordash |
| order_total | REAL | $8-$35 |
| delivery_fee | REAL | $2.99-$6.99 |
| delivery_time_min | INTEGER | 15-55 minutes |
| customer_rating | REAL | 3.0-5.0 |

### training_records (~360 rows)
Employee training completions (sampled 60% of employees).

| Column | Type | Description |
|--------|------|-------------|
| record_id | INTEGER PK | |
| employee_id | INTEGER | FK → employees.employee_id |
| training_name | TEXT | e.g. "Barista Basics", "Food Safety Certification" |
| training_type | TEXT | onboarding / safety / barista_cert / leadership / skill / seasonal |
| completion_date | TEXT | YYYY-MM-DD |
| score | REAL | 60-100 |
| duration_hours | REAL | |

### regional_performance (12 rows)
Q1 2025 vs Q1 2026 regional YoY comparison.

| Column | Type | Description |
|--------|------|-------------|
| region | TEXT | FK → regions.region_name |
| quarter | TEXT | e.g. "Q1-2025", "Q1-2026" |
| total_revenue | REAL | |
| store_count | INTEGER | |
| avg_revenue_per_store | REAL | |
| yoy_growth_pct | REAL | NULL for prior year row |
| customer_satisfaction_avg | REAL | 3.7-4.6 |
| employee_turnover_pct | REAL | |

### menu_pricing_history (~100 rows)
Price change history for products.

| Column | Type | Description |
|--------|------|-------------|
| price_id | INTEGER PK | |
| product_id | INTEGER | FK → products.product_id |
| effective_date | TEXT | YYYY-MM-DD |
| old_price | REAL | |
| new_price | REAL | Current price from products table |
| change_reason | TEXT | inflation / promotion / seasonal / cost_adjustment |

## Key Relationships

- `stores.region` → `regions.region_name`
- `stores.manager_id` → `employees.employee_id`
- `employees.store_id` → `stores.store_id`
- `daily_sales.store_id` → `stores.store_id`
- `product_sales.product_id` → `products.product_id`
- `customer_orders.customer_id` → `customers.customer_id`
- `inventory.supplier_id` → `suppliers.supplier_id`
- `delivery_orders.customer_id` → `customers.customer_id`
- `financial_summary.revenue` is derived from `SUM(daily_sales.total_revenue)` per store per month

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
