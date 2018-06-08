
--
-- SQL test data for PostgreSQL
--

drop table if exists table1 cascade;
create table table1
	(
		id serial primary key,
		name varchar(255) not null,
		
		value1 int not null,
		value2 int not null,
		
		flag1 boolean not null,
		flag2 boolean not null
	);




insert into table1 
	(
		name, value1, value2, flag1, flag2
	)
	values
	(
		'Thing one', 24, 266, false, false
	),
	(
		'Thing two', 35, 1112, true, true
	),
	(
		'Thing three', 99, 48, true, false
	);



drop table if exists table2 cascade;
create table table2
	(
		id serial primary key,
		stringy varchar(255) not null,
		floater float not null,
		inter int not null,
		
		CHECK(inter < 1000)
	);

insert into table2 
		( stringy, floater, inter ) 
	values 
		( 'no delete', 4, 1 );

drop table if exists table3 cascade;
create table table3
	(
		rowname varchar(30) not null primary key,
		flag1 boolean not null,
		flag2 boolean not null
	);

insert into table3
	(
		rowname, flag1, flag2
	)
	values
	(
		'update this', false, false
	);


grant select, insert, update, delete on table1 to sqltable;
grant usage, select on table1_id_seq to sqltable;
grant select, insert, update, delete on table2 to sqltable;
grant usage, select on table2_id_seq to sqltable;
grant select, insert, update, delete on table3 to sqltable;
