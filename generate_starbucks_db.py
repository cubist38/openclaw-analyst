#!/usr/bin/env python3
"""
Generate a realistic Starbucks business intelligence SQLite database.
21 tables with interconnected data for analyst testing.

Configuration is loaded from configs/config.yaml — adjust num_stores,
num_customers, date_range, regions, etc. to control the generated data.
"""

import sqlite3
import random
import os
import sys
from datetime import datetime, timedelta
from math import ceil

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML is required. Install it with: pip install pyyaml")
    sys.exit(1)

# ---------- config ----------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(SCRIPT_DIR, "configs", "config.yaml")

def load_config():
    if not os.path.exists(CONFIG_PATH):
        print(f"ERROR: Config file not found at {CONFIG_PATH}")
        sys.exit(1)
    with open(CONFIG_PATH) as f:
        return yaml.safe_load(f)

CFG = load_config()

random.seed(CFG.get("seed", 42))

# Resolve DB path
db_path_override = CFG.get("db_path", "")
if db_path_override:
    DB_PATH = os.path.expanduser(db_path_override)
    DB_DIR = os.path.dirname(DB_PATH)
else:
    DB_DIR = os.path.expanduser("~/.openclaw/workspace/data")
    DB_PATH = os.path.join(DB_DIR, "starbucks_business.db")
os.makedirs(DB_DIR, exist_ok=True)

# Scale parameters
NUM_STORES = CFG.get("num_stores", 50)
NUM_CUSTOMERS = CFG.get("num_customers", 200)
NUM_FEEDBACK = CFG.get("num_feedback", 200)
NUM_DISTRICT_MANAGERS = CFG.get("num_district_managers", 6)
EMP_CFG = CFG.get("employees_per_store", {})
BARISTAS_MIN = EMP_CFG.get("baristas_min", 2)
BARISTAS_MAX = EMP_CFG.get("baristas_max", 4)

# Date range
dr = CFG.get("date_range", {})
DATE_START = datetime.strptime(dr.get("start", "2026-01-01"), "%Y-%m-%d")
DATE_END = datetime.strptime(dr.get("end", "2026-03-31"), "%Y-%m-%d")
TOTAL_DAYS = (DATE_END - DATE_START).days + 1
NUM_WEEKS = ceil(TOTAL_DAYS / 7)

# Build months list from date range (for inventory, financial_summary)
def get_months(start, end):
    """Return list of 'YYYY-MM' strings covering the date range."""
    months = []
    current = start.replace(day=1)
    while current <= end:
        months.append(current.strftime("%Y-%m"))
        if current.month == 12:
            current = current.replace(year=current.year + 1, month=1)
        else:
            current = current.replace(month=current.month + 1)
    return months

# Build month start dates for inventory snapshots
def get_month_starts(start, end):
    """Return list of 'YYYY-MM-01' strings covering the date range."""
    dates = []
    current = start.replace(day=1)
    while current <= end:
        dates.append(current.strftime("%Y-%m-%d"))
        if current.month == 12:
            current = current.replace(year=current.year + 1, month=1)
        else:
            current = current.replace(month=current.month + 1)
    return dates

MONTHS = get_months(DATE_START, DATE_END)
MONTH_STARTS = get_month_starts(DATE_START, DATE_END)

# Regions from config
def build_cities_list(cfg):
    """Build flat list of (city, state, region) from config."""
    cities = []
    for region in cfg.get("regions", []):
        rname = region["name"]
        for c in region.get("cities", []):
            cities.append((c["city"], c["state"], rname))
    return cities

REGIONS_CFG = CFG.get("regions", [])
REGION_NAMES = [r["name"] for r in REGIONS_CFG]
CITIES_STATES = build_cities_list(CFG)

if not CITIES_STATES:
    print("ERROR: No cities defined in config. Add at least one region with cities.")
    sys.exit(1)

# Thresholds for store performance (proportional to num_stores)
TOP_STORE_THRESHOLD = max(1, int(NUM_STORES * 0.2))       # top 20%
STRUGGLING_STORE_START = max(TOP_STORE_THRESHOLD + 1, NUM_STORES - max(1, int(NUM_STORES * 0.1)) + 1)  # bottom 10%

# ---------- helpers ----------
def rand_date(start, end):
    delta = (end - start).days
    if delta <= 0:
        return start
    return start + timedelta(days=random.randint(0, delta))

def rand_time(h_min, h_max):
    h = random.randint(h_min, h_max)
    m = random.choice([0, 15, 30, 45])
    return f"{h:02d}:{m:02d}"

FIRST_NAMES = [
    "James","Emma","Liam","Olivia","Noah","Ava","Sophia","Jackson","Mia","Lucas",
    "Isabella","Aiden","Charlotte","Ethan","Amelia","Mason","Harper","Logan","Evelyn","Alexander",
    "Luna","Daniel","Chloe","Henry","Ella","Sebastian","Grace","Jack","Victoria","Owen",
    "Riley","Samuel","Aria","Benjamin","Lily","Leo","Zoey","Mateo","Nora","William",
    "Hannah","Elijah","Addison","Jayden","Eleanor","Carter","Stella","Dylan","Violet","Gabriel"
]
LAST_NAMES = [
    "Smith","Johnson","Williams","Brown","Jones","Garcia","Miller","Davis","Rodriguez","Martinez",
    "Hernandez","Lopez","Gonzalez","Wilson","Anderson","Thomas","Taylor","Moore","Jackson","Martin",
    "Lee","Perez","Thompson","White","Harris","Sanchez","Clark","Ramirez","Lewis","Robinson",
    "Walker","Young","Allen","King","Wright","Scott","Torres","Nguyen","Hill","Flores"
]

