create table fact_sales (
	invoice_no varchar(30) not null,
	stock_code varchar(30) not null,
	description text,
	quantity bigint not null,
	transaction_type varchar(15),
	invoice_date timestamp not null,
	price numeric(10, 2) not null,
	customer_id varchar(20),
	country varchar(100)
	
);
--------------------------------------
copy fact_sales (
				invoice_no,
				stock_code,
				description,
				quantity,
				transaction_type,
				invoice_date,
				price,
				customer_id,
				country)

from 'C:/Users/Public/Fact_Sales.csv'
with (format csv, header true, delimiter ',',encoding 'WIN1252')
;
---------------------------------------

select *
from fact_sales
limit 10

-- QUERY 1: MONTHLY REVENUE AND VOLUME ANALYSIS
-- This query helps the business see seasonal trends
select 
	to_char(invoice_date, 'yyyy-mm') as sales_month, -- Formats date to year-month
	sum(quantity) as total_quantity,
	round(sum(quantity * price)::numeric, 2) as total_revenue
from fact_sales
group by sales_month
/*
any column in your SELECT that isn't being "summed" or "averaged" must be in the GROUP BY clause.
*/
order by sales_month;

--Query 2: Identifying the Top 10 Best-Selling Products
--
select
	description, sum(quantity) as total_quantity
from fact_sales
where transaction_type = 'Sale'
/*
single quote - Used for Data/Text Values (Strings).
double quote - Used for Identifiers (Table or Column names).
*/
group by description
order by total_quantity desc 
limit 10;

-- Query 3: Revenue Contribution by Country: 
-- Identify which international markets (outside the UK) have the highest growth potential
select 
	country,
	round(sum(quantity * price)::numeric, 2) as revenue
from fact_sales
where transaction_type = 'Sale'
	and country not in ('United Kingdom')
group by country
order by revenue desc;

-- Query 4: TOP CUSTOMERS BY TOTAL SPEND
--
select
	customer_id,
	round(sum(quantity*price)::numeric, 2) as high_return
from fact_sales
where transaction_type = 'Sale'
group by customer_id
order by high_return desc
limit 5;


-- Query 5: Average Order Value
--
select
	round(avg(total_revenue)::numeric, 2) as aov
from (
	select
		invoice_no,
		sum(quantity * price) as total_revenue
	from fact_sales
	where transaction_type = 'Sale'
	group by invoice_no
	) as sum_vale;


-- Query 6: Purchase Frequency of Customers
-- 
select
	customer_id,
	count(distinct invoice_no) as total_order
from fact_sales
where transaction_type = 'Sale'
and customer_id is not null
and customer_id != 'Guest_user'
group by customer_id
order by total_order desc
limit 10;


-- Query 7: Average Number of Items per Order
--
select
	round(avg(total_items)::numeric, 2) as avg_items 

from
	(
	select 
		invoice_no,
		count(stock_code) as total_items
	from fact_sales
	where transaction_type = 'Sale'
	group by invoice_no
	);

-- Query 8: PEAK SALES HOURS
--
select 
	DATE_TRUNC('hour', invoice_date) as hours_of_the_day,
	count(distinct invoice_no) as total_orders
from fact_sales
where transaction_type = 'Sale'
group by hours_of_the_day
order by total_orders desc;


-- Query 9: Revenue by Day of the Week
-- 
select
	to_char(invoice_date, 'day') as week,
	round(sum(quantity * price)::numeric, 2) as revenue
from fact_sales
where transaction_type = 'Sale'
group by week, extract(dow from invoice_date)
order by extract(dow from invoice_date);


-- Query 10: PRODUCT VELOCITY (TOP 10 FASTEST SELLERS)
-- 
select
	stock_code,
	description,
	count(stock_code) as total_sold
from fact_sales
where transaction_type = 'Sale'
group by stock_code, description
order by total_sold desc
limit 10;


-- Query 11: Product Affinity (Market Basket Analysis)
-- 
select
	a.description as product_a,
	b.description as product_b,
	count(*) as product_bought_in_pair
from fact_sales a
join fact_sales b
	on a.invoice_no = b.invoice_no
where a.transaction_type = 'Sale'
and b.transaction_type = 'Sale'
and a.stock_code < b.stock_code
group by product_a, product_b
order by  product_bought_in_pair desc
limit 10;
	
-- Query 12: Cancelled Invoice Impact
-- 
select 
	customer_id,
	count(distinct(invoice_no)) as cancelled_orders,
	round(sum(abs(quantity * price))::numeric, 2) as lost_revenue
from fact_sales
where transaction_type = 'Return'
group by customer_id
order by lost_revenue desc
limit 10;

-- Query 13: RFM Analysis - Recency
-- 
select 
	customer_id,
	MAX(invoice_date) AS last_purchase_date,
	(SELECT MAX(invoice_date) FROM fact_sales) - MAX(invoice_date) AS recency_gap
from fact_sales
where transaction_type = 'Sale'
group by customer_id
order by recency_gap asc
limit 10;

-- Query 14: Customer Segmentation
--
with customer_details as (
	select 
		customer_id,
		DATE_PART('day', (SELECT MAX(invoice_date) FROM fact_sales) - MAX(invoice_date)) AS recency,
		count(distinct(invoice_no)) as frequency,
		sum(quantity * price) as monetary
	from fact_sales
	where transaction_type = 'Sale'
	and customer_id is not null
	and customer_id != 'Guest_user'
	group by customer_id
	order by recency asc
)
select
	customer_id,
	recency,
	frequency,
	monetary,
	case
		when recency <= 30 and frequency >= 10 then 'Champion'
		when recency <=60 and frequency >=5 then 'Loyal Customer'
		when recency > 180 then 'at risk / lost'
		else 'Regular Customer'
	end as customer_segment
from customer_details
order by monetary desc;


-- Query 15: New vs. Returning Customer Ratio
-- 
with customer_first_purchase as (
	select 
		customer_id,
		min(invoice_date) as first_purchase
	from fact_sales
	where customer_id is not null
	group by customer_id
),
new_customer as(
	select 
		fs.customer_id,
		fs.quantity * fs.price as line_total,
		case
			when cfp.first_purchase >= (select max(invoice_date)- interval '90 days' from fact_sales)
			then 'New'
			else 'returning'
		end as status
	from fact_sales fs
	join customer_first_purchase cfp on fs.customer_id = cfp.customer_id
	where fs.transaction_type = 'Sale'
)
select 
	status,
	sum(line_total) as total_revenue,
	count(distinct(customer_id)) as total_customer 
from new_customer
group by status;


-- Query 16: Guest vs. Registered Revenue
-- 
select 
	case
		when customer_id  = 'Guest_user' then 'Guest'
		else 'registered'
	end as status,
	round(sum(quantity * price)::numeric, 2) as total_revenue,
	count(distinct invoice_no) as total_orders,
	round(avg(quantity * price)::numeric, 2) as average_revenue
from fact_sales
where transaction_type = 'Sale'
group by status
order by total_revenue desc;


-- Query 17: High Value Ghost Product
-- 
with product_metrics as (
	select
		stock_code,
		description,
		max(price) as unit_price,
		sum(quantity) as total_quantity_sold,
		avg(price) over() as global_threshold
	from fact_sales
	where transaction_type = 'Sale'
	group by stock_code, description, price
)
select
	stock_code,
	description,
	unit_price,
	total_quantity_sold,
	round(global_threshold::numeric, 2) as market_avg_price
from product_metrics	
where unit_price > global_threshold
and total_quantity_sold < 5
order by unit_price desc;







