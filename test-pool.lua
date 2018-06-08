#!/usr/bin/env lua

pcall(require, "luacov")    --measure code coverage, if luacov is present

require "luarocks.loader"
lunatest = require "lunatest"
sqltable = require "sqltable.pool"


local db_type = arg[ #arg ]
assert(db_type, "Must specify database type")

local config = dofile("test-configs/" .. db_type .. ".lua")
assert(config, "Didn't find database connection args to load")



local function setup()

	return sqltable.connect( config.connection )

end


--
-- Test we can open a connection pool.
--
function test_pool_create()

	local t = setup()
	
	assert_table(t)
	assert_equal(config.connection.type, t:type())
	assert_equal(1, t:connections())

	t:close()

end


--
-- Test we can grab one of these connections.
--
function test_pool_get()

	local t = setup()
	local conn = t:get()
	
	assert_table(conn)
	assert_userdata(conn.connection)
	--assert_table(conn.statements)
	
	t:put(conn)
	t:close()
	
end


--
-- Test that we can get more than one, and that they are
-- different.
--
function test_pool_multiget()

	local t = setup()
	
	assert_equal(1, t:connections())
	assert_equal(0, t:outstanding())
	
	local conn1 = t:get()
	local conn2 = t:get()
	local conn3 = t:get()
	
	assert_equal(3, t:connections())
	assert_equal(3, t:outstanding())
	
	assert_table(conn1)
	assert_table(conn2)
	assert_table(conn3)
	
	assert_not_equal(conn1, conn2)
	assert_not_equal(conn1, conn3)
	assert_not_equal(conn2, conn3)

	t:put(conn1)
	assert_equal(3, t:connections())
	assert_equal(2, t:outstanding())
	
	t:put(conn3)
	t:put(conn2)
	
	assert_equal(3, t:connections())
	assert_equal(0, t:outstanding())

	t:close()

end


--
-- Test the execute function.
--
-- This test might not pass in all databases...
--
function test_execute()

	local t = setup()
	
	t:exec( "select 1 as one", nil, function( connection, statement )
	
		local row = statement:fetch(true)
		assert_table(row)
		assert_equal(1, row.one)
	
	end)
	
	assert_equal(0, t:outstanding())
	assert_gte(1, t:connections())

	t:close()

end


--
-- Test the execute function, without a callback function.
--
-- The result should be the same as above.
--
function test_execute()

	local t = setup()
	
	t:exec( "select 1 as one", nil)
	
	assert_equal(0, t:outstanding())
	assert_gte(1, t:connections())

	t:close()

end


--
-- Test that a failure to prepare code in the execute function
-- doesn't hurt the pool.
--
function test_execute_prepare_fails()

	local t = setup()
	
	assert_error(function()
		t:exec( "s43fuin23m4ruin34e", nil, function( connection, statement )
		end)
	end)

	assert_equal(0, t:outstanding())
	assert_gte(1, t:connections())

	t:close()

end


--
-- Test that a callback failure doesn't hurt the pool.
--
function test_execute_callback_fails()

	local t = setup()
	
	assert_error(function()
		t:exec( "select 1 as one", nil, function( connection, statement )
			error("break me")
		end)
	end)
	
	assert_equal(0, t:outstanding())
	assert_gte(1, t:connections())

	t:close()
end


--
-- Test that a reset works.
--
function test_reset()

	local t = setup()
	
	local conn1 = t:get()
	local conn2 = t:get()
	local conn3 = t:get()
	
	assert_equal(3, t:connections())
	assert_equal(3, t:outstanding())
	
	t:put(conn1)
	t:put(conn2)
	t:put(conn3)
	
	assert_equal(3, t:connections())
	assert_equal(0, t:outstanding())
	
	t:reset()

	assert_false(conn1.connection:ping())
	assert_false(conn2.connection:ping())
	assert_false(conn3.connection:ping())
	
	assert_equal(1, t:connections())
	assert_equal(0, t:outstanding())
	
	t:reset()
	
	conn1 = t:get()
	
	assert_table(conn1)
	t:put(conn1)
	t:put(conn2)	-- this one is dead, and thus should be kicked out
					-- by the pool.

	assert_equal(1, t:connections())
	assert_equal(0, t:outstanding())
	
	t:close()
	
end


--
-- Test that closing with an outstanding connection
-- doesn't happen.
--
function test_pool_error_on_close()

	local t = setup()
		
	local conn = t:get()
	
	assert_error(function() t:close() end)
	t:put(conn)
	t:close()

end


--
-- Test the debugging hook.
--
function test_debugging_hook()

		local t = setup()
		local code = "select 1 as one"
		local hook = nil
		local called = false
		
		t:debugging( function( sql, args ) hook = sql 
		
			assert_string(sql)
			assert_table(args)
			assert_equal(0, #args)
			called = true
		
		end )
		
		t:exec( code, nil, function( c, s ) end )
		assert_equal(code, hook)
		assert_true(called)

end


--
-- Test disabling the debugging hook.
--
function test_debugging_hook_disable()

		local t = setup()
		local code1 = "select 1 as one"
		local code2 = "select 2 as two"
		local hook = nil
		local called = false
		
		t:debugging( function( sql, args ) hook = sql called = true end )
		t:exec( code1, nil, function( c, s ) end )

		assert_equal(code1, hook)
		assert_true(called)
		
		called = false
		hook = nil
		
		t:debugging()
		t:exec( code2, nil, function( c, s ) end )
		assert_nil(hook)
		assert_false(called)
		
end



lunatest.run()
