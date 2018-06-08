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


say:set(
	"assertion.is_gte.failed", 
	"Expected number to be equal or larger.\nPassed in: \n%s\nExpected:\n%s"
)

luaassert:register(
	"assertion", "is_gte", gte, "assertion.is_gte.failed"
) 

require 'busted.runner'()
sqltable = require "sqltable.pool"


local function setup()

	return sqltable.connect( config.connection )

end


--
-- Test we can open a connection pool.
--
function test_pool_create()

	local t = setup()
	
	assert.is_table(t)
	assert.is_equal(config.connection.type, t:type())
	assert.is_equal(1, t:connections())

	t:close()

end


--
-- Test we can grab one of these connections.
--
function test_pool_get()

	local t = setup()
	local conn = t:get()
	
	assert.is_table(conn)
	assert.is_userdata(conn.conn) -- great, isn't it?
	
	t:put(conn)
	t:close()
	
end


--
-- Test that we can get more than one, and that they are
-- different.
--
function test_pool_multiget()

	local t = setup()
	
	assert.is_equal(1, t:connections())
	assert.is_equal(0, t:outstanding())
	
	local conn1 = t:get()
	local conn2 = t:get()
	local conn3 = t:get()
	
	assert.is_equal(3, t:connections())
	assert.is_equal(3, t:outstanding())
	
	assert.is_table(conn1)
	assert.is_table(conn2)
	assert.is_table(conn3)
	
	assert.is_not_equal(conn1, conn2)
	assert.is_not_equal(conn1, conn3)
	assert.is_not_equal(conn2, conn3)

	t:put(conn1)
	assert.is_equal(3, t:connections())
	assert.is_equal(2, t:outstanding())
	
	t:put(conn3)
	t:put(conn2)
	
	assert.is_equal(3, t:connections())
	assert.is_equal(0, t:outstanding())

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
	
	assert.is_equal(3, t:connections())
	assert.is_equal(3, t:outstanding())
	
	t:put(conn1)
	t:put(conn2)
	t:put(conn3)
	
	assert.is_equal(3, t:connections())
	assert.is_equal(0, t:outstanding())
	
	t:reset()

	assert.is_false(conn1:ping())
	assert.is_false(conn2:ping())
	assert.is_false(conn3:ping())
	
	assert.is_equal(1, t:connections())
	assert.is_equal(0, t:outstanding())
	
	t:reset()
	
	conn1 = t:get()
	
	assert.is_table(conn1)
	t:put(conn1)
	t:put(conn2)	-- this one is dead, and thus should be kicked out
					-- by the pool.

	assert.is_equal(1, t:connections())
	assert.is_equal(0, t:outstanding())
	
	t:close()
	
end


--
-- Test that closing with an outstanding connection
-- doesn't happen.
--
function test_pool_error_on_close()

	local t = setup()
		
	local conn = t:get()
	
	assert.is_error(function() t:close() end)
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
		
			assert.is_string(sql)
			assert.is_table(args)
			assert.is_equal(0, #args)
			called = true
		
		end )
		
		t:exec( code, nil, function( c, s ) end )
		assert.is_equal(code, hook)
		assert.is_true(called)

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

		assert.is_equal(code1, hook)
		assert.is_true(called)
		
		called = false
		hook = nil
		
		t:debugging()
		t:exec( code2, nil, function( c, s ) end )
		assert.is_nil(hook)
		assert.is_false(called)
		
end


--
-- Test that a connection caches statements.
--
function test_cache()

	local t = setup()
	local conn = t:get()
	
	local hits, misses

	assert.is_number(conn.hits)
	assert.is_number(conn.misses)

	hits = conn.hits
	misses = conn.misses
	
	local query_code = "select '" .. os.date() .. "' as nowtime"
	local query = conn:prepare(query_code)
	
	assert.is_equal(conn.misses, misses + 1)
	assert.is_equal(conn.hits, hits)
	assert.is_equal(1, conn:statement_count())
	
	local new_query = conn:prepare(query_code)
	
	assert.is_gte(conn.misses, misses + 1)
	assert.is_equal(conn.hits, hits + 1)
	assert.is_equal(query, new_query)
	assert.is_equal(1, conn:statement_count())
	
	t:put(conn)

end


--
-- Test that a connection caches multiple statements.
--
function test_cache_multi()

	local t = setup()
	local conn = t:get()
	
	local hits, misses

	assert.is_number(conn.hits)
	assert.is_number(conn.misses)

	hits = conn.hits
	misses = conn.misses
	
	local query_code = "select '" .. os.date() .. "' as nowtime"
	local query = conn:prepare(query_code)
	
	assert.is_equal(conn.misses, misses + 1)
	assert.is_equal(conn.hits, hits)
	assert.is_equal(1, conn:statement_count())
	
	local new_query_code = "select '" .. os.date() .. "' as anothertime"
	local new_query = conn:prepare(new_query_code)
	
	assert.is_gte(conn.misses, misses + 2)
	assert.is_equal(conn.hits, hits)
	assert.is_not_equal(query, new_query)
	assert.is_equal(2, conn:statement_count())
	
	t:put(conn)
	
end


--
-- Test that a failed prepare doesn't leave a broken statement
-- in the cache.
--
function test_cache_prepare_failure()

	local t = setup()
	local conn = t:get()
	
	local hits, misses
	
	assert.is_equal(0, conn.hits)
	assert.is_equal(0, conn:statement_count())
	
	local statement, err = conn:prepare("fail me 3ijr23ifm23irm2")
	
	assert.is_nil(statement)
	assert.is_string(err)

	assert.is_equal(0, conn.hits)
	assert.is_equal(0, conn.misses)
	assert.is_equal(0, conn:statement_count())
	
	t:put(conn)
	
end


describe("PostgreSQL #postgres", function()
	db_type = "postgres"
	config = dofile("test-configs/" .. db_type .. ".lua")
	local env

	it( "Can be created", test_pool_create )
	it( "Can't close with outstanding connections", test_pool_error_on_close )
	it( "Can provide a connection", test_pool_get )
	it( "Can provide many connections", test_pool_multiget )
	it( "Can be reset", test_reset )
	it( "Can cache prepared statements", test_cache )
	it( "Can cache mulitple prepared statements", test_cache_multi )
	it( "Doesn't cache statements if prepare fails", test_cache_prepare_failure )

end)

describe("MySQL #mysql", function()
	db_type = "mysql"
	config = dofile("test-configs/" .. db_type .. ".lua")
	local env

	it( "Can be created", test_pool_create )
	it( "Can't close with outstanding connections", test_pool_error_on_close )
	it( "Can provide a connection", test_pool_get )
	it( "Can provide many connections", test_pool_multiget )
	it( "Can be reset", test_reset )
	it( "Can cache prepared statements", test_cache )
	it( "Can cache mulitple prepared statements", test_cache_multi )
	it( "Doesn't cache statements if prepare fails", test_cache_prepare_failure )

end)

describe("SQLite3 #sqlite", function()
	db_type = "sqlite3"
	config = dofile("test-configs/" .. db_type .. ".lua")
	local env

	it( "Can be created", test_pool_create )
	it( "Can't close with outstanding connections", test_pool_error_on_close )
	it( "Can provide a connection", test_pool_get )
	it( "Can provide many connections", test_pool_multiget )
	it( "Can be reset", test_reset )
	it( "Can cache prepared statements", test_cache )
	it( "Can cache mulitple prepared statements", test_cache_multi )
	it( "Doesn't cache statements if prepare fails", test_cache_prepare_failure )

end)