PRODUCT_CATALOG = [
    # (name, category, subcategory, price, cost, is_seasonal)
    ("Caffe Americano","espresso","hot",3.75,0.85,0),
    ("Caffe Latte","espresso","hot",4.95,1.10,0),
    ("Cappuccino","espresso","hot",4.75,1.05,0),
    ("Caramel Macchiato","espresso","hot",5.45,1.20,0),
    ("Flat White","espresso","hot",4.95,1.15,0),
    ("Espresso","espresso","hot",2.45,0.55,0),
    ("Blonde Vanilla Latte","espresso","hot",5.25,1.10,0),
    ("Iced Caffe Latte","espresso","iced",5.25,1.15,0),
    ("Iced Caramel Macchiato","espresso","iced",5.75,1.25,0),
    ("Iced Brown Sugar Oatmilk Shaken Espresso","espresso","iced",5.95,1.30,0),
    ("Pumpkin Spice Latte","espresso","seasonal",6.25,1.35,1),
    ("Peppermint Mocha","espresso","seasonal",6.15,1.40,1),
    ("Gingerbread Latte","espresso","seasonal",6.25,1.45,1),
    ("Vanilla Sweet Cream Cold Brew","cold_brew","iced",5.45,0.95,0),
    ("Cold Brew Coffee","cold_brew","iced",4.75,0.80,0),
    ("Nitro Cold Brew","cold_brew","iced",5.25,0.90,0),
    ("Salted Caramel Cream Cold Brew","cold_brew","iced",5.75,1.00,0),
    ("Java Chip Frappuccino","frappuccino","blended",5.95,1.50,0),
    ("Caramel Frappuccino","frappuccino","blended",5.75,1.45,0),
    ("Mocha Frappuccino","frappuccino","blended",5.75,1.45,0),
    ("Strawberry Creme Frappuccino","frappuccino","blended",5.45,1.40,0),
    ("Vanilla Bean Frappuccino","frappuccino","blended",5.25,1.35,0),
    ("Matcha Creme Frappuccino","frappuccino","blended",5.75,1.50,0),
    ("Chai Tea Latte","tea","hot",4.75,0.90,0),
    ("Matcha Tea Latte","tea","hot",5.25,1.10,0),
    ("London Fog Tea Latte","tea","hot",4.55,0.85,0),
    ("Iced Chai Tea Latte","tea","iced",5.25,0.95,0),
    ("Iced Matcha Tea Latte","tea","iced",5.55,1.15,0),
    ("Passion Tango Herbal Tea","tea","hot",2.95,0.45,0),
    ("Peach Green Tea Lemonade","tea","iced",4.75,0.80,0),
    ("Dragon Drink","refreshers","iced",5.25,1.00,0),
    ("Strawberry Acai Refresher","refreshers","iced",4.95,0.90,0),
    ("Mango Dragonfruit Refresher","refreshers","iced",4.95,0.90,0),
    ("Pink Drink","refreshers","iced",5.25,1.00,0),
    ("Paradise Drink","refreshers","iced",5.25,1.00,0),
    ("Butter Croissant","food","bakery",3.45,1.20,0),
    ("Chocolate Croissant","food","bakery",3.75,1.30,0),
    ("Blueberry Muffin","food","bakery",3.45,1.15,0),
    ("Banana Nut Bread","food","bakery",3.75,1.20,0),
    ("Cheese Danish","food","bakery",3.45,1.10,0),
    ("Egg & Cheese Breakfast Sandwich","food","sandwich",4.95,1.80,0),
    ("Bacon Gouda Breakfast Sandwich","food","sandwich",5.45,2.00,0),
    ("Turkey Pesto Panini","food","sandwich",6.95,2.50,0),
    ("Chicken Caprese Panini","food","sandwich",6.95,2.50,0),
    ("Impossible Breakfast Sandwich","food","sandwich",5.95,2.20,0),
    ("Cake Pop","food","snack",3.25,0.80,0),
    ("Chocolate Chip Cookie","food","snack",2.95,0.70,0),
    ("Madeline","food","snack",2.75,0.65,0),
    ("Protein Box - Eggs & Cheese","food","protein_box",5.95,2.30,0),
    ("Protein Box - PB&J","food","protein_box",5.75,2.10,0),
    ("Pike Place Roast (bag)","merch","whole_bean",14.95,6.50,0),
    ("Veranda Blend (bag)","merch","whole_bean",14.95,6.50,0),
    ("French Roast (bag)","merch","whole_bean",14.95,6.50,0),
    ("Holiday Blend (bag)","merch","whole_bean",16.95,7.00,1),
    ("Starbucks Tumbler 16oz","merch","drinkware",22.95,8.50,0),
    ("Starbucks Cold Cup 24oz","merch","drinkware",19.95,7.00,0),
    ("Starbucks Gift Card $25","merch","gift_card",25.00,25.00,0),
    ("Oatmilk (add-on)","addon","milk_alt",0.80,0.35,0),
    ("Almond Milk (add-on)","addon","milk_alt",0.80,0.30,0),
    ("Extra Shot (add-on)","addon","espresso",0.80,0.20,0),
]

SUPPLIERS = [
    (1,"Arabica Origins Co","coffee_beans","Colombia",21,94),
    (2,"Pacific Bean Supply","coffee_beans","Brazil",25,91),
    (3,"Highland Roasters","coffee_beans","Ethiopia",30,88),
    (4,"DairyFresh Inc","dairy","USA",3,97),
    (5,"Oatly Partners","dairy","Sweden",14,92),
    (6,"Torani Syrups","syrups","USA",5,96),
    (7,"Monin Flavors","syrups","France",12,93),
    (8,"La Boulange Bakery","food","USA",1,95),
    (9,"Cuisine Solutions","food","USA",2,90),
    (10,"Prairie Farms","dairy","USA",3,96),
    (11,"EcoPack Solutions","packaging","USA",7,89),
    (12,"Green Cup Co","packaging","Canada",10,87),
    (13,"Sweet Street Desserts","food","USA",3,91),
    (14,"Teavana Farms","tea","India",28,85),
    (15,"Ceylon Select","tea","Sri Lanka",32,82),
    (16,"Cup & Lid Corp","packaging","USA",5,93),
    (17,"FreshBrew Equipment","equipment","Germany",45,90),
    (18,"CleanPro Supplies","cleaning","USA",4,95),
    (19,"Napkin & More","packaging","USA",6,91),
    (20,"Fruit Blenders Inc","ingredients","USA",3,94),
]

