-- Test runner for rife_core
package.path = package.path .. ';../?.lua;./?.lua'

local lu = require('luaunit')

-- Import test modules
require('test_rife_core')
require('test_rife_state_manager')
require('test_rife_template_loader')

-- Run tests
os.exit(lu.LuaUnit.run())
