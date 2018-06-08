SqlTable
========

SqlTable is a Lua module for accessing databases. It makes database
tables appear to be ordinary Lua tables containing one table per row.

It was born out of a frustration of trying to write an ORM mapper for
Lua. Being that Lua is not an object oriented language, any ORM mapper
immediately must come bundled with, or include, an entire object
orientation system.

The basic complex type in Lua isn't objects or classes. It is tables.
So why not make SQL tables look like Lua tables?


Links
-----

  * [Download](https://zadzmo.org/code/sqltable/downloads)
  * [Reference Manual](https://zadzmo.org/code/sqltable/docs)


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
as many table objects as you need:

	local t_employees_byname = sql.open_table{ name='employees', key='name' }
	local jSmith = t_employees_byname['John Smith']



Being originally written for Lua 5.1, the environment contains a method 
for doing table scans as well. In later 5.2 native versions I intend
to implement the `__pairs` and `__ipairs` metamethods, but for now there
is a helper function:

	for key, row in sql.all_rows( t_employees ) do
		do_stuff(row)
	end



Where clauses are helpful and common, too. Provide the SQL code
that goes after 'where' in your query, and any varibles it needs after 
that, and `sql.where` does what you might expect:

	for key, row in sql.where( t_employees, "active = $1", true) do
		do_stuff(row)
	end


The above example isn't 100% correct, because the value '$1' is
Postgres-specific. You can call `placeholder()` instead to be database 
agnostic:

	local query = "active = " .. sql.placeholder(1)

	for key, row in sql.where( t_employees, query, true) do
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



Requirements
------------

  * LuaDBI (database backend)
  * coxpcall (used in connection pooling)
  
Installation
------------

The simplest method is via LuaRocks, which will also pull in all
dependancies.

However, SqlTable is pure Lua, and can be installed from the
distribution tarball by including sqltable.lua and the sqltable/
subdirectories in package.path.

You can download the distribution tarball 
[here.](https://zadzmo.org/code/sqltable/downloads)


Limitations 
-----------

  * Currently, only Postgres is fully supported. Support for MySQL is
    implemented, but frequently segfaults. SQLite3 works, but there is 
    no `last_insert_id()` method exposed by LuaDBI which causes inserts 
    to be less than 100% functional.
  * NULLs in tables are not handled very well. Selecting, inserting,
    and updating NULL columns to non-NULL values works just fine as
    expected, but updating a column from a non-NULL value to NULL does 
    not. I plan to fix this in a later version.
  * Currently updates are slow, and prone to race conditions on busy
	servers.
  * SqlTable was built in Lua 5.1. Lua 5.2 may work but has not been
    tested.
    
Planned Features 
----------------

In no particular order, all the below are planned or under 
consideration:

  * Upsert support: fixes update limitation described above.
  * Fix MySQL support
  * Full Sqlite3 support
  * A procedure call interface: calling a stored procedure is one of
    the most common uses for the `sql:exec()` escape valve currently.
  * Prepared statement caching: should provide a significant performance
    boost, while also fixing the NULL handling limitation.
  * A database agnostic way of handling WHERE, LIMIT, and possibly
    ORDER BY clauses.
    
    
License
-------

This code is provided without warrenty under the terms of the
[MIT/X11 License](http://opensource.org/licenses/MIT).


Contact Maintainer
------------------

You can reach me by email at [aaron] [at] [zadzmo.org]. 

