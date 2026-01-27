-- Benchmark StateManager access performance
package.path = package.path .. ';../?.lua;./?.lua'
local StateManager = require('rife_state_manager')
local sm = StateManager:new("bench_pid")
sm:activate_rife("normal")
sm:set_fullscreen(true)
sm:set_pipeline_targets(1920, 1080, true)

local start = os.clock()
for i = 1, 100000 do
  sm:get_rife_active()
  sm:get_target_w()
  sm:get_target_h()
  sm:should_activate_vsr()
end
local elapsed = os.clock() - start

local total_calls = 100000 * 4
local us_per_call = (elapsed / total_calls) * 1000000

print(string.format("StateManager Access Benchmark:"))
print(string.format("  %d total calls: %.3fs", total_calls, elapsed))
print(string.format("  %.3fμs per call", us_per_call))
print(string.format("  %d calls per second", math.floor(total_calls / elapsed)))

if us_per_call < 100 then
  print("  ✅ PASS: <0.1ms per call (<100μs)")
else
  print("  ❌ FAIL: >=0.1ms per call (>=100μs)")
end
