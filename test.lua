#!/usr/bin/env lua

--pcall(require, "luacov")    --measure code coverage, if luacov is present

require "luarocks.loader"
lunatest = require "lunatest"
sqltable = require "sqltable"


local db_type = arg[ #arg ]
assert(db_type, "Must specify database type")

local config = dofile("test-configs/" .. db_type .. ".lua")
assert(config, "Didn't find database connection args to load")

local env = nil
local tdebug = false

--
-- Get a table.
--
-- We close and reopen the table for every test to ensure sane state.
-- However, we don't close and reopen the connection pool: We assume
-- it can keep itself sane. We prove that in test-connection.lua
-- instead.
--
local function setup( table_name, key, readonly )

	if not env then
		env = assert(sqltable.connect( config.connection ))
		
		if tdebug then
			env:debugging( 
				function ( q, args ) 
					print(q) 
					for k, v in pairs(args) do 
						print(k, '"'..tostring(v)..'"') 
					end 
				end
			)
		end
		
	end

	return assert(env:open_table{
			name = table_name,
			key = key or 'id',
			readonly = readonly or false,
			vendor = config[table_name .. '_vendor'] or {}
		})
end



--
-- Test that we can connect.
--
function test_init()
	
	local t = setup('table1')
	
	assert_nil(err)
	assert(t, err)
	
end


--
-- Test that a connect with bad user/pass fails.
--
function test_failure()

	assert_error(function()
		local t, err = sqltable.create{
			connection = {
				type = connect_args.type,
				host = connect_args.host,
				name = 'thisisnotpossiblyarealdatabase',
				user = 'thisisnotpossiblyarealuser'
			},
			
			sqltable = 'sqltable',
			key = 'thing'
		}
	end)
	
end


--
-- Test that unsupported databases aren't tried.
--
function test_no_support()

	assert_error(function()
		local t, err = sqltable.create{
			connection = {
				type = 'No Database',
				host = 'localhost',
				name = 'thisisnotpossiblyarealdatabase',
				user = 'thisisnotpossiblyarealuser'
			},
			
			sqltable = 'sqltable',
			key = 'thing'
		}
	end)
	
end


--
-- Test that we can iterate over all rows of a table.
--
function test_iterate_all()

	local t = setup('table1')
	local count = 0
	
	for i, v in env.all_rows(t) do
		assert(i > 0)
		assert_string(v.name)
		
		count = count + 1
	end

	assert(count == 3, "Got " .. tostring(count) .. " rows, expected 3")

end


--
-- Prove you can iterate multiple times.
--
function test_iterate_multiall()

	local t = setup('table1')
	
	
	for count = 1, 5 do
		local iter = env.all_rows(t)
	
		for i, v in iter do
			assert(i > 0)
			assert_string(v.name)
		end
	end

end




---
-- Test the primitive (string driven) where statement.
--
function test_where_normal()

	local t = setup('table1')
	local count = 0
	
	for k, v in env.where( t, "id >= 2") do
		count = count + 1
		
		assert_gte(2, k)
		assert_string(v.name)
	end

	assert_equal(2, count)

end


---
-- The above, with placeholders.
--
function test_where_withargs()

	local t = setup('table3', 'rowname')
	local count = 0
	
	for k, v in env.where( 
			t, "rowname = " .. env:placeholder(1), 
				'update this' 
		) do
			count = count + 1
			
			assert_equal('update this', k)
			assert_equal('update this', v.rowname)
			
			assert_boolean(v.flag1)
			assert_boolean(v.flag2)
	end

	-- only one row, primary key
	assert_equal(1, count)

end


---
-- Test that an impossible predicate gets no rows calling where.
--
function test_where_norows()

	local t = setup('table1')
	local count = 0
	
	for k, v in env.where( t, "1 != 1") do
		count = count + 1
	end
	
	assert_equal(0, count)
	
end


--
-- Test that we can grab specific rows
--
function test_select()

	local t = setup('table1')
	
	local x = env.select(t, 1)
	assert_table(x)
	assert_equal('Thing one', x.name)
	assert_equal(24, x.value1)
	assert_equal(266, x.value2)
	
	assert_false(x.flag1)
	assert_false(x.flag2)

end


--
-- Test that select works via metamethod.
--
function test_select_meta()

	local t = setup('table1')
	
	local x = t[1]
	assert_table(x)
	assert_equal('Thing one', x.name)
	assert_equal(24, x.value1)
	assert_equal(266, x.value2)

	assert_false(x.flag1)
	assert_false(x.flag2)

end


--
-- Test that we get nil if the row doesn't exist
--
function test_select_nil()

	local t = setup('table1')
	
	local x = env.select(t, 235823523)
	assert_nil(x)
	
end


--
-- Test that we can insert new rows
--
function test_insert()

	local t = setup('table2')
	
	local new_row = {
			stringy = 'weeee!',
			floater = (os.time() % 400) / 5,
			inter = os.time() % 1000
		}	

	local last_insert_id, err = env.insert(t, new_row)
	assert_nil(err)
	assert_number(last_insert_id)
	
	assert_table(t[ last_insert_id ])
	assert_equal(new_row.stringy, t[ last_insert_id ].stringy)
	assert_equal(math.floor(new_row.floater), math.floor(t[ last_insert_id ].floater))
	assert_equal(new_row.inter, t[ last_insert_id ].inter)

	-- Check that an insert really occured: close
	-- connection and redo
	env:reset()
	
	t = setup('table2')
	assert_table(t[ last_insert_id ])
	assert_equal(new_row.stringy, t[ last_insert_id ].stringy)
	assert_equal(math.floor(new_row.floater), math.floor(t[ last_insert_id ].floater))
	assert_equal(new_row.inter, t[ last_insert_id ].inter)
	
end


--
-- Test that insert works via metamethods.
--
function test_insert_meta()

	local t = setup('table2')
	local new_row = {
			stringy = 'weeee!',
			floater = (os.time() % 200) / 5,
			inter = os.time() % 1000
		}
		
	
	t[env.next] = new_row
	local last_insert_id = env.last_insert_id(t)
	
	assert_table(t[ last_insert_id ])
	assert_equal(new_row.stringy, t[ last_insert_id ].stringy)
	assert_equal(math.floor(new_row.floater), math.floor(t[ last_insert_id ].floater))
	assert_equal(new_row.inter, t[ last_insert_id ].inter)

	-- Check that an insert really occured: close
	-- connection and redo
	env:reset()

	t = setup('table2')
	assert_table(t[ last_insert_id ])
	assert_equal(new_row.stringy, t[ last_insert_id ].stringy)
	assert_equal(math.floor(new_row.floater), math.floor(t[ last_insert_id ].floater))
	assert_equal(new_row.inter, t[ last_insert_id ].inter)
	
end


--
-- Test that we can update rows
--
function test_update_varchar_key()

	local t = setup('table3', 'rowname')

	assert(env.select(t, 'update this'), "Didn't find row to update")
	env.update(t, { rowname = 'update this', flag1 = true, flag2 = false })
	
	-- Did it stick? Reset connections and find out.	
	env:reset()
	
	assert_true(env.select(t, 'update this').flag1)
	assert_false(env.select(t, 'update this').flag2)
	
	--
	-- repeat a few times, to be sure the database just didn't happen
	-- to look like that when we started.
	--
	
	env.update(t, { rowname = 'update this', flag1 = true, flag2 = true })
	env:reset()
	
	assert_true(env.select(t, 'update this').flag1)
	assert_true(env.select(t, 'update this').flag2)
	
	env.update(t, { rowname = 'update this', flag1 = false, flag2 = false })
	env:reset()

	assert_false(env.select(t, 'update this').flag1)
	assert_false(env.select(t, 'update this').flag2)
	
end


--
-- Test that we can update rows with integer keys
--
function test_update_integer_key()

	local t = setup('table1')

	assert(env.select(t, 3), "Didn't find row to update")
	local set_to = os.time()
	env.update(t, { id = 3, value2 = set_to })

	env:reset()
	assert_equal(set_to, (env.select(t, 3).value2))
	
	env:reset()
	set_to = set_to - 200
	env.update(t, { id = 3, value2 = set_to })

	env:reset()
	assert_equal(set_to, (env.select(t, 3).value2))

end


--
-- Test that we can update metamethod style.
--
function test_update_meta()

	local t = setup('table1')

	assert(t[3], "Didn't find row to update")
	local set_to = os.time()
	t[3] = { value2 = set_to }
	

	env:reset()
	assert_equal(set_to, t[3].value2)

	env:reset()
	set_to = set_to - 200
	t[3] = { value2 = set_to }
	
	env:reset()
	assert_equal(set_to, t[3].value2)
	
end


--
-- Prove that an update without the primary key dies.
--
function test_update_failure()

	local t = setup('table3', 'rowname')
	
	assert_error(function()
		env.update(t, { flag1 = true, flag2 = false })
	end)

end


--
-- Test that deletes work.
--
function test_delete()

	-- first, we need a row to delete. Add it.
	local t = setup('table3', 'rowname')
	
	local row = env.select( t, 'delete me' )
	if not row then
		env.insert( t, { rowname = 'delete me', flag1 = true, flag2 = true })
		row = env.select( t, 'delete me' )
	end
	
	-- it's there, right?
	assert_table(row)
	assert_equal('delete me', row.rowname)
	assert_true(row.flag1)
	assert_true(row.flag2)
	
	-- kill it!
	assert_true(env.delete( t, { rowname = 'delete me' } ))
	
	-- prove it died
	env:reset()
	
	t = setup('table3', 'rowname')
	assert_nil(env.select( t, 'delete me'))


end


--
-- Test we can delete via the metamethods.
--
function test_delete_meta()

	-- first, we need a row to delete. Add it.
	local t = setup('table3', 'rowname')
	
	local row = t['delete me']
	if not t['delete me'] then
		t['delete me'] = { flag1 = true, flag2 = true }
	end
	
	-- is it there?
	assert_true(t['delete me'].flag1)
	
	-- kill it!
	t['delete me'] = nil
	
	-- prove it died
	env:reset()
	
	t = setup('table3', 'rowname')
	assert_nil(t['delete me'])

	
end


--
-- Prove you can't delete without a primary key. Very big
-- issues can happen if not!
--
function test_delete_fails()
	local t = setup('table3', 'rowname')

	assert_error(function()
		env.delete(t, { flag1 = true, flag2 = false })
	end)
end


--
-- Prove we can count the number of rows in a table.
--
function test_count()
	local t = setup('table1')

	assert_equal(3, env.count(t))

end


--
-- Prove we can count the number of rows in a table, using a where
-- clause.
--
function test_count_where()
	local t = setup('table1')
	local where = "id < " .. env:placeholder( 1 )

	assert_equal(2, env.count(t, where, 3))

end


--
-- Prove that, after an error situation, we recover gracefully.
--
-- This was found in Postgres: in the event of an error, rollback()
-- must be performed. And DBI propagates errors to the top, thus
-- unrolling the stack, thus killing our rollback command if we
-- don't pcall() it.
--
-- This is likely a useless test now that connection pooling works,
-- but it doesn't hurt to keep it.
--
function test_error_rollback()

	local t = setup('table2')
	
	-- First we need a query that reliabily trips an error. Without
	-- check constraints this is not as easy as it sounds, particularly
	-- when you want portability across databases. They don't all fail
	-- the same way! For example, MySQL is silent about integer 
	-- overflows and SQLite3 doesn't worry about the exact data type.

	assert_error(function()
		t[env.next] = { 
			inter = 25000,
			stringy = 'weeee!',
			floater = os.time() / 5
		}
	end)
	
	-- notice we don't close the table. we're checking if it still
	-- works afterwards.
	t[env.next] = { 
			inter = 15,
			stringy = 'weeee!',
			floater = os.time() / 5
		}
		
	local last_insert_id = env.last_insert_id( t )
	
	-- Check that an insert really occured: close
	-- connection and check the last key
	env:reset()

	t = setup('table2')
	assert_table(t[ last_insert_id ])
	assert_equal(15, t[ last_insert_id ].inter)
	
end


--
-- Prove that accessing a bad key doesn't kill our
-- connection by leaving it in a bad state.
--
-- This is much like the above, but for the subtle case
-- of an error occuring during a select statement.
--
function test_select_rollback()

	-- XXX: It seems only Postgres has this condition to worry about.
	if config.connection.type ~= 'PostgreSQL' then
		return
	end

	local t = setup('table1')

	assert_error(function()
		local y = t['thing']
	end)
	
	assert_table(t[1])
	assert_boolean(t[1].flag1)
	assert_boolean(t[1].flag2)

end


--
-- Test that a table set to read-only is still readable.
--
function test_select_readonly()

	local t = setup('table1', 'id', true)
	
	assert_table(t[1])
	assert_boolean(t[1].flag1)
	assert_boolean(t[1].flag2)
	
end


--
-- Test that a table set to read-only errors during a write.
--
function test_error_readonly()

	local t = setup('table1', 'id', true)
	
	assert_error(function()
		t[345232] = { name = 'Should fail', value1 = 3543, value2 = 3345,
						flag1 = true, flag2 = false }
	end)
	
	assert_nil(t[345232])
	
end


--
-- Test that cloning a table works.
--
function test_clone()

	local t = setup('table1')
	local cloned = env.clone(t)

	assert_table(cloned)
	assert_equal(3, #cloned)
	assert_equal('Thing one', cloned[1].name)
	assert_equal('Thing two', cloned[2].name)
	assert_equal('Thing three', cloned[3].name)
	
	for i, v in ipairs(cloned) do
		assert_number(i)
		assert_number(v.value1)
		assert_number(v.value2)
		assert_boolean(v.flag1)
		assert_boolean(v.flag2)
	end
	
end


--
-- Test that cloning with a where clause works.
--
function test_clone_where()

	local t = setup('table1')
	local cloned = env.clone(t, "id >= 2")
	local count = 0
	
	for k, v in pairs(cloned) do
		count = count + 1
		
		assert_gte(2, k)
		assert_string(v.name)
	end

	assert_equal(2, count)
	
end


--
-- Test that cloning a table works, integer keys edition.
--
function test_iclone()

	local t = setup('table2')
	local cloned = env.iclone(t)
	local count = 0

	assert_table(cloned)
	for i, v in ipairs(cloned) do
		assert_table(v)
		assert_string(v.stringy)
		assert_number(v.inter)
		assert_number(v.floater)
		count = count + 1
	end

	assert_gt(0, count)

end


--
-- Test that cloning a table works, integer keys edition. And
-- with where clauses!
--
function test_iclone_where()

	local t = setup('table2')
	local cloned_nowhere = env.iclone(t)
	local cloned = env.iclone(t, "inter > 20")
	local count = 0

	assert_table(cloned)
	for i, v in ipairs(cloned) do
		assert_table(v)
		assert_string(v.stringy)
		assert_number(v.inter)
		assert_number(v.floater)
		count = count + 1
	end

	assert_gt(0, count)
	assert_gt(count, #cloned_nowhere)

end


--
-- Run the tests
--
lunatest.run()


--
-- Teardown, for completeness sake
--
local outstanding = env.pool:outstanding()
assert(outstanding == 0, "Leaked " .. tonumber(outstanding) .. " connections!")
if env then env:close() end
