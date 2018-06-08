#!/usr/bin/env lua5.3

package.path = "../?.lua;" .. package.path
require "luarocks.loader"

--pcall(require, "luacov")    --measure code coverage

--
-- Need to create some assertations missing from busted that
-- were present in lunatest
--
luaassert = require "luassert"
say = require "say"

local function gte( state, arguments )

	local a = arguments[1]
	local b = arguments[2]
	
	if a <= b then	
		return true
	end
	
	return false

end

local function gt( state, arguments )

	local a = arguments[1]
	local b = arguments[2]
	
	if a < b then	
		return true
	end
	
	return false

end

say:set(
	"assertion.is_gte.failed", 
	"Expected number to be equal or larger.\nPassed in: \n%s\nExpected:\n%s"
)

say:set(
	"assertion.is_gt.failed", 
	"Expected number to be larger.\nPassed in: \n%s\nExpected:\n%s"
)

luaassert:register(
	"assertion", "is_gte", gte, "assertion.is_gte.failed"
) 

luaassert:register(
	"assertion", "is_gt", gt, "assertion.is_gt.failed"
) 

require 'busted.runner'()

--pcall(require, "luacov")    --measure code coverage, if luacov is present
sqltable = require "sqltable"



--
-- Set this to 'true' to dump SQL code while tests run.
--
local tdebug = false


--
-- Setup tests
--
local function setup_tests()

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
	
	return env
	
end


--
-- Teardown, to clean up for the next test
--
local function teardown_tests()

	local outstanding = env.pool:outstanding()
	assert(outstanding == 0, "Leaked " .. tonumber(outstanding) .. " connections!")
	if env then env:close() end

end



--
-- Get a table.
--
-- We close and reopen the table for every test to ensure sane state.
-- However, we don't close and reopen the connection pool: We assume
-- it can keep itself sane. We prove that in test-connection.lua
-- instead.
--
local function gettable( table_name, key, readonly )

	assert(env, "Need environment")
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
	
	local t, err = gettable('table1')
	assert.is_nil(err)
	assert(t, err)
	
end


