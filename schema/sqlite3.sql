
--
-- SQL test data for SQlite3
--

drop table if exists table3;
drop table if exists table2;
drop table if exists table1;


create table table1
	(
		id integer primary key autoincrement,
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
		'Thing one', 24, 266, 0, 0
	),
	(
		'Thing two', 35, 1112, 1, 1
	),
	(
		'Thing three', 99, 48, 1, 0
	);



create table table2
	(
		id integer primary key autoincrement,
		stringy varchar(255) not null,
		floater float not null,
		inter int not null,
		
		CHECK(inter < 1000)
	);

insert into table2 
		( stringy, floater, inter ) 
	values 
		( 'no delete', 4, 1 );

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
		'update this', 0, 0
	);


