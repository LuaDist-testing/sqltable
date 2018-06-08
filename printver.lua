#!/usr/bin/env lua5.3

--
-- This is part of the release script.
--
-- See release.sh for more explanation.
--
package.path = "../?.lua;" .. package.path
require "luarocks.loader"

sql = dofile("./sqltable.lua")
print(sql.VERSION)