--
-- Test that a connect with bad user/pass fails.
--
function test_failure()

	assert.is_error(function()
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

	assert.is_error(function()
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

	local t = gettable('table1')
	local count = 0
	
	for i, v in env.all_rows(t) do
		assert(i > 0)
		assert.is_string(v.name)
		
		count = count + 1
	end

	assert(count == 3, "Got " .. tostring(count) .. " rows, expected 3")

end


--
-- Prove you can iterate multiple times.
--
function test_iterate_multiall()

	local t = gettable('table1')
	
	
	for count = 1, 5 do
		local iter = env.all_rows(t)
	
		for i, v in iter do
			assert(i > 0)
			assert.is_string(v.name)
		end
	end

end


--
-- Prove you can iterate by calling pairs().
--
function test_iterate_meta_pairs()
	local t = gettable('table1')
	local count = 0
	
	for i, v in pairs(t) do
		assert(i > 0)
		assert.is_string(v.name)
		
		count = count + 1
	end

	assert(count == 3, "Got " .. tostring(count) .. " rows, expected 3")
end


--
-- Prove you can iterate by calling ipairs().
--
function test_iterate_meta_ipairs()
	local t = gettable('table1')
	local count = 0
	
	for i, v in ipairs(t) do
		assert.is_string(v.name)
		count = count + 1
		assert.is_equal(count, i)
	end

	assert(count == 3, "Got " .. tostring(count) .. " rows, expected 3")
end



---
-- Test the primitive (string driven) where statement.
--
function test_where_normal()

	local t = gettable('table1')
	local count = 0
	
	for k, v in env.where( t, "id >= 2") do
		count = count + 1
		
		assert.is_gte(2, k)
		assert.is_string(v.name)
	end

	assert.is_equal(2, count)

end


---
-- The above, with placeholders.
--
function test_where_withargs()

	local t = gettable('table3', 'rowname')
	local count = 0
	
	for k, v in env.where( 
			t, "rowname = " .. env:placeholder(1), 
				'update this' 
		) do
			count = count + 1
			
			assert.is_equal('update this', k)
			assert.is_equal('update this', v.rowname)
			
			assert.is_boolean(v.flag1)
			assert.is_boolean(v.flag2)
	end

	-- only one row, primary key
	assert.is_equal(1, count)

end


---
-- Test that an impossible predicate gets no rows calling where.
--
function test_where_norows()

	local t = gettable('table1')
	local count = 0
	
	for k, v in env.where( t, "1 != 1") do
		count = count + 1
	end
	
	assert.is_equal(0, count)
	
end


--
-- Test that we can grab specific rows
--
function test_select()

	local t = gettable('table1')
	
	local x = env.select(t, 1)
	assert.is_table(x)
	assert.is_equal('Thing one', x.name)
	assert.is_equal(24, x.value1)
	assert.is_equal(266, x.value2)
	
	assert.is_false(x.flag1)
	assert.is_false(x.flag2)

end


--
-- Test that select works via metamethod.
--
function test_select_meta()

	local t = gettable('table1')
	
	local x = t[1]
	assert.is_table(x)
	assert.is_equal('Thing one', x.name)
	assert.is_equal(24, x.value1)
	assert.is_equal(266, x.value2)

	assert.is_false(x.flag1)
	assert.is_false(x.flag2)

end


--
-- Test that we get nil if the row doesn't exist
--
function test_select_nil()

	local t = gettable('table1')
	
	local x = env.select(t, 235823523)
	assert.is_nil(x)
	
end


--
-- Test that we can insert new rows
--
function test_insert()

	local t = gettable('table2')
	
	local new_row = {
			stringy = 'weeee!',
			floater = (os.time() % 400) / 5,
			inter = os.time() % 1000
		}	

	local last_insert_id, err = env.insert(t, new_row)
	assert.is_nil(err)
	assert.is_number(last_insert_id)
	
	assert.is_table(t[ last_insert_id ])
	assert.is_equal(new_row.stringy, t[ last_insert_id ].stringy)
	assert.is_equal(math.floor(new_row.floater), math.floor(t[ last_insert_id ].floater))
	assert.is_equal(new_row.inter, t[ last_insert_id ].inter)

	-- Check that an insert really occured: close
	-- connection and redo
	env:reset()
	
	t = gettable('table2')
	assert.is_table(t[ last_insert_id ])
	assert.is_equal(new_row.stringy, t[ last_insert_id ].stringy)
	assert.is_equal(math.floor(new_row.floater), math.floor(t[ last_insert_id ].floater))
	assert.is_equal(new_row.inter, t[ last_insert_id ].inter)
	
end


--
-- Test that insert works via metamethods.
--
function test_insert_meta()

	local t = gettable('table2')
	local new_row = {
			stringy = 'weeee!',
			floater = (os.time() % 200) / 5,
			inter = os.time() % 1000
		}
		
	
	t[env.next] = new_row
	local last_insert_id = env.last_insert_id(t)
	
	assert.is_table(t[ last_insert_id ])
	assert.is_equal(new_row.stringy, t[ last_insert_id ].stringy)
	assert.is_equal(math.floor(new_row.floater), math.floor(t[ last_insert_id ].floater))
	assert.is_equal(new_row.inter, t[ last_insert_id ].inter)

	-- Check that an insert really occured: close
	-- connection and redo
	env:reset()

	t = gettable('table2')
	assert.is_table(t[ last_insert_id ])
	assert.is_equal(new_row.stringy, t[ last_insert_id ].stringy)
	assert.is_equal(math.floor(new_row.floater), math.floor(t[ last_insert_id ].floater))
	assert.is_equal(new_row.inter, t[ last_insert_id ].inter)
	
end


--
-- Test that we can update rows
--
function test_update_varchar_key()

	local t = gettable('table3', 'rowname')

	assert(env.select(t, 'update this'), "Didn't find row to update")
	env.update(t, { rowname = 'update this', flag1 = true, flag2 = false })
	
	-- Did it stick? Reset connections and find out.	
	env:reset()
	
	assert.is_true(env.select(t, 'update this').flag1)
	assert.is_false(env.select(t, 'update this').flag2)
	
	--
	-- repeat a few times, to be sure the database just didn't happen
	-- to look like that when we started.
	--
	
	env.update(t, { rowname = 'update this', flag1 = true, flag2 = true })
	env:reset()
	
	assert.is_true(env.select(t, 'update this').flag1)
	assert.is_true(env.select(t, 'update this').flag2)
	
	env.update(t, { rowname = 'update this', flag1 = false, flag2 = false })
	env:reset()

	assert.is_false(env.select(t, 'update this').flag1)
	assert.is_false(env.select(t, 'update this').flag2)
	
end


--
-- Test that we can update rows with integer keys
--
function test_update_integer_key()

	local t = gettable('table1')

	assert(env.select(t, 3), "Didn't find row to update")
	local set_to = os.time()
	env.update(t, { id = 3, value2 = set_to })

	env:reset()
	assert.is_equal(set_to, (env.select(t, 3).value2))
	
	env:reset()
	set_to = set_to - 200
	env.update(t, { id = 3, value2 = set_to })

	env:reset()
	assert.is_equal(set_to, (env.select(t, 3).value2))

end


--
-- Test that we can update metamethod style.
--
function test_update_meta()

	local t = gettable('table1')

	assert(t[3], "Didn't find row to update")
	local set_to = os.time()
	t[3] = { value2 = set_to }
	

	env:reset()
	assert.is_equal(set_to, t[3].value2)

	env:reset()
	set_to = set_to - 200
	t[3] = { value2 = set_to }
	
	env:reset()
	assert.is_equal(set_to, t[3].value2)
	
end


--
-- Prove that an update without the primary key dies.
--
function test_update_failure()

	local t = gettable('table3', 'rowname')
	
	assert.is_error(function()
		env.update(t, { flag1 = true, flag2 = false })
	end)

end


--
-- Test that deletes work.
--
function test_delete()

	-- first, we need a row to delete. Add it.
	local t = gettable('table3', 'rowname')
	
	local row = env.select( t, 'delete me' )
	if not row then
		env.insert( t, { rowname = 'delete me', flag1 = true, flag2 = true })
		row = env.select( t, 'delete me' )
	end
	
	-- it's there, right?
	assert.is_table(row)
	assert.is_equal('delete me', row.rowname)
	assert.is_true(row.flag1)
	assert.is_true(row.flag2)
	
	-- kill it!
	assert.is_true(env.delete( t, { rowname = 'delete me' } ))
	
	-- prove it died
	env:reset()
	
	t = gettable('table3', 'rowname')
	assert.is_nil(env.select( t, 'delete me'))


end


--
-- Test we can delete via the metamethods.
--
function test_delete_meta()

	-- first, we need a row to delete. Add it.
	local t = gettable('table3', 'rowname')
	
	local row = t['delete me']
	if not t['delete me'] then
		t['delete me'] = { flag1 = true, flag2 = true }
	end
	
	-- is it there?
	assert.is_true(t['delete me'].flag1)
	
	-- kill it!
	t['delete me'] = nil
	
	-- prove it died
	env:reset()
	
	t = gettable('table3', 'rowname')
	assert.is_nil(t['delete me'])

	
end


--
-- Prove you can't delete without a primary key. Very big
-- issues can happen if not!
--
function test_delete_fails()
	local t = gettable('table3', 'rowname')

	assert.is_error(function()
		env.delete(t, { flag1 = true, flag2 = false })
	end)
end


--
-- Prove we can count the number of rows in a table.
--
function test_count()
	local t = gettable('table1')

	assert.is_equal(3, env.count(t))
end


--
-- Prove we can count the number of rows in a table, using a where
-- clause.
--
function test_count_where()
	local t = gettable('table1')
	local where = "id < " .. env:placeholder( 1 )

	assert.is_equal(2, env.count(t, where, 3))
end


--
-- Prove we can count the number of rows using the len operator
-- (#). Only works in Lua > 5.2.
--
function test_count_lenop()
	local t = gettable('table1')
	
	assert.is_equal(3, #t)
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

	local t = gettable('table2')
	
	-- First we need a query that reliabily trips an error. Without
	-- check constraints this is not as easy as it sounds, particularly
	-- when you want portability across databases. They don't all fail
	-- the same way! For example, MySQL is silent about integer 
	-- overflows and SQLite3 doesn't worry about the exact data type.

	assert.is_equal(0, env.pool:outstanding())
	
	assert.is_error(function()
		t[env.next] = { 
			inter = 25000,
			stringy = 'weeee!',
			floater = os.time() / 5
		}
	end)
	
	assert.is_equal(0, env.pool:outstanding())
	
	-- notice we don't close the table. we're checking if it still
	-- works afterwards.
	t[env.next] = { 
			inter = 15,
			stringy = 'weeee!',
			floater = os.time() / 5
		}
		
	assert.is_equal(0, env.pool:outstanding())
	local last_insert_id = env.last_insert_id( t )
	
	-- Check that an insert really occured: close
	-- connection and check the last key
	env:reset()

	t = gettable('table2')
	assert.is_table(t[ last_insert_id ])
	assert.is_equal(15, t[ last_insert_id ].inter)
	
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

	local t = gettable('table1')

	assert.is_error(function()
		local y = t['thing']
	end)
	
	assert.is_table(t[1])
	assert.is_boolean(t[1].flag1)
	assert.is_boolean(t[1].flag2)

end


--
-- Test that a table set to read-only is still readable.
--
function test_select_readonly()

	local t = gettable('table1', 'id', true)
	
	assert.is_table(t[1])
	assert.is_boolean(t[1].flag1)
	assert.is_boolean(t[1].flag2)
	
end


--
-- Test that a table set to read-only errors during a write.
--
function test_error_readonly()

	local t = gettable('table1', 'id', true)
	
	assert.is_error(function()
		t[345232] = { name = 'Should fail', value1 = 3543, value2 = 3345,
						flag1 = true, flag2 = false }
	end)
	
	assert.is_nil(t[345232])
	
end


--
-- Test that cloning a table works.
--
function test_clone()

	local t = gettable('table1')
	local cloned = env.clone(t)

	assert.is_table(cloned)
	assert.is_equal(3, #cloned)
	assert.is_equal('Thing one', cloned[1].name)
	assert.is_equal('Thing two', cloned[2].name)
	assert.is_equal('Thing three', cloned[3].name)
	
	for i, v in ipairs(cloned) do
		assert.is_number(i)
		assert.is_number(v.value1)
		assert.is_number(v.value2)
		assert.is_boolean(v.flag1)
		assert.is_boolean(v.flag2)
	end
	
end


--
-- Test that cloning with a where clause works.
--
function test_clone_where()

	local t = gettable('table1')
	local cloned = env.clone(t, "id >= 2")
	local count = 0
	
	for k, v in pairs(cloned) do
		count = count + 1
		
		assert.is_gte(2, k)
		assert.is_string(v.name)
	end

	assert.is_equal(2, count)
	
end


--
-- Test that cloning a table works, integer keys edition.
--
function test_iclone()

	local t = gettable('table2')
	local cloned = env.iclone(t)
	local count = 0

	assert.is_table(cloned)
	for i, v in ipairs(cloned) do
		assert.is_table(v)
		assert.is_string(v.stringy)
		assert.is_number(v.inter)
		assert.is_number(v.floater)
		count = count + 1
	end

	assert.is_gt(0, count)

end


--
-- Test that cloning a table works, integer keys edition. And
-- with where clauses!
--
function test_iclone_where()

	local t = gettable('table2')
	local cloned_nowhere = env.iclone(t)
	local cloned = env.iclone(t, "inter > 20")
	local count = 0

	assert.is_table(cloned)
	for i, v in ipairs(cloned) do
		assert.is_table(v)
		assert.is_string(v.stringy)
		assert.is_number(v.inter)
		assert.is_number(v.floater)
		count = count + 1
	end

	assert.is_gt(0, count)
	assert.is_gt(count, #cloned_nowhere)

end


--
-- Test transaction support, ending in commit
--
function test_transaction_commit()

	local t = gettable('table2')
	env:begin_transaction(t)
	
	local new_row = {
			stringy = 'weeee!',
			floater = (os.time() % 400) / 5,
			inter = os.time() % 1000
		}	
		
	t[env.next] = new_row
	local last_insert_id = env.last_insert_id(t)
	
	assert.is_table(t[ last_insert_id ])
	assert.is_equal(new_row.stringy, t[ last_insert_id ].stringy)
	assert.is_equal(math.floor(new_row.floater), math.floor(t[ last_insert_id ].floater))
	assert.is_equal(new_row.inter, t[ last_insert_id ].inter)
	
	new_row.stringy = 'Not whee'
	t[ last_insert_id ] = new_row
	
	env:commit( t )
	
	-- select back, prove it holds
	assert.is_table(t[ last_insert_id ])
	assert.is_equal(new_row.stringy, t[ last_insert_id ].stringy)
	assert.is_equal(math.floor(new_row.floater), math.floor(t[ last_insert_id ].floater))
	assert.is_equal(new_row.inter, t[ last_insert_id ].inter)
	
end

--
-- Test transaction support, ending in rollback
--
function test_transaction_rollback()

	local t = gettable('table2')
	
	local new_row = {
			stringy = 'weeee!',
			floater = (os.time() % 400) / 5,
			inter = os.time() % 1000
		}	
		
	t[env.next] = new_row
	local last_insert_id = env.last_insert_id(t)
	
	assert.is_table(t[ last_insert_id ])
	assert.is_equal(new_row.stringy, t[ last_insert_id ].stringy)
	assert.is_equal(math.floor(new_row.floater), math.floor(t[ last_insert_id ].floater))
	assert.is_equal(new_row.inter, t[ last_insert_id ].inter)
	
	env:begin_transaction(t)
	
	new_row.stringy = 'Not whee'
	t[ last_insert_id ] = new_row
	
	env:rollback( t )
	
	-- select back, prove it failed
	assert.is_table(t[ last_insert_id ])
	assert.is_equal('weeee!', t[ last_insert_id ].stringy)
	assert.is_equal(math.floor(new_row.floater), math.floor(t[ last_insert_id ].floater))
	assert.is_equal(new_row.inter, t[ last_insert_id ].inter)
	
end


--
-- Test that you can't open a transaction twice.
--
function test_transaction_begin_fails()

	local t = gettable('table2')
	env:begin_transaction(t)
	
	assert.is_error(function()
		env:begin_transaction(t)
	end)
	
	env:commit(t)
	
end


--
-- Test that you can't commit a transaction twice.
--
function test_transaction_commit_fails()

	local t = gettable('table2')
	env:begin_transaction(t)
	env:commit(t)
	
	assert.is_error(function()
		env:commit(t)
	end)
	
end


--
-- Test that you can't rollback a transaction twice.
--
function test_transaction_rollback_fails()

	local t = gettable('table2')
	env:begin_transaction(t)
	env:rollback(t)
	
	assert.is_error(function()
		env:rollback(t)
	end)
	
end


--
-- Test the debugging hook.
--
function test_debugging_hook()

	local t = gettable('table2')
	local code = "select 1 as one"
	local hook = nil
	local called = false
		
	env:debugging( function( sql, args ) 
	
		hook = sql 
		assert.is_string(sql)
		assert.is_table(args)
		assert.is_equal(0, #args)
		called = true
		
	end )
		
	env:exec( code, {}, function( c, s ) end )
	assert.is_equal(code, hook)
	assert.is_true(called)

end


--
-- Test disabling the debugging hook.
--
function test_debugging_hook_disable()

	local t = gettable('table2')
	local code1 = "select 1 as one"
	local code2 = "select 2 as two"
	local hook = nil
	local called = false
		
	env:debugging( function( sql, args ) hook = sql called = true end )
	env:exec( code1, {}, function( c, s ) end )

	assert.is_equal(code1, hook)
	assert.is_true(called)
		
	called = false
	hook = nil
		
	env:debugging()
	env:exec( code2, nil, function( c, s ) end )
	assert.is_nil(hook)
	assert.is_false(called)
		
end


--
-- Test the execute function.
--
-- This test might not pass in all databases...
--
function test_execute()

	env:exec( "select 1 as one", nil, function( connection, statement )
	
		local row = statement:fetch(true)
		assert.is_table(row)
		assert.is_equal(1, row.one)
	
	end)
	
	assert.is_equal(0, env.pool:outstanding())
	assert.is_gte(1, env.pool:connections())

end


--
-- Test the execute function, without a callback function.
--
-- The result should be the same as above.
--
function test_execute_nocallback()

	env:exec( "select 1 as one", nil)
	
	assert.is_equal(0, env.pool:outstanding())
	assert.is_gte(1, env.pool:connections())

end


--
-- Test that a failure to prepare code in the execute function
-- doesn't hurt the pool.
--
function test_execute_prepare_fails()

	assert.is_error(function()
		env:exec( "s43fuin23m4ruin34e", nil, function( connection, statement )
		end)
	end)

	assert.is_equal(0, env.pool:outstanding())
	assert.is_gte(1, env.pool:connections())
	
end


--
-- Test that a callback failure doesn't hurt the pool.
--
function test_execute_callback_fails()

	assert.is_error(function()
		env:exec( "select 1 as one", nil, function( connection, statement )
			error("break me")
		end)
	end)
	
	assert.is_equal(0, env.pool:outstanding())
	assert.is_gte(1, env.pool:connections())

end


describe("PostgreSQL #psql", function()
	db_type = "postgres"
	config = dofile("test-configs/" .. db_type .. ".lua")
	local env

	setup(setup_tests)
	it( "Sets up correctly", test_init )
	it( "Fails sanely", test_failure )
	it( "Fails on unsupported drivers", test_no_support )
	it( "Can iterate over tables", test_iterate_all )
	it( "Can iterate the same table multiple times", test_iterate_multiall )
	it( "Supports where clauses", test_where_normal )
	it( "Supports where with placeholders", test_where_withargs )
	it( "Doesn't break if where returns no rows", test_where_norows )
	it( "Can select a row", test_select )
	it( "Can select via metamethod", test_select_meta )
	it( "Returns nil if selected row doesn't exist", test_select_nil )
	it( "Can select if a table is read-only", test_select_readonly )
	it( "Can rollback on a bad select", test_select_rollback )
	it( "Can insert rows", test_insert )
	it( "Can insert via metamethods", test_insert_meta )
	it( "Can update with string keys", test_update_varchar_key )
	it( "Can update with integer keys", test_update_integer_key )
	it( "Can update via metamethods", test_update_meta )
	it( "Fails when a key isn't provided to update", test_update_failure )
	it( "Can delete rows", test_delete )
	it( "Can delete via metamethods", test_delete_meta )
	it( "Fails when deleting without a key", test_delete_fails )
	it( "Can clone a table into a temporary one", test_clone )
	it( "Can clone part of a table into a temporary one", test_clone_where )
	it( "Can clone into a temporary table, with integer keys", test_iclone )
	it( "Can clone into an integer keys temp table, with a where clause ", test_iclone_where )
	it( "Can count rows of a table", test_count )
	it( "Can count a subset of a table", test_count_where )
	it( "Can commit a transaction", test_transaction_commit )
	it( "Can rollback a transaction", test_transaction_rollback )
	it( "Won't double-commit a transaction", test_transaction_commit_fails )
	it( "Won't open two transactions", test_transaction_begin_fails )
	it( "Won't rollback a transaction twice", test_transaction_rollback_fails )
	it( "Fails when updating a read-only table", test_error_readonly )
	it( "Rolls back a transaction on failures", test_error_rollback )
	it( "Has a debugging hook", test_debugging_hook )
	it( "Can disable a debugging hook", test_debugging_hook_disable )
	it( "Has an execute function", test_execute )
	it( "Can recover from a failed execute callback", test_execute_callback_fails )
	it( "Can execute without a callback", test_execute_nocallback )
	it( "Can recover if SQL code isn't valid", test_execute_prepare_fails )
		
	if _VERSION ~= 'Lua 5.1' then
		it( "Can count rows with the length operator", test_count_lenop )
		it( "Can iterate a table using pairs", test_iterate_meta_pairs )
		it( "Can iterate a table using ipairs", test_iterate_meta_ipairs )
	end
	
	teardown(teardown_tests)
	
end)

describe("MySQL #mysql", function()
	db_type = "mysql"
	config = dofile("test-configs/" .. db_type .. ".lua")
	local env

	setup(setup_tests)
	it( "Sets up correctly", test_init )
	it( "Fails sanely", test_failure )
	it( "Fails on unsupported drivers", test_no_support )
	it( "Can iterate over tables", test_iterate_all )
	it( "Can iterate the same table multiple times", test_iterate_multiall )
	it( "Supports where clauses", test_where_normal )
	it( "Supports where with placeholders", test_where_withargs )
	it( "Doesn't break if where returns no rows", test_where_norows )
	it( "Can select a row", test_select )
	it( "Can select via metamethod", test_select_meta )
	it( "Returns nil if selected row doesn't exist", test_select_nil )
	it( "Can select if a table is read-only", test_select_readonly )
	it( "Can rollback on a bad select", test_select_rollback )
	it( "Can insert rows", test_insert )
	it( "Can insert via metamethods", test_insert_meta )
	it( "Can update with string keys", test_update_varchar_key )
	it( "Can update with integer keys", test_update_integer_key )
	it( "Can update via metamethods", test_update_meta )
	it( "Fails when a key isn't provided to update", test_update_failure )
	it( "Can delete rows", test_delete )
	it( "Can delete via metamethods", test_delete_meta )
	it( "Fails when deleting without a key", test_delete_fails )
	it( "Can clone a table into a temporary one", test_clone )
	it( "Can clone part of a table into a temporary one", test_clone_where )
	it( "Can commit a transaction", test_transaction_commit )
	it( "Can rollback a transaction", test_transaction_rollback )
	it( "Won't double-commit a transaction", test_transaction_commit_fails )
	it( "Won't open two transactions", test_transaction_begin_fails )
	it( "Won't rollback a transaction twice", test_transaction_rollback_fails )
	it( "Can clone into a temporary table, with integer keys", test_iclone )
	it( "Can clone into an integer keys temp table, with a where clause ", test_iclone_where )
	it( "Can count rows of a table", test_count )
	it( "Can count a subset of a table", test_count_where )
	it( "Fails when updating a read-only table", test_error_readonly )
	it( "Rolls back a transaction on failures", test_error_rollback )	
	it( "Has a debugging hook", test_debugging_hook )
	it( "Can disable a debugging hook", test_debugging_hook_disable )
	it( "Has an execute function", test_execute )
	it( "Can recover from a failed execute callback", test_execute_callback_fails )
	it( "Can execute without a callback", test_execute_nocallback )
	it( "Can recover if SQL code isn't valid", test_execute_prepare_fails )
	
	if _VERSION ~= 'Lua 5.1' then
		it( "Can count rows with the length operator", test_count_lenop )
		it( "Can iterate a table using pairs", test_iterate_meta_pairs )
		it( "Can iterate a table using ipairs", test_iterate_meta_ipairs )
	end
	
	teardown(teardown_tests)
	
end)

describe("SQLite3 #sqlite", function()
	db_type = "sqlite3"
	config = dofile("test-configs/" .. db_type .. ".lua")
	local env

	setup(setup_tests)
	it( "Sets up correctly", test_init )
	it( "Fails sanely", test_failure )
	it( "Fails on unsupported drivers", test_no_support )
	it( "Can iterate over tables", test_iterate_all )
	it( "Can iterate the same table multiple times", test_iterate_multiall )
	it( "Supports where clauses", test_where_normal )
	it( "Supports where with placeholders", test_where_withargs )
	it( "Doesn't break if where returns no rows", test_where_norows )
	it( "Can select a row", test_select )
	it( "Can select via metamethod", test_select_meta )
	it( "Returns nil if selected row doesn't exist", test_select_nil )
	it( "Can select if a table is read-only", test_select_readonly )
	it( "Can rollback on a bad select", test_select_rollback )
	it( "Can insert rows", test_insert )
	it( "Can insert via metamethods", test_insert_meta )
	it( "Can update with string keys", test_update_varchar_key )
	it( "Can update with integer keys", test_update_integer_key )
	it( "Can update via metamethods", test_update_meta )
	it( "Fails when a key isn't provided to update", test_update_failure )
	it( "Can delete rows", test_delete )
	it( "Can delete via metamethods", test_delete_meta )
	it( "Fails when deleting without a key", test_delete_fails )
	it( "Can clone a table into a temporary one", test_clone )
	it( "Can clone part of a table into a temporary one", test_clone_where )
	it( "Can commit a transaction", test_transaction_commit )
	it( "Can rollback a transaction", test_transaction_rollback )
	it( "Won't double-commit a transaction", test_transaction_commit_fails )
	it( "Won't open two transactions", test_transaction_begin_fails )
	it( "Won't rollback a transaction twice", test_transaction_rollback_fails )
	it( "Can clone into a temporary table, with integer keys", test_iclone )
	it( "Can clone into an integer keys temp table, with a where clause ", test_iclone_where )
	it( "Can count rows of a table", test_count )
	it( "Can count a subset of a table", test_count_where )
	it( "Fails when updating a read-only table", test_error_readonly )
	it( "Rolls back a transaction on failures", test_error_rollback )
	it( "Has a debugging hook", test_debugging_hook )
	it( "Can disable a debugging hook", test_debugging_hook_disable )
	it( "Has an execute function", test_execute )
	it( "Can recover from a failed execute callback", test_execute_callback_fails )
	it( "Can execute without a callback", test_execute_nocallback )
	it( "Can recover if SQL code isn't valid", test_execute_prepare_fails )
	
	if _VERSION ~= 'Lua 5.1' then
		it( "Can count rows with the length operator", test_count_lenop )
		it( "Can iterate a table using pairs", test_iterate_meta_pairs )
		it( "Can iterate a table using ipairs", test_iterate_meta_ipairs )
	end
	
	teardown(teardown_tests)
	
end)
