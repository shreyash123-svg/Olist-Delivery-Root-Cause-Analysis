
-- === OLIST TABLES ===================================================

CREATE TABLE IF NOT EXISTS olist_customers (
  customer_id               TEXT PRIMARY KEY,
  customer_unique_id        TEXT,
  customer_zip_code_prefix  INTEGER,
  customer_city             TEXT,
  customer_state            TEXT
);

CREATE TABLE IF NOT EXISTS olist_sellers (
  seller_id                 TEXT PRIMARY KEY,
  seller_zip_code_prefix    INTEGER,
  seller_city               TEXT,
  seller_state              TEXT
);

CREATE TABLE IF NOT EXISTS olist_products (
  product_id                   TEXT PRIMARY KEY,
  product_category_name        TEXT,
  product_name_length          INTEGER,
  product_description_length   INTEGER,
  product_photos_qty           INTEGER,
  product_weight_g             INTEGER,
  product_length_cm            INTEGER,
  product_height_cm            INTEGER,
  product_width_cm             INTEGER
);

CREATE TABLE IF NOT EXISTS olist_orders (
  order_id                        TEXT PRIMARY KEY,
  customer_id                     TEXT NOT NULL,
  order_status                    TEXT,
  order_purchase_timestamp        TIMESTAMP,
  order_approved_at               TIMESTAMP,
  order_delivered_carrier_date    TIMESTAMP,
  order_delivered_customer_date   TIMESTAMP,
  order_estimated_delivery_date   TIMESTAMP
);

CREATE TABLE IF NOT EXISTS olist_order_items (
  order_id            TEXT NOT NULL,
  order_item_id       INTEGER NOT NULL,
  product_id          TEXT,
  seller_id           TEXT,
  shipping_limit_date TIMESTAMP,
  price               NUMERIC(12,2),
  freight_value       NUMERIC(12,2),
  PRIMARY KEY (order_id, order_item_id)
);

CREATE TABLE IF NOT EXISTS olist_order_payments (
  order_id              TEXT NOT NULL,
  payment_sequential    INTEGER NOT NULL,
  payment_type          TEXT,
  payment_installments  INTEGER,
  payment_value         NUMERIC(12,2),
  PRIMARY KEY (order_id, payment_sequential)
);

CREATE TABLE IF NOT EXISTS olist_order_reviews (
  review_id                TEXT PRIMARY KEY,
  order_id                 TEXT,
  review_score             INTEGER,
  review_comment_title     TEXT,
  review_comment_message   TEXT,
  review_creation_date     TIMESTAMP,
  review_answer_timestamp  TIMESTAMP
);

CREATE TABLE IF NOT EXISTS olist_geolocation (
  geolocation_zip_code_prefix  INTEGER,
  geolocation_lat              NUMERIC(9,6),
  geolocation_lng              NUMERIC(9,6),
  geolocation_city             TEXT,
  geolocation_state            TEXT
);

CREATE TABLE IF NOT EXISTS product_category_name_translation (
  product_category_name          TEXT PRIMARY KEY,
  product_category_name_english  TEXT);





select * from olist_customers

select * from olist_sellers 

select * from olist_products

select * from olist_orders

select * from olist_order_items

select * from olist_order_payments

select * from olist_order_reviews

select * from olist_geolocation

select * from product_category_name_translation



-----TASK 1---


CREATE OR REPLACE VIEW v_delivery_facts_plus AS
WITH order_seller AS (
  -- Ensure one row per order × seller (orders can have multiple items per seller)
  SELECT DISTINCT order_id, seller_id
  FROM olist_order_items
)
SELECT
  os.order_id,
  os.seller_id,
  o.customer_id,
  c.customer_state,
  s.seller_state,

  -- Key milestones
  o.order_approved_at,
  o.order_delivered_carrier_date,      -- when seller handed off to carrier
  o.order_delivered_customer_date,     -- when customer received it
  o.order_estimated_delivery_date,     -- promised latest date

  -- KPIs (in days; rounded)
  ROUND(EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_approved_at))/86400.0, 2)
    AS lead_time_days,
  ROUND(EXTRACT(EPOCH FROM (o.order_delivered_carrier_date - o.order_approved_at))/86400.0, 2)
    AS handling_days,
  ROUND(EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_delivered_carrier_date))/86400.0, 2)
    AS transit_days,
  ROUND(EXTRACT(EPOCH FROM (o.order_estimated_delivery_date - o.order_approved_at))/86400.0, 2)
    AS promised_days,
  GREATEST(
    ROUND(EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_estimated_delivery_date))/86400.0, 2),
    0
  ) AS lateness_days,

  CASE WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date THEN 1 ELSE 0 END
    AS is_on_time
FROM olist_orders o
JOIN order_seller    os ON os.order_id = o.order_id
JOIN olist_customers c  ON c.customer_id = o.customer_id
JOIN olist_sellers   s  ON s.seller_id   = os.seller_id
WHERE o.order_status = 'delivered'
  AND o.order_approved_at IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL;


