#!/usr/local/bin/lua

--
-- This is part of the release script.
--
-- See release.sh for more explanation.
--


sql = dofile("./sqltable.lua")
print(sql.VERSION)
