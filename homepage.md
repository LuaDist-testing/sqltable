SqlTable
========

SqlTable is a Lua module for accessing databases. It makes database
tables appear to be ordinary Lua tables containing one table per row.
PostgreSQL, SQLite, and MySQL are all supported.

It was born out of a frustration of trying to write an ORM mapper for
Lua. Being that Lua is not an object oriented language, any ORM mapper
immediately must come bundled with, or include, an entire object
orientation system.

The basic complex type in Lua isn't objects or classes. It is tables.
So why not make SQL tables look like Lua tables?


Links
-----

  * [Download](https://zadzmo.org/code/sqltable/downloads/)
  * [Reference Manual](https://zadzmo.org/code/sqltable/docs/)


Basic Usage 
-----------

The following examples assume the existance of a fake payroll database, 
with a table called `employees`.


Using SqlTable, selects are now:
	
	local row = t_employees[ employee_name ]


Updates:

	row.value = "modified"
	t_employees[ row.id ] = row


Deletes:

	t_employees[ row.id ] = nil


Inserts are special. If there is no auto-increment, it looks exactly
like an update. If you have an auto-incrementing key, you don't 
know what the key is until after the insert. The arbitrary value 
`sql.next` tells SqlTable that the value is an insert and to generate a 
new key:

	t_employees[ sql.next ] = new_row


Then, retrieve the key like this (warning, currently only works in
PostgreSQL):

	local new_row_id = sql.last_insert_id( t_employees )


Oh, I'm sorry, you still want an ORM mapper? Done:

	local methods = {
		foo = function() ... end
	}
	local object = setmetatable( t_employees[ id ], methods )


To do any of this, of course, you need to make your database 
connection. This is how:

	local connection_args = {
			type = 'PostgreSQL',
			host = 'pgserver.local.domain',
			name = 'payroll',
			user = 'sqltable',
			pass = 'testinguser-12345!!!'
		},
		
	local sqltable = require "sqltable"
	local sql = sqltable.connect( connection_arg )


That variable `sql` is your database environment. It contains a number
of variables, including but not limited to the `next` value that is
used for inserts. It also contains the function used to tell SqlTable
about a table you are interested in. These examples are all querying
the employee table, so we need to tell SqlTable we are interested in
employees:

	local t_employees = sql.open_table{ name='employees', key='id' }


Both `name` -the name of the table, and `key` - the primary key of
the table are required to open it. Other advanced arguments are
possible, consult the detailed documentation.

It's worth noting that SqlTable doesn't care, or for that matter even
know, what the primary key is. It also doesn't care what the data type
of the key is. Thus, if you want to select employees by name as well,
just open another one. Database connections are pooled, so open
as many table objects as you need without worrying about overhead:

	local t_employees_byname = sql.open_table{ name='employees', key='name' }
	local jSmith = t_employees_byname['John Smith']



Being originally written for Lua 5.1, the environment contains a method 
for doing table scans as well.

	for key, row in sql.all_rows( t_employees ) do
		do_stuff(row)
	end

In Lua 5.2 and later, you can also just use pairs() and ipairs(). They
behave mostly as you would expect:

	for key, row in pairs( t_employees ) do
		-- primary key, and a table for the row
		do_stuff(row)
	end
	
	for i, row in ipairs( t_employees) do
		-- i goes from 1 to however many rows are returned, along
		-- with the given row
		do_stuff(row)
	end

There is also a 'count' method, which returns the total rows in a
table:

	local num_employees = sql.count( t_employees )
	
In 5.2 and later, the len metamethod is also set:

	local num_employees = #t_employees


Where clauses are helpful and common, too. Provide the SQL code
that goes after 'where' in your query, and any varibles it needs after 
that, and `sql.where` does what you might guess:

	for key, row in sql.where( t_employees, "active = $1", true) do
		-- only active employees
		do_stuff(row)
	end


The above example isn't 100% correct, because the value '$1' is
Postgres-specific. You can call `sql.placeholder()` instead to be database 
agnostic. `placeholder()` takes a number as it's argument, which 
corresponds to the SQL argument being passed in.


	local query = "active = " .. sql.placeholder(1)

	-- all active employees
	for key, row in sql.where( t_employees, query, true) do
		do_stuff(row)
	end

	-- all active employees paid more than $50,000/year
	local new_query =  "active = .. sql.placeholder(1) 
					.. " and salary > " .. sql.placeholder(2)
	for key, row in sql.where( t_employees, query, true, 50000 )
		do_stuff(row)
	end


Querying data and unpacking it into a new table turned out to be such
a common operation, it was implemented with the function `clone`:

	local t = sql.clone( t_employees )
	
	for key, row in pairs( t ) do
		print(key, row.salary)
	end


This copies the table into memory, which means if something changes in 
the background, the table created by `clone` goes stale. There is no
efficient way to predict this, so it's best to keep the cloned table
very short lived.

If you wish your table to be array-like and not map-like, ie to use
`ipairs` instead, `iclone` works almost the same way except it ignores
the row key. The same limitations apply:

	local t = sql.iclone( t_employees )
	
	for i, row in pairs( t ) do
		print(row.name, row.salary)
	end


Both `clone` and `iclone` also support where clauses:

	local t = sql.clone( t_employees, "salary > $1", { 25000 } )


At this point you might be wondering where support for joins,
subselects, group by, etc come into play. They don't. SqlTable was built
with the belief that all syntax can, and should, be kept seperate: keep
your SQL in the database, as a view. Once the view exists, open said 
view as a table, and you have your join, aggregate, or subselect. The 
examples above for `where()`,  `clone()`, and `iclone()` are the only 
places where any SQL code at all is needed.

That being said, all abstractions fail at some point. And thus, there
is an escape valve: the connection pool contains an execute method,
and it's directly exposed as `sql.exec()`. Consult the 
[reference manual](https://zadzmo.org/code/sqltable/docs/modules/sqltable.pool.html#_pool.exec)
for a full explaination:


	local row = true

	sql:exec(
		[[
		select * 
			from employees as e 
			join salary as s 
				on e.id = s.employee_id
			where id = $1
		]], 
		
		{ 500 },
		
		function( conn, statement )
			row = statement:fetch(true)
		end
	)

	return row


Sometimes, one needs to set up per-connection variables or connection
specific options. A classic example is setting PRAGMA on SQLite3
connections. Simply provide a function that will be passed the database
connection object from LuaDBI when a connection is opened. Please
note, this is the low level [LuaDBI](https://zadzmo.org/code/luadbi)
API within:

	sql:setup_hook( function( connection )

		connection.prepare( ... )
		--- more code

	end )


Requirements
------------

  * LuaDBI (database backend)
  * coxpcall (Lua 5.1 only; used in connection pooling)
  
Installation
------------

The simplest method is via LuaRocks.

However, SqlTable is pure Lua, and can be installed from the
distribution tarball by including sqltable.lua and the sqltable/
subdirectories in package.path.

You can download the distribution tarball 
[here.](https://zadzmo.org/code/sqltable/downloads/)

SqlTable is built on LuaDBI. Luarocks will install the DBI module;
you will also have to install the DBD module for your particular
database, one of:

 - luadbi-postgresql
 - luadbi-mysql
 - luadbi-sqlite3
 
If using SqlTable with Lua 5.1, you will also need 
[coxpcall](https://github.com/keplerproject/coxpcall), also
available in Luarocks.


Changelog
---------

 - Version 1.2 
   - Full support for MySQL, SQLite3
   - Full support for Lua 5.2 and 5.3
   - Prepared statement caching
   
 - Version 1.3
   - Connection Open hooks


Limitations 
-----------

  * NULLs in tables are not handled very well. Selecting, inserting,
    and updating NULL columns to non-NULL values works just fine as
    expected, but updating a column from a non-NULL value to NULL does 
    not. I plan to fix this in a later version.
  * Currently updates are slow, and prone to race conditions on busy
	servers.
    
Planned Features 
----------------

In no particular order, all the below are planned or under 
consideration:

  * Upsert support: fixes update limitation described above.
  * A procedure call interface: calling a stored procedure is one of
    the most common uses for the `sql:exec()` escape valve currently.
  * A database agnostic way of handling WHERE, LIMIT, and possibly
    ORDER BY clauses.
    
    
License
-------

This code is provided without warrenty under the terms of the
[MIT/X11 License](http://opensource.org/licenses/MIT).


Contact Maintainer
------------------

You can reach me by email at [aaron] [at] [zadzmo.org]. 

