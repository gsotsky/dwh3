/*
Задание No3*: таблица фактов “Подписки”. Необходимо создать таблицу фактов по подпискам. 
При этом необходимо выполнить бизнес требование 2 из слайда No20 (Требования). 
(на слайде 20 презентации нет требований)
*/
drop TABLE fact.subscriptions;
CREATE TABLE fact.subscriptions (
	date_key int4 NOT NULL,
	id int4 NOT NULL,
	subscriptions_key int4 NOT NULL,
	"name" varchar(100) NOT NULL,
	music_quantity int4 NOT NULL,
	books_quantity int4 NOT NULL,
	films_quantity int4 NOT NULL,
	price float8 NOT NULL,
	customer_key int4 NOT NULL,
	gender bpchar(1) NULL,
	age  int4 NOT NULL,
	city_user varchar(40) NOT NULL,
	region_user varchar(40) NOT NULL,
	city_store varchar(40) NOT NULL,
	region_store varchar(40) NOT NULL,
	days_active int2 NOT NULL,
	dt timestamp NOT NULL,
	start_ts date NULL,
	end_ts date NULL,
	is_current bool NULL DEFAULT true,
	create_ts timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
	update_ts timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
	CONSTRAINT subscriptions_date_key_fkey FOREIGN KEY (date_key) REFERENCES dim.date(id)
);

insert into fact.subscriptions (
	date_key,
	id,
	subscriptions_key,
	"name",
	music_quantity,
	books_quantity,
	films_quantity,
	price,
	customer_key,
	gender,
	age,
	city_user,
	region_user,
	city_store,
	region_store,
	days_active,
	dt,
	start_ts,
	end_ts,
	is_current)
select 
distinct
to_char(date, 'YYYYMMDD')::int
,  s.id
, subscriptions_key
, s.name
, music_quantity
, books_quantity
, films_quantity
, price
, c.id as customer_key
, gender
, (now()::date - birth_date::date)/365 as age
, c2.name as city_user
, r.name  as region_user
, c3.name as city_store
, r1.name as region_store
, days_active
, date as dt
, start_ts
, end_ts
, is_current
from nds.subscriptions s 
join nds.customers_subscriptions cs on cs.subscription_id = s.id
join nds.customer c on c.id = cs.customer_id 
join nds.address a on c.address_id = a.id 
join nds.city c2 on a.city_id = c2.id 
join nds.region r on c2.region_id = r.id 
left join nds.subscriptions_downloads sd on sd.subscription_id = s.id
join nds.store s2 on sd.store_id = s2.id
join nds.address a2 on s2.address_id = a2.id
join nds.city c3 on a2.city_id = c3.id 
join nds.region r1 on c3.region_id = r1.id 
order by s.id;

/*
Пример анализа продаж по географии и демографии
*/
select 
city_user
, gender
, case 
	when age < 25 then '< 25'
	when 25 <= age and  age <35 then '< 25-35'	
	when 35 <= age and  age < 45 then '< 35-45'	
	when 45 <= age then '>45'
	end age
, sum(price)
from fact.subscriptions s
group by city_user, gender, age
order by sum desc;

/*
city_user       |gender|age    |sum     |
----------------|------|-------|--------|
Ростов-на-Дону  |м     |< 25   |312070.0|
Иваново         |м     |< 25-35|227170.0|
Ставрополь      |м     |>45    |210010.0|
Челябинск       |м     |< 35-45|197730.0|
Казань          |м     |< 25-35|190790.0|
Нижний Новгород |м     |< 25   |166200.0|
Нижний Тагил    |м     |>45    |166200.0|
Иркутск         |м     |< 25-35|166200.0|
Москва          |м     |>45    |156090.0|
Иркутск         |ж     |>45    |155960.0|
Тюмень          |м     |< 35-45|151700.0|
Нижний Новгород |ж     |< 25-35|151540.0|
*/

/*
Длительность подписки по городам магазинов
*/
select 
city_store 
, sum(days_active) as long_subsc 
from fact.subscriptions s
group by city_store
order by long_subsc desc;

/*
city_store     |long_subsc|
---------------|----------|
Москва         |     55053|
Санкт-Петербург|     55053|
Казань         |     46443|
Нижний Новгород|     44679|
Новосибирск    |     43026|
Троицк         |     25420|
Уфа            |     21327|
*/

/*
Пользователи с подпиской
*/
select distinct c.id 
from nds.customer c 
join fact.subscriptions s on c.id = s.customer_key 
order by id;