select * from v_delivery_facts_plus


-----TASK 2-----
WITH lane AS (
  SELECT
    seller_state,
    customer_state,
    COUNT(*)                                          AS orders,
    ROUND(AVG(is_on_time)::numeric, 3)                AS on_time_rate,
    ROUND(AVG(lead_time_days)::numeric, 2)            AS avg_lead_time_days,
    -- Medians reduce outlier noise for diagnosis
    percentile_cont(0.5) WITHIN GROUP (ORDER BY handling_days) AS p50_handling_days,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY transit_days)  AS p50_transit_days
  FROM v_delivery_facts_plus
  GROUP BY seller_state, customer_state
)

-- Worst 10 lanes to fix first (real traffic + poor on-time)
SELECT seller_state, customer_state, orders, on_time_rate, avg_lead_time_days,
       ROUND(p50_handling_days::numeric,2) AS p50_handling_days,
       ROUND(p50_transit_days::numeric,2)  AS p50_transit_days
FROM lane
WHERE orders >= 300           -- volume guard; tweak if you like
  AND on_time_rate < 0.85     -- “bad” threshold; tweak to your SLA
ORDER BY on_time_rate ASC, orders DESC
LIMIT 10;




----TASK 3-----
WITH seller_kpis AS (
  SELECT seller_id, COUNT(*) AS delivered_orders,
    ROUND(AVG(is_on_time)::numeric, 3)             AS on_time_rate,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY handling_days) AS p50_handling_days,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY transit_days)  AS p50_transit_days
  FROM v_delivery_facts_plus
  GROUP BY seller_id
)
SELECT seller_id, delivered_orders, ROUND(on_time_rate, 3)  AS on_time_rate,
  ROUND(p50_handling_days::numeric, 2) AS p50_handling_days,
  ROUND(p50_transit_days::numeric, 2) AS p50_transit_days
FROM seller_kpis
WHERE delivered_orders >= 200 -- fairness guard
ORDER BY p50_handling_days DESC, delivered_orders DESC
LIMIT 20;


-----TASK 4-----
-- 1) Lane-specific thresholds to define "unusually high"
WITH lane_thresh AS (
SELECT seller_state, customer_state,
percentile_cont(0.75) WITHIN GROUP (ORDER BY handling_days) AS p75_handling,
percentile_cont(0.75) WITHIN GROUP (ORDER BY transit_days)  AS p75_transit
FROM v_delivery_facts_plus
GROUP BY seller_state, customer_state),
-- 2) Label each late order against its lane's thresholds
late_labeled AS (
  SELECT f.seller_state, f.customer_state,
  CASE WHEN f.handling_days IS NOT NULL AND f.handling_days >= lt.p75_handling THEN 1 ELSE 0 END AS handling_flag,
  CASE WHEN f.transit_days  IS NOT NULL AND f.transit_days  >= lt.p75_transit  THEN 1 ELSE 0 END AS transit_flag
  FROM v_delivery_facts_plus f
JOIN lane_thresh lt USING (seller_state, customer_state)
  WHERE f.is_on_time = 0 )

-- 3) Lane diagnosis summary
SELECT seller_state, Customer_state, COUNT(*)  AS late_orders, SUM(handling_flag)  AS late_due_handling, SUM(transit_flag) AS late_due_transit,
ROUND(100.0 * SUM(handling_flag) / NULLIF(COUNT(*),0), 1) AS handling_share_pct,
ROUND(100.0 * SUM(transit_flag)  / NULLIF(COUNT(*),0), 1) AS transit_share_pct,
CASE WHEN SUM(handling_flag) > SUM(transit_flag) THEN 'handling'
WHEN SUM(transit_flag)  > SUM(handling_flag) THEN 'transit' ELSE 'mixed'
END AS primary_driver
FROM late_labeled
GROUP BY seller_state, customer_state
HAVING COUNT(*) >= 100                        -- only lanes with enough late orders
ORDER BY primary_driver, late_orders DESC;



-----TASK 5-----

WITH base AS ( SELECT seller_id, seller_state, customer_state, 
COUNT(*) AS orders, AVG(1 - is_on_time)::numeric  AS late_rate,
percentile_cont(0.5) WITHIN GROUP (ORDER BY handling_days) AS p50_handling_days,
percentile_cont(0.5) WITHIN GROUP (ORDER BY transit_days)  AS p50_transit_days
FROM v_delivery_facts_plus
GROUP BY seller_id, seller_state, customer_state )
SELECT seller_id, seller_state, customer_state, orders,
ROUND(late_rate, 3) AS late_rate, 
ROUND(p50_handling_days::numeric, 2)     AS p50_handling_days,
ROUND(p50_transit_days::numeric, 2)      AS p50_transit_days
FROM base
WHERE orders >= 50    -- enough traffic to matter
AND late_rate >= 0.20   -- tweak threshold to your SLA
ORDER BY late_rate DESC, orders DESC
LIMIT 20;