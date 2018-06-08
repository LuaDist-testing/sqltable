#!/usr/bin/env lua


local DBI = require "DBI"



---
-- A connection pooling object.
--
-- This allows for lots of tables to be opened with only
-- as many connections as are needed to be created. Also,
-- it provides for some level of fault tolerance: stale connections
-- are automatically purged.
--
local _pool = {}


--
-- We need coroutine-safe pcall. Lua 5.2 can do it, but Lua 5.1
-- needs a helper library to do it
--
local _pcall
if _VERSION == 'Lua 5.1' then
	assert(require "coxpcall", "coxpcall required for Lua 5.1")
	_pcall = copcall
else
	_pcall = pcall
end


---
-- Opens a new connection.
--
local function open( params )

	local connect_args = {
			params.type,
			params.name,
			params.user,
			params.pass or nil,
			params.host or 'localhost',
			params.port or 5432
		}
		
	local connection = assert(DBI.Connect(unpack(connect_args)))
	
	return {
			connection = connection,
			--statements = {}
		}

end


---
-- Set a debugging callback that displays code being passed through
-- this pool.
--
function _pool.debugging( pool, fcn )

	local meta = getmetatable(pool)
	
	-- nil means disable.
	if not fcn then
		meta.debugging = nil
		return
	end
	
	assert(
		type(fcn) == 'function', 
		'You lied to me when you told me this was a function.'
	)
	
	meta.debugging = fcn

end


---
-- Return the type of database this pool connects to.
--
function _pool.type( pool )
	return getmetatable(pool).type
end


---
-- Checkout a connection from the pool for use.
--
function _pool.get( pool )

	local meta = getmetatable(pool)
	local ret = nil
	
	if #(meta.connections) > 0 then
		--meta.outstanding = meta.outstanding + 1
		ret = table.remove(meta.connections, 1)
	else	
		-- create a new one.
		--meta.outstanding = meta.outstanding + 1
		ret = open( meta.params )
	end

	-- make sure there isn't a transaction active with this
	-- connection.
	ret.connection:rollback()

	meta.outstanding[ ret ] = true
	return ret
end


---
-- Return a connection to the pool.
--
function _pool.put( pool, connection )

	local meta = getmetatable(pool)
	
	-- Guard against a particularly bad programming mistake
	assert(
		connection.connection, 
		"This doesn't look like a valid database connection"
	)
	
	-- make sure the connection is alive before placing it in the
	-- pool.
	if not connection.connection:ping() then 
		meta.outstanding[ connection ] = nil
		return 
	end
	
	table.insert(meta.connections, connection)
	
	-- bootstrapping: outstanding is nil when the first connection
	-- is handed to this method.
	if not meta.outstanding then
		meta.outstanding = {}
	else
		meta.outstanding[ connection ] = nil
	end

end


---
-- Helper function: wrap all DB operations in a try/catch
-- block to ensure we always return the database connection,
-- and in a sane state as well.
--
-- @param pool Pool being accessed
-- @param code SQL code to execute (string)
-- @param values Table of values to bind to SQL placeholders. 
--					Pass an empty table or nil if no data is to be
--					bound.
-- @param callback Callback function that receives the result of the
--					query. It is given two arguments: the connection
--					and a statement object. Both of these are raw LuaDBI
--					Userdata, consult it's manual for usage.
--
function _pool.exec( pool, code, values, callback )

	local meta = getmetatable(pool)
	local xc = pool:get()
	local statement = nil

	values = values or {}

	local success, err = _pcall(function()

		if meta.debugging then
			meta.debugging( code, values or {} )
		end
		statement = assert(xc.connection:prepare(code))

		if values then
			assert(statement:execute( unpack(values) ))
		else
			assert(statement:execute())
		end
		
		-- callback is optional.
		if callback then
			callback( xc.connection, statement )
		end
	
	end)

	if not success then

		if statement then
			pcall(statement.close, statement)
		end
		
		pcall(xc.connection.rollback, xc.connection)
		pool:put(xc)
	
		-- bubble the error back to the top.
		error(err)
		
	end
		
	statement:close()
	xc.connection:commit()	
	pool:put(xc)

end


---
-- Returns a count of the total number of connections this
-- pool has open.
--
function _pool.connections( pool )

	local meta = getmetatable(pool)
	return #meta.connections + pool:outstanding()

end


---
-- Returns a count of connections that exist, but are in use
-- and not waiting in the pool.
--
function _pool.outstanding( pool )

	local meta = getmetatable(pool)
	local sum = 0
	
	for k, v in pairs(meta.outstanding) do sum = sum + 1 end
	return sum
	
end


---
-- Close the connection handed to us, for any reason.
--
-- Since the connection could be bad, pcall() everything.
--
local function close_connection( connection )

	--for i, statement in ipairs(connection.statements) do
		--pcall(statement.close, statement)
	--end
		
	if connection.connection:ping() then
		pcall(connection.connection.close, connection.connection)
	end
		
end



---
-- Shuts down the pool.
--
-- THIS EXPLODES BADLY if there are outstanding connections not
-- yet returned. Stop all queries before calling it!
--
function _pool.close( pool )

	local meta = getmetatable(pool)
	
	if pool:outstanding() > 0 then
		error("Cannot close: "..pool:outstanding().." connections not returned.")
	end

	for i, connection in ipairs(meta.connections) do
		close_connection(connection)
	end
	
	-- break the pool object. It's closed, right?
	setmetatable(
		pool, 
		{ 
			__index = function() error("pool is closed") end,
			__newindex = function() error("pool is closed") end
		}
	)

end


---
-- Resets a pool by closing all connections, then reconnecting
-- with just one. This is handy if your program forks and/or you
-- want to recycle all file handles.
--
function _pool.reset( pool )

	local meta = getmetatable(pool)
	
	if pool:outstanding() > 0 then
		error("Cannot reset: "..pool:outstanding().." connections not returned.")
	end
	
	for i, connection in ipairs(meta.connections) do
		close_connection(connection)
	end

	-- reopen.
	meta.connections = {}
	meta.outstanding = nil
	pool:put( open( meta.params ) )

end


---
-- Methods for the pool object.
--
local _methods = {

	-- set readonly
	__newindex = function() end

}


---
-- "Connect" to a database. This opens the first connection to
-- a database to ensure the settings are correct, then returns
-- a pool object containing one connection.
--
function _pool.connect( params )

	assert(type(params) == 'table', "No connection args!")
	assert(params.type, "Database type must be provided")
	assert(params.name, "Database name must be provided")
	
	if not params.type == 'SQLite3' then
		assert(params.user, "Database user must be provided")
	end

	local ret = {}
	local ret_meta = {
	
		connections = {},
		params = params,
		type = params.type
	
	}
	
	for name, method in pairs(_pool) do
		ret[name] = method
	end
	
	for name, method in pairs(_methods) do
		ret_meta[name] = method
	end
	
	ret.connect = nil
	setmetatable(ret, ret_meta)
	ret:put(open( params ))
	
	return ret
	
end


return _pool