TRAINING_TYPES = [
    ("Barista Basics","onboarding",8),
    ("Food Safety Certification","safety",4),
    ("Espresso Mastery","barista_cert",6),
    ("Latte Art Workshop","barista_cert",3),
    ("Shift Leadership","leadership",8),
    ("Store Manager Essentials","leadership",16),
    ("Customer Service Excellence","skill",4),
    ("Seasonal Menu Training","seasonal",2),
    ("POS System Training","onboarding",3),
    ("Inventory Management","skill",4),
    ("Health & Safety Refresher","safety",2),
    ("Cold Brew Techniques","barista_cert",3),
    ("Conflict Resolution","leadership",4),
    ("Allergen Awareness","safety",2),
    ("Drive-Thru Efficiency","skill",3),
]

# Campaigns are date-aware — filter to those overlapping with our date range
ALL_CAMPAIGNS = [
    ("New Year New Brew","email","2026-01-02","2026-01-15",15000,850000,42000,3200,128000),
    ("Winter Warmers Promo","social","2026-01-10","2026-01-31",25000,1200000,65000,4800,195000),
    ("Valentine's Day Specials","in-store","2026-02-01","2026-02-14",10000,300000,None,2100,89000),
    ("App Exclusive: BOGO","app","2026-02-05","2026-02-12",5000,500000,38000,5600,224000),
    ("National Coffee Day","social","2026-01-18","2026-01-25",20000,950000,52000,3900,156000),
    ("Rewards Double Stars","app","2026-02-15","2026-02-22",8000,600000,45000,6200,248000),
    ("Spring Preview Menu","email","2026-03-01","2026-03-10",12000,720000,35000,2800,112000),
    ("Drive-Thru Happy Hour","in-store","2026-03-05","2026-03-19",18000,400000,None,3500,140000),
    ("St. Patrick's Matcha","social","2026-03-14","2026-03-17",8000,680000,41000,2200,88000),
    ("Starbucks for Life Sweepstakes","app","2026-01-15","2026-03-15",50000,2000000,120000,8500,425000),
    ("Sustainability Week","email","2026-02-20","2026-02-27",6000,420000,22000,1200,48000),
    ("Teacher Appreciation","social","2026-03-10","2026-03-14",10000,550000,32000,2600,104000),
    ("Mobile Order & Pay Push","app","2026-01-05","2026-01-31",15000,800000,55000,7100,284000),
    ("Frappuccino Friday","in-store","2026-03-20","2026-03-27",7000,250000,None,1800,72000),
    ("Cold Brew Season Kickoff","social","2026-03-22","2026-03-31",20000,900000,48000,3600,144000),
]

def campaigns_in_range(start, end):
    """Filter campaigns that overlap with the configured date range."""
    result = []
    for c in ALL_CAMPAIGNS:
        cs = datetime.strptime(c[2], "%Y-%m-%d")
        ce = datetime.strptime(c[3], "%Y-%m-%d")
        if cs <= end and ce >= start:
            result.append(c)
    return result

CAMPAIGNS = campaigns_in_range(DATE_START, DATE_END)

# ---------- Determine last month of date range for growth effects ----------
LAST_MONTH = DATE_END.month

