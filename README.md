# Olist Delivery Root Cause Analysis

## 1. Project Title

Olist Delivery Root Cause Analysis

## 2. Short Description / Purpose

A PostgreSQL-based data analysis project focused on identifying the root causes of late deliveries in the Olist Brazilian E-Commerce dataset.

The project analyzes delivery timelines, seller performance, delivery routes, and handling vs transit delays to identify problematic sellers and seller-to-customer lanes.

## 3. Tech Stack

- PostgreSQL
- SQL

## 4. Data Source

The project uses the Brazilian E-Commerce Public Dataset by Olist available on Kaggle.

### Kaggle Dataset

[Olist Brazilian E-Commerce Dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)

The dataset contains information related to:

- Customers
- Sellers
- Orders
- Order items
- Products
- Order reviews
- Payments
- Geolocation

### Tables Used

- `olist_orders`
- `olist_order_items`
- `olist_customers`
- `olist_sellers`

## 5. Features & Highlights

### Business Problem

Late deliveries can negatively affect customer satisfaction and repeat purchases.

This project analyzes delivery data to identify where delays occur and which sellers or routes contribute most to late deliveries.

### Key Analysis

- Created a reusable delivery facts view
- Analyzed seller-to-customer delivery lanes
- Identified worst-performing delivery routes
- Analyzed seller handling time
- Compared handling time vs transit time
- Identified primary causes of late deliveries
- Identified seller × lane delivery hotspots

### Delivery Metrics

- Lead time
- Handling time
- Transit time
- Promised delivery time
- Lateness
- On-time delivery rate
- Late delivery rate

### Root Cause Analysis

Late deliveries are classified based on whether the delay is primarily related to:

- Seller handling
- Transit
- Both handling and transit

### SQL Concepts Used

- JOINs
- GROUP BY
- HAVING
- CASE statements
- CTEs
- Aggregate functions
- Window functions
- Views
- Percentile functions
