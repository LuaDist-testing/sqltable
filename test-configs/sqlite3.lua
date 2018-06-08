#!/usr/bin/env lua


return {

	connection = {
		type = 'SQLite3',
		name = 'sqlite3-test',
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