# ---------- generate ----------
def create_db():
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    # ---- 1. regions ----
    c.execute("""CREATE TABLE regions (
        region_id INTEGER PRIMARY KEY,
        region_name TEXT NOT NULL,
        regional_director TEXT
    )""")
    for i, rname in enumerate(REGION_NAMES, 1):
        c.execute("INSERT INTO regions VALUES (?,?,?)",
            (i, rname, f"{random.choice(FIRST_NAMES)} {random.choice(LAST_NAMES)}"))

    # ---- 2. stores ----
    c.execute("""CREATE TABLE stores (
        store_id INTEGER PRIMARY KEY,
        store_name TEXT,
        city TEXT, state TEXT, country TEXT,
        region TEXT,
        store_type TEXT,
        open_date TEXT,
        square_feet INTEGER,
        manager_id INTEGER
    )""")
    stores = []
    for i in range(1, NUM_STORES + 1):
        city, state, region = random.choice(CITIES_STATES)
        stype = random.choices(["drive-thru","cafe","reserve"], weights=[45,45,10])[0]
        sqft = random.randint(1200, 3500) if stype != "reserve" else random.randint(3000, 6000)
        odate = rand_date(datetime(2005,1,1), datetime(2024,6,1)).strftime("%Y-%m-%d")
        stores.append((i, f"Starbucks {city} #{i}", city, state, "US", region, stype, odate, sqft, None))
    c.executemany("INSERT INTO stores VALUES (?,?,?,?,?,?,?,?,?,?)", stores)

    # ---- 3. employees ----
    c.execute("""CREATE TABLE employees (
        employee_id INTEGER PRIMARY KEY,
        store_id INTEGER,
        first_name TEXT, last_name TEXT,
        role TEXT,
        hire_date TEXT,
        hourly_rate REAL,
        status TEXT,
        performance_rating INTEGER,
        FOREIGN KEY (store_id) REFERENCES stores(store_id)
    )""")
    employees = []
    emp_id = 1
    for sid in range(1, NUM_STORES + 1):
        # 1 store manager
        employees.append((emp_id, sid, random.choice(FIRST_NAMES), random.choice(LAST_NAMES),
            "store_manager", rand_date(datetime(2015,1,1), datetime(2023,1,1)).strftime("%Y-%m-%d"),
            round(random.uniform(22,28),2), "active", random.randint(3,5)))
        mgr_id = emp_id
        c.execute("UPDATE stores SET manager_id=? WHERE store_id=?", (mgr_id, sid))
        emp_id += 1
        # 1 shift supervisor
        employees.append((emp_id, sid, random.choice(FIRST_NAMES), random.choice(LAST_NAMES),
            "shift_supervisor", rand_date(datetime(2018,1,1), datetime(2024,6,1)).strftime("%Y-%m-%d"),
            round(random.uniform(17,21),2), "active", random.randint(2,5)))
        emp_id += 1
        # baristas
        for _ in range(random.randint(BARISTAS_MIN, BARISTAS_MAX)):
            status = random.choices(["active","inactive"], weights=[90,10])[0]
            employees.append((emp_id, sid, random.choice(FIRST_NAMES), random.choice(LAST_NAMES),
                "barista", rand_date(datetime(2020,1,1), datetime(2025,12,1)).strftime("%Y-%m-%d"),
                round(random.uniform(14,18),2), status, random.randint(1,5)))
            emp_id += 1
    # district managers (not tied to a store)
    for _ in range(NUM_DISTRICT_MANAGERS):
        employees.append((emp_id, None, random.choice(FIRST_NAMES), random.choice(LAST_NAMES),
            "district_manager", rand_date(datetime(2010,1,1), datetime(2020,1,1)).strftime("%Y-%m-%d"),
            round(random.uniform(32,42),2), "active", random.randint(4,5)))
        emp_id += 1
    c.executemany("INSERT INTO employees VALUES (?,?,?,?,?,?,?,?,?)", employees)

    # ---- 4. products ----
    c.execute("""CREATE TABLE products (
        product_id INTEGER PRIMARY KEY,
        product_name TEXT,
        category TEXT,
        subcategory TEXT,
        unit_price REAL,
        cost REAL,
        is_seasonal INTEGER,
        launch_date TEXT
    )""")
    for i, p in enumerate(PRODUCT_CATALOG, 1):
        ldate = rand_date(datetime(2018,1,1), datetime(2025,6,1)).strftime("%Y-%m-%d")
        c.execute("INSERT INTO products VALUES (?,?,?,?,?,?,?,?)",
            (i, p[0], p[1], p[2], p[3], p[4], p[5], ldate))

    # ---- 5. suppliers ----
    c.execute("""CREATE TABLE suppliers (
        supplier_id INTEGER PRIMARY KEY,
        supplier_name TEXT,
        category TEXT,
        country TEXT,
        lead_time_days INTEGER,
        reliability_score INTEGER,
        contract_start TEXT,
        contract_end TEXT
    )""")
    for s in SUPPLIERS:
        cs = rand_date(datetime(2022,1,1), datetime(2024,6,1)).strftime("%Y-%m-%d")
        ce = rand_date(datetime(2026,6,1), datetime(2028,12,1)).strftime("%Y-%m-%d")
        c.execute("INSERT INTO suppliers VALUES (?,?,?,?,?,?,?,?)",
            (s[0], s[1], s[2], s[3], s[4], s[5], cs, ce))

    # ---- 6. customers ----
    c.execute("""CREATE TABLE customers (
        customer_id INTEGER PRIMARY KEY,
        first_name TEXT, last_name TEXT,
        email TEXT,
        city TEXT, state TEXT,
        join_date TEXT,
        rewards_tier TEXT,
        lifetime_spend REAL,
        visits_last_90_days INTEGER
    )""")
    customers = []
    for i in range(1, NUM_CUSTOMERS + 1):
        fn, ln = random.choice(FIRST_NAMES), random.choice(LAST_NAMES)
        city, state, _ = random.choice(CITIES_STATES)
        tier = random.choices(["none","green","gold"], weights=[30,40,30])[0]
        spend = round(random.uniform(50, 800) if tier == "none" else random.uniform(200, 3000) if tier == "green" else random.uniform(500, 8000), 2)
        visits = random.randint(1, 10) if tier == "none" else random.randint(5, 25) if tier == "green" else random.randint(15, 60)
        customers.append((i, fn, ln, f"{fn.lower()}.{ln.lower()}{i}@email.com", city, state,
            rand_date(datetime(2019,1,1), datetime(2025,12,1)).strftime("%Y-%m-%d"), tier, spend, visits))
    c.executemany("INSERT INTO customers VALUES (?,?,?,?,?,?,?,?,?,?)", customers)

    # ---- 7. daily_sales ----
    c.execute("""CREATE TABLE daily_sales (
        sale_date TEXT,
        store_id INTEGER,
        total_revenue REAL,
        total_transactions INTEGER,
        avg_ticket_size REAL,
        mobile_order_pct REAL,
        FOREIGN KEY (store_id) REFERENCES stores(store_id)
    )""")
    daily_sales = []
    for day_offset in range(TOTAL_DAYS):
        d = DATE_START + timedelta(days=day_offset)
        ds = d.strftime("%Y-%m-%d")
        dow = d.weekday()
        # Calculate how far we are into the range (0.0 to 1.0) for growth trend
        progress = day_offset / max(TOTAL_DAYS - 1, 1)
        for sid in range(1, NUM_STORES + 1):
            base = random.uniform(3500, 6500)
            # weekend boost
            if dow >= 5:
                base *= random.uniform(1.1, 1.35)
            # Monday dip
            if dow == 0:
                base *= random.uniform(0.85, 0.95)
            # top performing stores
            if sid <= TOP_STORE_THRESHOLD:
                base *= random.uniform(1.1, 1.3)
            # struggling stores
            if sid >= STRUGGLING_STORE_START:
                base *= random.uniform(0.65, 0.80)
            # Growth trend in the last third of the date range
            if progress > 0.66:
                base *= 1.05
            revenue = round(base, 2)
            txns = int(revenue / random.uniform(5.5, 8.5))
            avg_ticket = round(revenue / txns, 2) if txns > 0 else 0
            mobile_pct = round(random.uniform(25, 45) + (2 * progress), 1)
            daily_sales.append((ds, sid, revenue, txns, avg_ticket, mobile_pct))
    c.executemany("INSERT INTO daily_sales VALUES (?,?,?,?,?,?)", daily_sales)

    # ---- 8. product_sales (weekly aggregates) ----
    c.execute("""CREATE TABLE product_sales (
        week_start TEXT,
        store_id INTEGER,
        product_id INTEGER,
        quantity_sold INTEGER,
        revenue REAL,
        discount_amount REAL,
        FOREIGN KEY (store_id) REFERENCES stores(store_id),
        FOREIGN KEY (product_id) REFERENCES products(product_id)
    )""")
    product_sales = []
    # Sample ~30% of stores and ~33% of products per week
    stores_sample_size = max(1, int(NUM_STORES * 0.3))
    products_sample_size = min(20, len(PRODUCT_CATALOG))
    for week in range(NUM_WEEKS):
        ws = (DATE_START + timedelta(weeks=week)).strftime("%Y-%m-%d")
        for sid in random.sample(range(1, NUM_STORES + 1), min(stores_sample_size, NUM_STORES)):
            for pid in random.sample(range(1, len(PRODUCT_CATALOG) + 1), products_sample_size):
                is_seasonal = PRODUCT_CATALOG[pid-1][5]
                base_qty = random.randint(5, 80)
                if is_seasonal:
                    # seasonal items decline over the date range
                    base_qty = max(2, int(base_qty * (1.0 - week * 0.07)))
                price = PRODUCT_CATALOG[pid-1][3]
                qty = base_qty
                rev = round(qty * price, 2)
                disc = round(rev * random.uniform(0, 0.08), 2)
                product_sales.append((ws, sid, pid, qty, rev, disc))
    c.executemany("INSERT INTO product_sales VALUES (?,?,?,?,?,?)", product_sales)

    # ---- 9. customer_orders ----
    c.execute("""CREATE TABLE customer_orders (
        order_id INTEGER PRIMARY KEY,
        customer_id INTEGER,
        store_id INTEGER,
        order_date TEXT,
        order_total REAL,
        items_count INTEGER,
        payment_method TEXT,
        is_mobile_order INTEGER,
        FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
        FOREIGN KEY (store_id) REFERENCES stores(store_id)
    )""")
    orders = []
    oid = 1
    for cid in range(1, NUM_CUSTOMERS + 1):
        tier = customers[cid-1][7]
        n_orders = random.randint(1, 5) if tier == "none" else random.randint(3, 12) if tier == "green" else random.randint(8, 25)
        for _ in range(n_orders):
            sid = random.randint(1, NUM_STORES)
            od = rand_date(DATE_START, DATE_END).strftime("%Y-%m-%d")
            items = random.randint(1, 5)
            total = round(items * random.uniform(3.5, 7.5), 2)
            pay = random.choices(["card","mobile","cash"], weights=[40,45,15])[0]
            is_mobile = 1 if pay == "mobile" else random.choices([0,1], weights=[70,30])[0]
            orders.append((oid, cid, sid, od, total, items, pay, is_mobile))
            oid += 1
    c.executemany("INSERT INTO customer_orders VALUES (?,?,?,?,?,?,?,?)", orders)

    # ---- 10. inventory ----
    c.execute("""CREATE TABLE inventory (
        record_id INTEGER PRIMARY KEY AUTOINCREMENT,
        record_date TEXT,
        store_id INTEGER,
        item_name TEXT,
        category TEXT,
        quantity_on_hand INTEGER,
        reorder_point INTEGER,
        unit_cost REAL,
        supplier_id INTEGER,
        FOREIGN KEY (store_id) REFERENCES stores(store_id),
        FOREIGN KEY (supplier_id) REFERENCES suppliers(supplier_id)
    )""")
    inv_items = [
        ("Espresso Beans (kg)","coffee_beans",15,5,18.50,1),
        ("Pike Place Beans (kg)","coffee_beans",12,4,16.00,2),
        ("Whole Milk (gal)","dairy",20,8,4.50,4),
        ("Oat Milk (gal)","dairy",12,5,6.80,5),
        ("2% Milk (gal)","dairy",18,8,4.20,4),
        ("Vanilla Syrup (bottle)","syrups",8,3,12.00,6),
        ("Caramel Syrup (bottle)","syrups",8,3,12.00,6),
        ("Hazelnut Syrup (bottle)","syrups",6,3,12.00,7),
        ("Mocha Sauce (bottle)","syrups",6,2,14.00,7),
        ("Cups 12oz (sleeve)","packaging",25,10,8.50,11),
        ("Cups 16oz (sleeve)","packaging",25,10,9.00,11),
        ("Lids (sleeve)","packaging",30,12,5.00,16),
        ("Croissants (frozen, dozen)","food",6,2,18.00,8),
        ("Sandwich Wraps (pack)","food",8,3,22.00,9),
        ("Matcha Powder (kg)","tea",4,2,45.00,14),
        ("Chai Concentrate (gal)","tea",5,2,15.00,14),
    ]
    inventory_rows = []
    for month_start in MONTH_STARTS:
        for sid in range(1, NUM_STORES + 1):
            for item_name, cat, base_qty, reorder, cost, sup_id in inv_items:
                qty = max(0, base_qty + random.randint(-8, 8))
                inventory_rows.append((month_start, sid, item_name, cat, qty, reorder, cost, sup_id))
    c.executemany("INSERT INTO inventory (record_date,store_id,item_name,category,quantity_on_hand,reorder_point,unit_cost,supplier_id) VALUES (?,?,?,?,?,?,?,?)", inventory_rows)

    # ---- 11. customer_feedback ----
    c.execute("""CREATE TABLE customer_feedback (
        feedback_id INTEGER PRIMARY KEY,
        store_id INTEGER,
        customer_id INTEGER,
        feedback_date TEXT,
        rating INTEGER,
        category TEXT,
        comment TEXT,
        FOREIGN KEY (store_id) REFERENCES stores(store_id),
        FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
    )""")
    feedback_cats = ["service","quality","speed","cleanliness","app"]
    good_comments = [
        "Great experience as always!","Barista was super friendly","Perfect drink, made just right",
        "Quick service even during rush","Love the new seasonal menu","Clean and cozy atmosphere",
        "Mobile order was ready on time","Best latte in town","Staff remembered my name!",
        "Drive-thru was fast today"
    ]
    bad_comments = [
        "Had to wait 15 minutes for my order","Drink was lukewarm","Wrong order, had to get it remade",
        "Bathroom was not clean","App crashed during checkout","Barista seemed rushed and unfriendly",
        "Out of oat milk again","Drive-thru line was ridiculous","Pastry was stale",
        "Charged twice on my card"
    ]
    feedbacks = []
    for fid in range(1, NUM_FEEDBACK + 1):
        sid = random.randint(1, NUM_STORES)
        # struggling stores get worse ratings
        if sid >= STRUGGLING_STORE_START:
            rating = random.choices([1,2,3,4,5], weights=[15,25,30,20,10])[0]
        else:
            rating = random.choices([1,2,3,4,5], weights=[5,10,15,30,40])[0]
        comment = random.choice(good_comments) if rating >= 4 else random.choice(bad_comments)
        feedbacks.append((fid, sid, random.randint(1, NUM_CUSTOMERS),
            rand_date(DATE_START, DATE_END).strftime("%Y-%m-%d"),
            rating, random.choice(feedback_cats), comment))
    c.executemany("INSERT INTO customer_feedback VALUES (?,?,?,?,?,?,?)", feedbacks)

    # ---- 12. marketing_campaigns ----
    c.execute("""CREATE TABLE marketing_campaigns (
        campaign_id INTEGER PRIMARY KEY,
        campaign_name TEXT,
        channel TEXT,
        start_date TEXT, end_date TEXT,
        budget REAL,
        impressions INTEGER,
        clicks INTEGER,
        conversions INTEGER,
        revenue_attributed REAL
    )""")
    for i, camp in enumerate(CAMPAIGNS, 1):
        c.execute("INSERT INTO marketing_campaigns VALUES (?,?,?,?,?,?,?,?,?,?)",
            (i, camp[0], camp[1], camp[2], camp[3], camp[4], camp[5], camp[6], camp[7], camp[8]))

    # ---- 13. loyalty_transactions ----
    c.execute("""CREATE TABLE loyalty_transactions (
        transaction_id INTEGER PRIMARY KEY,
        customer_id INTEGER,
        transaction_date TEXT,
        stars_earned INTEGER,
        stars_redeemed INTEGER,
        reward_type TEXT,
        transaction_amount REAL,
        FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
    )""")
    reward_types = ["free_drink","free_food","discount",None]
    loyalty = []
    tid = 1
    for cid in range(1, NUM_CUSTOMERS + 1):
        tier = customers[cid-1][7]
        if tier == "none":
            continue
        n_txns = random.randint(3, 10) if tier == "green" else random.randint(8, 25)
        for _ in range(n_txns):
            td = rand_date(DATE_START, DATE_END).strftime("%Y-%m-%d")
            amt = round(random.uniform(4, 15), 2)
            stars_e = int(amt * 2)
            redeemed = 0
            rtype = None
            if tier == "gold" and random.random() < 0.25:
                redeemed = random.choice([25, 50, 150, 200])
                rtype = random.choice(["free_drink","free_food","discount"])
            loyalty.append((tid, cid, td, stars_e, redeemed, rtype, amt))
            tid += 1
    c.executemany("INSERT INTO loyalty_transactions VALUES (?,?,?,?,?,?,?)", loyalty)

    # ---- 14. labor_schedule ----
    c.execute("""CREATE TABLE labor_schedule (
        schedule_id INTEGER PRIMARY KEY,
        store_id INTEGER,
        employee_id INTEGER,
        shift_date TEXT,
        shift_start TEXT,
        shift_end TEXT,
        hours_worked REAL,
        is_overtime INTEGER,
        FOREIGN KEY (store_id) REFERENCES stores(store_id),
        FOREIGN KEY (employee_id) REFERENCES employees(employee_id)
    )""")
    schedule = []
    schid = 1
    emp_by_store = {}
    for e in employees:
        sid = e[1]
        if sid and e[7] == "active":
            emp_by_store.setdefault(sid, []).append(e[0])
    for week in range(NUM_WEEKS):
        week_start = DATE_START + timedelta(weeks=week)
        for sid in range(1, NUM_STORES + 1):
            emps = emp_by_store.get(sid, [])
            for eid in emps:
                days_worked = random.randint(4, 6)
                for d in random.sample(range(7), days_worked):
                    sd = (week_start + timedelta(days=d)).strftime("%Y-%m-%d")
                    sh = random.choice([5,6,7,8,12,13,14])
                    hrs = random.choices([6,7,8,9,10], weights=[15,25,35,15,10])[0]
                    is_ot = 1 if hrs > 8 else 0
                    schedule.append((schid, sid, eid, sd, f"{sh:02d}:00", f"{sh+hrs:02d}:00", hrs, is_ot))
                    schid += 1
    c.executemany("INSERT INTO labor_schedule VALUES (?,?,?,?,?,?,?,?)", schedule)

    # ---- 15. financial_summary ----
    c.execute("""CREATE TABLE financial_summary (
        month TEXT,
        store_id INTEGER,
        revenue REAL,
        cogs REAL,
        labor_cost REAL,
        rent REAL,
        utilities REAL,
        marketing_cost REAL,
        other_expenses REAL,
        net_profit REAL,
        FOREIGN KEY (store_id) REFERENCES stores(store_id)
    )""")
    fin = []
    for month in MONTHS:
        for sid in range(1, NUM_STORES + 1):
            base_rev = random.uniform(90000, 200000)
            if sid <= TOP_STORE_THRESHOLD:
                base_rev *= 1.2
            if sid >= STRUGGLING_STORE_START:
                base_rev *= 0.65
            # Growth in later months
            month_idx = MONTHS.index(month)
            if month_idx == len(MONTHS) - 1 and len(MONTHS) > 1:
                base_rev *= 1.05
            rev = round(base_rev, 2)
            cogs = round(rev * random.uniform(0.28, 0.35), 2)
            labor = round(rev * random.uniform(0.25, 0.32), 2)
            rent = round(random.uniform(8000, 18000), 2)
            utilities = round(random.uniform(1500, 4000), 2)
            mkt = round(random.uniform(500, 3000), 2)
            other = round(random.uniform(1000, 5000), 2)
            net = round(rev - cogs - labor - rent - utilities - mkt - other, 2)
            fin.append((month, sid, rev, cogs, labor, rent, utilities, mkt, other, net))
    c.executemany("INSERT INTO financial_summary VALUES (?,?,?,?,?,?,?,?,?,?)", fin)

    # ---- 16. store_traffic ----
    c.execute("""CREATE TABLE store_traffic (
        record_date TEXT,
        store_id INTEGER,
        hour_block TEXT,
        foot_traffic INTEGER,
        conversion_rate REAL,
        FOREIGN KEY (store_id) REFERENCES stores(store_id)
    )""")
    hour_blocks = ["06-07","07-08","08-09","09-10","10-11","11-12","12-13","13-14","14-15","15-16","16-17","17-18","18-19","19-20"]
    hour_weights = [15,45,50,35,20,25,30,28,32,28,18,15,10,8]
    traffic = []
    for week in range(NUM_WEEKS):
        sample_day = DATE_START + timedelta(weeks=week, days=random.randint(0,6))
        ds = sample_day.strftime("%Y-%m-%d")
        for sid in range(1, NUM_STORES + 1):
            for hb, hw in zip(hour_blocks, hour_weights):
                ft = max(5, int(hw * random.uniform(0.6, 1.5)))
                if sid >= STRUGGLING_STORE_START:
                    ft = int(ft * 0.6)
                cr = round(random.uniform(0.55, 0.85), 2)
                traffic.append((ds, sid, hb, ft, cr))
    c.executemany("INSERT INTO store_traffic VALUES (?,?,?,?,?)", traffic)

    # ---- 17. waste_log ----
    c.execute("""CREATE TABLE waste_log (
        log_id INTEGER PRIMARY KEY,
        log_date TEXT,
        store_id INTEGER,
        product_id INTEGER,
        quantity_wasted INTEGER,
        waste_reason TEXT,
        estimated_cost REAL,
        FOREIGN KEY (store_id) REFERENCES stores(store_id),
        FOREIGN KEY (product_id) REFERENCES products(product_id)
    )""")
    waste_reasons = ["expired","damaged","overproduction","quality"]
    waste = []
    wid = 1
    waste_stores_sample = max(1, int(NUM_STORES * 0.4))
    for week in range(NUM_WEEKS):
        ws = (DATE_START + timedelta(weeks=week)).strftime("%Y-%m-%d")
        for sid in random.sample(range(1, NUM_STORES + 1), min(waste_stores_sample, NUM_STORES)):
            for _ in range(random.randint(1, 4)):
                pid = random.randint(1, min(50, len(PRODUCT_CATALOG)))
                qty = random.randint(1, 12)
                if sid >= STRUGGLING_STORE_START:
                    qty = int(qty * 1.5)  # worse stores waste more
                cost_per = PRODUCT_CATALOG[pid-1][4]
                waste.append((wid, ws, sid, pid, qty, random.choice(waste_reasons), round(qty * cost_per, 2)))
                wid += 1
    c.executemany("INSERT INTO waste_log VALUES (?,?,?,?,?,?,?)", waste)

    # ---- 18. delivery_orders ----
    c.execute("""CREATE TABLE delivery_orders (
        order_id INTEGER PRIMARY KEY,
        customer_id INTEGER,
        store_id INTEGER,
        order_date TEXT,
        delivery_partner TEXT,
        order_total REAL,
        delivery_fee REAL,
        delivery_time_min INTEGER,
        customer_rating REAL,
        FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
        FOREIGN KEY (store_id) REFERENCES stores(store_id)
    )""")
    delivery = []
    did = 1
    for day_offset in range(TOTAL_DAYS):
        d = DATE_START + timedelta(days=day_offset)
        # growing trend: more deliveries over time
        progress = day_offset / max(TOTAL_DAYS - 1, 1)
        n_deliveries = random.randint(2, 5) + int(progress * 4)
        for _ in range(n_deliveries):
            cid = random.randint(1, NUM_CUSTOMERS)
            sid = random.randint(1, NUM_STORES)
            partner = random.choice(["uber_eats","doordash"])
            total = round(random.uniform(8, 35), 2)
            fee = round(random.uniform(2.99, 6.99), 2)
            time_min = random.randint(15, 55)
            rating = round(random.choices([3.0,3.5,4.0,4.5,5.0], weights=[5,10,20,35,30])[0], 1)
            delivery.append((did, cid, sid, d.strftime("%Y-%m-%d"), partner, total, fee, time_min, rating))
            did += 1
    c.executemany("INSERT INTO delivery_orders VALUES (?,?,?,?,?,?,?,?,?)", delivery)

    # ---- 19. training_records ----
    c.execute("""CREATE TABLE training_records (
        record_id INTEGER PRIMARY KEY,
        employee_id INTEGER,
        training_name TEXT,
        training_type TEXT,
        completion_date TEXT,
        score REAL,
        duration_hours REAL,
        FOREIGN KEY (employee_id) REFERENCES employees(employee_id)
    )""")
    training = []
    trid = 1
    for eid in random.sample(range(1, emp_id), min(int(emp_id * 0.6), emp_id - 1)):
        n_trainings = random.randint(1, 4)
        for _ in range(n_trainings):
            t = random.choice(TRAINING_TYPES)
            # Training dates can span a year before the date range through the end
            train_start = DATE_START - timedelta(days=365)
            training.append((trid, eid, t[0], t[1],
                rand_date(train_start, DATE_END).strftime("%Y-%m-%d"),
                round(random.uniform(60, 100), 1), t[2]))
            trid += 1
    c.executemany("INSERT INTO training_records VALUES (?,?,?,?,?,?,?)", training)

    # ---- 20. regional_performance ----
    c.execute("""CREATE TABLE regional_performance (
        region TEXT,
        quarter TEXT,
        total_revenue REAL,
        store_count INTEGER,
        avg_revenue_per_store REAL,
        yoy_growth_pct REAL,
        customer_satisfaction_avg REAL,
        employee_turnover_pct REAL
    )""")
    # Generate YoY comparison for each region: prior year Q and current Q
    # Use the quarter of the start date as the "current" quarter
    q_num = (DATE_START.month - 1) // 3 + 1
    current_q = f"Q{q_num}-{DATE_START.year}"
    prior_q = f"Q{q_num}-{DATE_START.year - 1}"
    region_data = []
    # Count stores per region
    stores_per_region = {}
    for s in stores:
        stores_per_region[s[5]] = stores_per_region.get(s[5], 0) + 1
    for rname in REGION_NAMES:
        sc = stores_per_region.get(rname, 0)
        if sc == 0:
            continue
        base_rev = random.uniform(400000, 600000) * sc
        prior_rev = round(base_rev, 0)
        growth = round(random.uniform(5.0, 10.0), 1)
        current_rev = round(prior_rev * (1 + growth / 100), 0)
        prior_avg = round(prior_rev / sc, 0)
        current_avg = round(current_rev / max(sc, 1), 0)
        sat_prior = round(random.uniform(3.7, 4.4), 1)
        sat_current = round(sat_prior + random.uniform(-0.1, 0.2), 1)
        turn_prior = round(random.uniform(12.0, 21.0), 1)
        turn_current = round(turn_prior - random.uniform(0.5, 2.0), 1)
        region_data.append((rname, prior_q, prior_rev, sc, prior_avg, None, sat_prior, turn_prior))
        region_data.append((rname, current_q, current_rev, sc, current_avg, growth, sat_current, turn_current))
    c.executemany("INSERT INTO regional_performance VALUES (?,?,?,?,?,?,?,?)", region_data)

    # ---- 21. menu_pricing_history ----
    c.execute("""CREATE TABLE menu_pricing_history (
        price_id INTEGER PRIMARY KEY,
        product_id INTEGER,
        effective_date TEXT,
        old_price REAL,
        new_price REAL,
        change_reason TEXT,
        FOREIGN KEY (product_id) REFERENCES products(product_id)
    )""")
    pricing = []
    prid = 1
    reasons = ["inflation","promotion","seasonal","cost_adjustment"]
    for pid in range(1, min(51, len(PRODUCT_CATALOG) + 1)):
        n_changes = random.randint(1, 3)
        current_price = PRODUCT_CATALOG[pid-1][3]
        for _ in range(n_changes):
            # Price changes in the 2 years leading up to end date
            price_start = DATE_END - timedelta(days=730)
            ed = rand_date(price_start, DATE_END).strftime("%Y-%m-%d")
            old_p = round(current_price - random.uniform(0.25, 0.75), 2)
            pricing.append((prid, pid, ed, old_p, current_price, random.choice(reasons)))
            prid += 1
    c.executemany("INSERT INTO menu_pricing_history VALUES (?,?,?,?,?,?)", pricing)

    conn.commit()

    # Print summary
    print(f"Database created: {DB_PATH}")
    print(f"Date range: {DATE_START.strftime('%Y-%m-%d')} to {DATE_END.strftime('%Y-%m-%d')} ({TOTAL_DAYS} days, {NUM_WEEKS} weeks)")
    print(f"Stores: {NUM_STORES} | Customers: {NUM_CUSTOMERS} | Regions: {len(REGION_NAMES)}")
    print()
    c.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
    tables = c.fetchall()
    total_rows = 0
    print(f"Tables ({len(tables)}):")
    for t in tables:
        c.execute(f"SELECT COUNT(*) FROM [{t[0]}]")
        count = c.fetchone()[0]
        total_rows += count
        print(f"  {t[0]:30s} {count:>8,} rows")
    print(f"  {'TOTAL':30s} {total_rows:>8,} rows")

    conn.close()

if __name__ == "__main__":
    create_db()
