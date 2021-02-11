drop table dim.customer;
CREATE TABLE dim.customer (
	id int4 NOT NULL,
	customer_key int4 NOT NULL,
	"name" varchar(100) NOT NULL,
	gender bpchar(1) NOT NULL,
	birth_date date NULL,
	address varchar(500) NULL,
	city varchar(100) NULL,
	region varchar(100) NULL,
	phone int8 NULL,
	email varchar(100) NULL,
	status varchar(30) NULL,
	subscriber_class varchar(100) NULL,
	CONSTRAINT customer_pk PRIMARY KEY (id)
);
insert into dim.customer (	
	id,
	customer_key,
	"name",
	gender,
	birth_date,
	address,
	city,
	region,
	phone,
	email,
	status,
	subscriber_class)
with cte_status as 
/* Вычисляем статус */
(
select distinct c.id
	,case 
		when max(si.dt) over (partition by si.customer_id) >= ('2020-05-31'::date) - interval '1 YEAR' then 'Активный' 
		-- вместо  now() считаем, что сегодня 2020-05-31, т.к. это самая свежая дата в базе
		else 'Не активный'
	end status
from nds.customer c
join nds.sale_item si on si.customer_id = c.id
)
--select * from cte_status
--select count(*) from cte_status;--1000
,cte_prod_cost as 
/* Вычисляем стоимость всех покупок за 3 месяца*/
(
select distinct 
c1.id
--, si.transaction_id 
--, si.line_number 
--, b.cost as b_cost
--, f.cost as f_cost
--, m.cost as m_cost
--, quantity 
,sum((coalesce(b.cost*quantity, 0) + coalesce(f.cost*quantity, 0) + coalesce(m.cost*quantity, 0))) over (partition by c1.id) as prod_cost --сумма всех покупок
, min(dt) over (partition by c1.id)::date as min_date
, ('2020-06-01'::date - min(dt) over (partition by c1.id)::date) as dd -- количество дней, прошедших с первой покупки
from nds.customer c1 
join nds.sale_item si on c1.id = si.customer_id 
left join nds.book b on b.id = si.book_id
left join nds.films f on f.id = si.film_id
left join nds.music m on m.id = si.music_id
where si.dt >= '2020-05-31'::date - interval '3 MONTH' -- считаем, что сегодня 2020-05-31, т.к. это самая свежая дата в базе
order by c1.id 
)
--select * from cte_prod_cost;
--select count(*) from cte_prod_cost;--507
,cte_sub_cost as(
/* Вычисляем стоимость всех подписок за 3 месяца*/
select distinct 
  c2.id
--, c.customer_id 
--, cs.date
--, s.price
--, s.days_active
--, s.start_ts
--, s.end_ts
,sum (s.price) over (partition by c2.id ) as subscr_cost --сумма всех подписок
from nds.customer c2 
left join nds.customers_subscriptions cs on cs.customer_id = c2.id
left join nds.subscriptions s on s.subscriptions_key =cs.subscription_id 
where cs.date >= '2020-05-31'::date - interval '3 MONTH' 
and s.end_ts >= '2020-05-31'::date - interval '3 MONTH'
order by c2.id  
)
--select * from cte_sub_cost;
--select count(*) from cte_sub_cost;--346
,cte_pgv as (
/* Вычисляем предполагаемую годовую выручку*/
select distinct c3.id
--,cte1.min_date
--,cte1.dd
--,coalesce (prod_cost,0)+coalesce (subscr_cost,0) as full_cost
, coalesce(case 
	when min_date <='2020-05-31'::date - interval '3 MONTH' --если первая покупка пользователя была более или = 3х месяцев от текущего момента
/* 
Предполагаемую годовую выручку (ПГВ pgv) рассчитывается так: сумма платежей за 3 последние месяца умножается на 4 
*/
	then (coalesce (prod_cost,0)+coalesce (subscr_cost,0))*4
/*
если первая покупка пользователя была не раньше 3х месяцев от текущего момента, тогда сумма всех платежей подписчика умножается на (365 / кол-во дней, прошедших с первой покупки)
*/
	else 365*(coalesce (prod_cost,0)+coalesce (subscr_cost,0))/dd
  end,0)::int as pgv 
from nds.customer c3
left join cte_prod_cost cte1 on cte1.id = c3.id
left join cte_sub_cost cte2 on cte2.id = c3.id
order by pgv desc 
)
--select * from cte_pgv;
--select count(*) from cte_pgv; --2014 
/*
 в nds.customer 2014 записей для 1000 пользователей. У дубляжей будет статус null, поэтому очистим ниже
  */
, cte_max_pgv as (select max(pgv) as max_pgv from cte_pgv) -- максимальное значение суммы платежей по всем пользователям
--select * from cte_max_pgv;
, cte_subscriber_class as (
/* Вычисляем значение subscriber_class*/
select 
id
--, pgv
--, max_pgv
/* 
Значения поля subscriber_class присваиваются по следующему принципу: R1 - если ПГВ в диапазоне от 0 до 24% включительно от максимального по всем пользователям, R2 в диапазоне от 25% до 49%, R3 - от 50% до 74% и R4, если ПГВ пользователя больше 75% включительно
*/
, case 
	when pgv =0											then 'R0'
	when pgv < 0.25*max_pgv 							then 'R1'
	when 0.25*max_pgv <= pgv and pgv <0.50*max_pgv 		then 'R2'
	when 0.50*max_pgv <= pgv and pgv <0.75*max_pgv 		then 'R3'
	when pgv >=0.25*max_pgv 							then 'R4'
	end as subscriber_class
from cte_pgv
inner join cte_max_pgv on 1=1
order by pgv desc 
)
--select * from cte_subscriber_class;
--select count(*) from cte_subscriber_class; -- 2014
select
	c.id,
	c.customer_id as customer_key,
	full_name,
	gender,
	birth_date,
	r.name || ', ' || c2.name|| ', ' ||a.name as address,
	c2.name as city,
	r.name as region,
	phone,
	email
	, cte_st.status	
	,cte_sc.subscriber_class
from nds.customer c
left join cte_status cte_st on cte_st.id = c.id
left join cte_subscriber_class cte_sc on cte_sc.id = c.id
join nds.address a on a.id = c.address_id 
join nds.city c2 on c2.id = a.city_id 
join nds.region r on r.id = c2.region_id
where cte_st.status is not null -- очищаем
;
/*Проверка*/

select count(*) from dim.customer_backup; -- 1000 
select count(*) from nds.customer; --2014
select count(*) from dim.customer; -- 1000
select * from nds.customer c where c.customer_id = '50630'; -- пример дубляжа
/*
 id  |customer_id|full_name     |gender|birth_date|
----|-----------|--------------|------|----------|
 631|      50630|Короткова Л.П.|ж     |1992-05-16|
1507|      50630|Короткова Л.П.|ж     |1992-05-16|
2014|      50630|Короткова Л.П.|ж     |1992-05-16| 
 */
select id,  customer_key, name, birth_date, status, subscriber_class
from dim.customer c where c.customer_key = '50630'; --очищено
/*
 id |customer_key|name          |birth_date|status|subscriber_class|
---|------------|--------------|----------|------|----------------|
631|       50630|Короткова Л.П.|1992-05-16|  Активный  |  R1      |
 */
 

