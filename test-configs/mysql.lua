#!/usr/bin/env lua


return {

	connection = {
		type = 'MySQL',
		host = 'mysqlserver.zadzmo.org',
		port = 3306,
		name = 'sqltable',
		user = 'sqltable',
		pass = 'testing12345!!!'
	},
	
	table1_vendor = {
		booleans = { 'flag1', 'flag2' }
	},
	table2_vendor = {
	},
	table3_vendor = {
		booleans = { 'flag1', 'flag2' }
	}
}

