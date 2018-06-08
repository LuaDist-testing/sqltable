
--
-- SQL test data for PostgreSQL
--

drop table if exists table1 cascade;
create table table1
	(
		id int primary key auto_increment,
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


--
-- MySQL truely is a braindead database. Can't raise an error
-- that propagates to the program? WTF?
--
drop table if exists Error;
CREATE TABLE `Error` (
`ErrorGID` int(10) unsigned NOT NULL auto_increment,
`Message` varchar(128) default NULL,
`Created` timestamp NOT NULL default CURRENT_TIMESTAMP
on update CURRENT_TIMESTAMP,
PRIMARY KEY (`ErrorGID`),
UNIQUE KEY `MessageIndex` (`Message`))
ENGINE=MEMORY
DEFAULT CHARSET=latin1
ROW_FORMAT=FIXED
COMMENT='The Fail() procedure writes to this table
twice to force a constraint failure.';

DELIMITER $$
DROP PROCEDURE IF EXISTS `Fail`$$
CREATE PROCEDURE `Fail`(_Message VARCHAR(128))
BEGIN
INSERT INTO Error (Message) VALUES (_Message);
INSERT INTO Error (Message) VALUES (_Message);
END$$
DELIMITER ;


drop table if exists table2 cascade;
create table table2
	(
		id int primary key auto_increment,
		stringy varchar(255) not null,
		floater float not null,
		inter int not null
	);

DELIMITER $$
create trigger table2_check_constraint_insert before insert on table2 for each row
begin
if new.inter >= 1000 then
call Fail('table2.inter must be below 1000');
end if;
end $$
DELIMITER ;

DELIMITER $$
create trigger table2_check_constraint_update before update on table2 for each row
begin
if new.inter >= 1000 then
call Fail('table2.inter must be below 1000');
end if;
end $$
DELIMITER ;


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
grant select, insert, update, delete on table2 to sqltable;
grant select, insert, update, delete on table3 to sqltable;
