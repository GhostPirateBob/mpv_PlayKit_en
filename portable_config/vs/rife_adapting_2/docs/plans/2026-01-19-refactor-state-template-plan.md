# Implementation Plan - StateManager & Template Refactor

> **Reference:** `docs/designs/2026-01-19-refactor-state-template-design.md`
> **Execution:** Use `executing-plans` skill.

## Overview

This plan implements the StateManager and Template extraction refactor across 4 phases:
- **Phase 1:** StateManager Foundation (basic getters/setters, no validation)
- **Phase 2:** Validation & Invariants (strict transition checking)
- **Phase 3:** Template Extraction (external template file)
- **Phase 4:** Integration & Testing (manual mpv testing, performance profiling)

**Estimated Time:** 6-10 hours total
**Testing Strategy:** Pure Lua unit tests (no Python/VPY integration)

---

## Phase 1: StateManager Foundation

### Task 1.1: Create StateManager File Structure

**Goal:** Create empty StateManager module with basic metatable setup

**Step 1: Write the Failing Test**
- File: `tests/test_rife_state_manager.lua`
- Code:
```lua
local lu = require('luaunit')
local StateManager = require('rife_state_manager')

TestStateManagerNew = {}

function TestStateManagerNew:test_creates_state_manager()
  local sm = StateManager:new("123")
  lu.assertNotNil(sm)
  lu.assertEquals(sm:get_pid(), "123")
end

function TestStateManagerNew:test_initial_state_defaults()
  local sm = StateManager:new("456")
  lu.assertFalse(sm:get_rife_active())
  lu.assertFalse(sm:get_vsr_only_mode())
  lu.assertNil(sm:get_current_crop())
  lu.assertNil(sm:get_cropdetect_timer())
  lu.assertFalse(sm:get_is_fullscreen())
  lu.assertNil(sm:get_target_w())
  lu.assertNil(sm:get_target_h())
  lu.assertFalse(sm:get_vsr_path_active())
end
```

**Step 2: Run Test (Red)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua`
- Expect: "module 'rife_state_manager' not found"

**Step 3: Implementation (Green)**
- File: `rife_state_manager.lua`
- Action: Create StateManager module with metatable and private state
- Code:
```lua
-- rife_state_manager.lua - State encapsulation with validation

local StateManager = {}
StateManager.__index = StateManager

-- Create new state instance
function StateManager:new(pid)
  local state = {
    -- Private state (closure-based privacy with underscore convention)
    _rife_active = false,
    _vsr_only_mode = false,
    _current_crop = nil,
    _cropdetect_timer = nil,
    _is_fullscreen = false,
    _target_w = nil,
    _target_h = nil,
    _vsr_path_active = false,
    _pid = pid
  }

  return setmetatable(state, self)
end

-- Getters
function StateManager:get_pid()
  return self._pid
end

function StateManager:get_rife_active()
  return self._rife_active
end

function StateManager:get_vsr_only_mode()
  return self._vsr_only_mode
end

function StateManager:get_current_crop()
  return self._current_crop
end

function StateManager:get_cropdetect_timer()
  return self._cropdetect_timer
end

function StateManager:get_is_fullscreen()
  return self._is_fullscreen
end

function StateManager:get_target_w()
  return self._target_w
end

function StateManager:get_target_h()
  return self._target_h
end

function StateManager:get_vsr_path_active()
  return self._vsr_path_active
end

return StateManager
```

**Step 4: Verify (Green)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua`
- Expect: PASS

**Step 5: Git Commit**
- Command: `git add rife_state_manager.lua tests/test_rife_state_manager.lua && git commit -m "feat: add StateManager foundation with basic getters"`

---

### Task 1.2: Implement activate_rife() Method

**Goal:** Add RIFE activation with mode selection (normal/vsr_only)

**Step 1: Write the Failing Test**
- File: `tests/test_rife_state_manager.lua`
- Code:
```lua
TestStateManagerActivate = {}

function TestStateManagerActivate:test_activate_normal_mode()
  local sm = StateManager:new("789")
  local success, err = sm:activate_rife("normal")

  lu.assertTrue(success)
  lu.assertNil(err)
  lu.assertTrue(sm:get_rife_active())
  lu.assertFalse(sm:get_vsr_only_mode())
end

function TestStateManagerActivate:test_activate_vsr_only_mode()
  local sm = StateManager:new("790")
  local success, err = sm:activate_rife("vsr_only")

  lu.assertTrue(success)
  lu.assertNil(err)
  lu.assertTrue(sm:get_rife_active())
  lu.assertTrue(sm:get_vsr_only_mode())
end

function TestStateManagerActivate:test_double_activation_fails()
  local sm = StateManager:new("791")
  sm:activate_rife("normal")

  local success, err = sm:activate_rife("vsr_only")
  lu.assertFalse(success)
  lu.assertStrContains(err, "already active")
end

function TestStateManagerActivate:test_invalid_mode_fails()
  local sm = StateManager:new("792")
  local success, err = sm:activate_rife("invalid")

  lu.assertFalse(success)
  lu.assertStrContains(err, "Invalid mode")
end
```

**Step 2: Run Test (Red)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua`
- Expect: "attempt to call method 'activate_rife'"

**Step 3: Implementation (Green)**
- File: `rife_state_manager.lua`
- Action: Add activate_rife() method after get_pid()
- Code:
```lua
-- Activate RIFE (normal or vsr-only mode)
-- Returns: (success, error_message)
function StateManager:activate_rife(mode)
  -- Validate not already active
  if self._rife_active then
    return false, "RIFE already active"
  end

  -- Validate mode
  if mode ~= "normal" and mode ~= "vsr_only" then
    return false, "Invalid mode: " .. tostring(mode)
  end

  -- Set state
  self._rife_active = true
  self._vsr_only_mode = (mode == "vsr_only")

  return true, nil
end
```

**Step 4: Verify (Green)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua`
- Expect: PASS

**Step 5: Git Commit**
- Command: `git add rife_state_manager.lua tests/test_rife_state_manager.lua && git commit -m "feat: add activate_rife() with mode validation"`

---

### Task 1.3: Implement deactivate_rife() Method

**Goal:** Add RIFE deactivation with full state reset

**Step 1: Write the Failing Test**
- File: `tests/test_rife_state_manager.lua`
- Code:
```lua
TestStateManagerDeactivate = {}

function TestStateManagerDeactivate:test_deactivate_normal_mode()
  local sm = StateManager:new("801")
  sm:activate_rife("normal")
  sm:set_crop_detection_timer("dummy_timer")
  sm:set_pipeline_targets(1920, 1080, true)

  sm:deactivate_rife()

  lu.assertFalse(sm:get_rife_active())
  lu.assertFalse(sm:get_vsr_only_mode())
  lu.assertNil(sm:get_current_crop())
  lu.assertNil(sm:get_cropdetect_timer())
  lu.assertNil(sm:get_target_w())
  lu.assertNil(sm:get_target_h())
  lu.assertFalse(sm:get_vsr_path_active())
end

function TestStateManagerDeactivate:test_deactivate_when_inactive_is_noop()
  local sm = StateManager:new("802")
  -- Should not error
  sm:deactivate_rife()
  lu.assertFalse(sm:get_rife_active())
end
```

**Step 2: Run Test (Red)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua`
- Expect: "attempt to call method 'deactivate_rife'"

**Step 3: Implementation (Green)**
- File: `rife_state_manager.lua`
- Action: Add deactivate_rife() and set_crop_detection_timer() and set_pipeline_targets() methods
- Code:
```lua
-- Deactivate RIFE (reset all state)
function StateManager:deactivate_rife()
  self._rife_active = false
  self._vsr_only_mode = false
  self._current_crop = nil
  self._cropdetect_timer = nil
  self._target_w = nil
  self._target_h = nil
  self._vsr_path_active = false
  -- Note: is_fullscreen and pid are preserved
end

-- Set crop detection timer (pending detection)
function StateManager:set_crop_detection_timer(timer)
  self._cropdetect_timer = timer
end

-- Set pipeline targets after resolution calculation
function StateManager:set_pipeline_targets(w, h, vsr_path)
  self._target_w = w
  self._target_h = h
  self._vsr_path_active = vsr_path
end
```

**Step 4: Verify (Green)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua`
- Expect: PASS

**Step 5: Git Commit**
- Command: `git add rife_state_manager.lua tests/test_rife_state_manager.lua && git commit -m "feat: add deactivate_rife() with full state reset"`

---

### Task 1.4: Implement set_fullscreen() and Query Methods

**Goal:** Add fullscreen setter and VSR eligibility query

**Step 1: Write the Failing Test**
- File: `tests/test_rife_state_manager.lua`
- Code:
```lua
TestStateManagerFullscreen = {}

function TestStateManagerFullscreen:test_set_fullscreen_true()
  local sm = StateManager:new("901")
  sm:set_fullscreen(true)
  lu.assertTrue(sm:get_is_fullscreen())
end

function TestStateManagerFullscreen:test_set_fullscreen_false()
  local sm = StateManager:new("902")
  sm:set_fullscreen(false)
  lu.assertFalse(sm:get_is_fullscreen())
end

TestStateManagerQueries = {}

function TestStateManagerQueries:test_should_activate_vsr_all_true()
  local sm = StateManager:new("903")
  sm:activate_rife("normal")
  sm:set_fullscreen(true)
  sm:set_pipeline_targets(1920, 1080, true)

  lu.assertTrue(sm:should_activate_vsr())
end

function TestStateManagerQueries:test_should_activate_vsr_not_fullscreen()
  local sm = StateManager:new("904")
  sm:activate_rife("normal")
  sm:set_fullscreen(false)  -- Not fullscreen
  sm:set_pipeline_targets(1920, 1080, true)

  lu.assertFalse(sm:should_activate_vsr())
end

function TestStateManagerQueries:test_should_activate_vsr_not_active()
  local sm = StateManager:new("905")
  sm:set_fullscreen(true)
  sm:set_pipeline_targets(1920, 1080, true)

  lu.assertFalse(sm:should_activate_vsr())  -- RIFE not active
end

function TestStateManagerQueries:test_should_activate_vsr_vsr_path_inactive()
  local sm = StateManager:new("906")
  sm:activate_rife("normal")
  sm:set_fullscreen(true)
  sm:set_pipeline_targets(1920, 1080, false)  -- vsr_path=false

  lu.assertFalse(sm:should_activate_vsr())
end
```

**Step 2: Run Test (Red)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua`
- Expect: "attempt to call method 'set_fullscreen'"

**Step 3: Implementation (Green)**
- File: `rife_state_manager.lua`
- Action: Add set_fullscreen() and should_activate_vsr() methods
- Code:
```lua
-- Update fullscreen state
function StateManager:set_fullscreen(is_fullscreen)
  self._is_fullscreen = is_fullscreen
end

-- Query: should VSR activate now?
-- Returns true if: rife_active AND vsr_path_active AND is_fullscreen
function StateManager:should_activate_vsr()
  return self._rife_active and
         self._vsr_path_active and
         self._is_fullscreen
end
```

**Step 4: Verify (Green)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua`
- Expect: PASS

**Step 5: Git Commit**
- Command: `git add rife_state_manager.lua tests/test_rife_state_manager.lua && git commit -m "feat: add set_fullscreen() and should_activate_vsr() query"`

---

### Task 1.5: Implement complete_crop_detection() Method

**Goal:** Handle crop detection completion (store result, clear timer)

**Step 1: Write the Failing Test**
- File: `tests/test_rife_state_manager.lua`
- Code:
```lua
TestStateManagerCrop = {}

function TestStateManagerCrop:test_complete_crop_detection_with_result()
  local sm = StateManager:new("1001")
  sm:activate_rife("normal")
  sm:set_crop_detection_timer("timer_obj")

  local crop_result = {w = 1920, h = 1080, x = 0, y = 80}
  sm:complete_crop_detection(crop_result)

  lu.assertEquals(sm:get_current_crop(), crop_result)
  lu.assertNil(sm:get_cropdetect_timer())  -- Timer cleared
end

function TestStateManagerCrop:test_complete_crop_detection_no_bars()
  local sm = StateManager:new("1002")
  sm:activate_rife("normal")
  sm:set_crop_detection_timer("timer_obj")

  sm:complete_crop_detection(nil)  -- No black bars

  lu.assertNil(sm:get_current_crop())
  lu.assertNil(sm:get_cropdetect_timer())  -- Timer cleared
end
```

**Step 2: Run Test (Red)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua`
- Expect: "attempt to call method 'complete_crop_detection'"

**Step 3: Implementation (Green)**
- File: `rife_state_manager.lua`
- Action: Add complete_crop_detection() method
- Code:
```lua
-- Complete crop detection (store result, clear timer)
-- crop_result: {w, h, x, y} or nil (no black bars)
function StateManager:complete_crop_detection(crop_result)
  self._current_crop = crop_result
  self._cropdetect_timer = nil  -- Clear timer
end
```

**Step 4: Verify (Green)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua`
- Expect: PASS

**Step 5: Git Commit**
- Command: `git add rife_state_manager.lua tests/test_rife_state_manager.lua && git commit -m "feat: add complete_crop_detection() method"`

---

### Task 1.6: Integrate StateManager into rife_main.lua

**Goal:** Replace state table with StateManager instance

**Step 1: Manual Verification**
- File: `rife_main.lua`
- Action: Replace state table initialization (lines 51-61)
- Change:
```lua
-- OLD:
local state = {
    rife_active = false,
    current_crop = nil,
    cropdetect_timer = nil,
    is_fullscreen = false,
    target_w = nil,
    target_h = nil,
    vsr_path_active = false,
    vsr_only_mode = false,
    pid = mp.get_property_native("pid") or "0",
}

-- NEW:
local StateManager = require('rife_state_manager')
local state_manager = StateManager:new(mp.get_property_native("pid") or "0")
```

**Step 2: Replace Direct State Access with StateManager Methods**

Update all references to state table:

1. **toggle_rife() function (line 353-398):**
   - `state.rife_active` → `state_manager:get_rife_active()`
   - `state.vsr_only_mode` → `state_manager:get_vsr_only_mode()`
   - Activate: replace manual state setting with `state_manager:activate_rife(mode)`
   - Deactivate: replace manual reset with `state_manager:deactivate_rife()`

2. **update_vsr_state() function (line 102-142):**
   - `state.rife_active` → `state_manager:get_rife_active()`
   - `state.vsr_path_active` → `state_manager:get_vsr_path_active()`
   - `state.target_w` → `state_manager:get_target_w()`
   - `state.target_h` → `state_manager:get_target_h()`
   - `state.is_fullscreen` → `state_manager:get_is_fullscreen()`
   - VSR activation check: use `state_manager:should_activate_vsr()`

3. **generate_and_apply_vpy() function (line 206-347):**
   - `state.current_crop` → `state_manager:get_current_crop()`
   - After calculate_targets: add `state_manager:set_pipeline_targets(result.target_w, result.target_h, result.vsr_path)`
   - `state.target_w` → `state_manager:get_target_w()`
   - `state.target_h` → `state_manager:get_target_h()`
   - `state.vsr_path_active` → `state_manager:get_vsr_path_active()`

4. **finish_crop_detection() function (line 148-187):**
   - `state.cropdetect_timer` → `state_manager:get_cropdetect_timer()`
   - Replace manual crop storage with `state_manager:complete_crop_detection(state.current_crop)`

5. **start_crop_detection() function (line 189-196):**
   - Replace `state.cropdetect_timer = mp.add_timeout(...)` with `state_manager:set_crop_detection_timer(mp.add_timeout(...))`

6. **on_fullscreen_change() function (line 405-412):**
   - Replace `state.is_fullscreen = value` with `state_manager:set_fullscreen(value)`

**Step 3: Manual Test**
- Command: Open mpv, press Shift+6 to toggle RIFE
- Expect: No errors, OSD shows "ON" message
- Command: Toggle again to turn off
- Expect: OSD shows "OFF" message

**Step 4: Git Commit**
- Command: `git add rife_main.lua && git commit -m "refactor: integrate StateManager into rife_main.lua"`

---

## Phase 2: Validation & Invariants

### Task 2.1: Add Validation Helper Methods

**Goal:** Add internal validation functions for state invariants

**Step 1: Write the Failing Test**
- File: `tests/test_rife_state_manager.lua`
- Code:
```lua
TestStateManagerValidation = {}

function TestStateManagerValidation:test_set_crop_timer_without_rife_active_fails()
  local sm = StateManager:new("2001")
  -- RIFE not active, should fail to set timer

  -- This test verifies we're adding validation
  -- Implementation will be added in Task 2.2
end
```

**Step 2: Run Test (Red)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua`
- Expect: PASS (test is empty placeholder)

**Step 3: Implementation (Green)**
- File: `rife_state_manager.lua`
- Action: Add internal validation methods (private functions with underscore prefix)
- Code:
```lua
-- Internal validation helpers (private methods)

-- Check if RIFE is active in normal mode
function StateManager:_is_normal_mode_active()
  return self._rife_active and not self._vsr_only_mode
end

-- Validate crop detection timer can be set
function StateManager:_validate_can_start_crop_detection()
  if not self._rife_active then
    return false, "Cannot start crop detection: RIFE not active"
  end

  if self._vsr_only_mode then
    return false, "Cannot start crop detection in VSR-only mode"
  end

  if self._cropdetect_timer then
    return false, "Crop detection already in progress"
  end

  return true, nil
end

-- Validate pipeline targets can be set
function StateManager:_validate_can_set_targets()
  if not self._rife_active then
    return false, "Cannot set targets: RIFE not active"
  end

  return true, nil
end
```

**Step 4: Verify (Green)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua`
- Expect: PASS

**Step 5: Git Commit**
- Command: `git add rife_state_manager.lua && git commit -m "feat: add validation helper methods to StateManager"`

---

### Task 2.2: Add Validation to set_crop_detection_timer()

**Goal:** Validate crop detection can only start when RIFE active in normal mode

**Step 1: Write the Failing Test**
- File: `tests/test_rife_state_manager.lua`
- Code:
```lua
function TestStateManagerValidation:test_set_crop_timer_without_rife_active_fails()
  local sm = StateManager:new("2002")
  local success, err = sm:set_crop_detection_timer("dummy")

  lu.assertFalse(success)
  lu.assertStrContains(err, "RIFE not active")
end

function TestStateManagerValidation:test_set_crop_timer_in_vsr_only_mode_fails()
  local sm = StateManager:new("2003")
  sm:activate_rife("vsr_only")

  local success, err = sm:set_crop_detection_timer("dummy")

  lu.assertFalse(success)
  lu.assertStrContains(err, "VSR-only mode")
end

function TestStateManagerValidation:test_set_crop_timer_when_already_active_fails()
  local sm = StateManager:new("2004")
  sm:activate_rife("normal")
  sm:set_crop_detection_timer("timer1")

  local success, err = sm:set_crop_detection_timer("timer2")

  lu.assertFalse(success)
  lu.assertStrContains(err, "already in progress")
end

function TestStateManagerValidation:test_set_crop_timer_in_normal_mode_succeeds()
  local sm = StateManager:new("2005")
  sm:activate_rife("normal")

  local success, err = sm:set_crop_detection_timer("dummy")

  lu.assertTrue(success)
  lu.assertNil(err)
  lu.assertEquals(sm:get_cropdetect_timer(), "dummy")
end
```

**Step 2: Run Test (Red)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua`
- Expect: "2 failures" (set_crop_detection_timer doesn't return success/error tuple)

**Step 3: Implementation (Green)**
- File: `rife_state_manager.lua`
- Action: Modify set_crop_detection_timer() to return (success, error) and validate
- Code:
```lua
-- Set crop detection timer (pending detection)
-- Returns: (success, error_message)
function StateManager:set_crop_detection_timer(timer)
  local valid, err = self:_validate_can_start_crop_detection()
  if not valid then
    return false, err
  end

  self._cropdetect_timer = timer
  return true, nil
end
```

**Step 4: Update rife_main.lua to Handle Validation Errors**
- File: `rife_main.lua`
- Action: Update start_crop_detection() function (line 189-196)
- Change:
```lua
-- OLD:
state.cropdetect_timer = mp.add_timeout(1.0, finish_crop_detection)

-- NEW:
local timer = mp.add_timeout(1.0, finish_crop_detection)
local success, err = state_manager:set_crop_detection_timer(timer)
if not success then
    mp.msg.error("[rife_adaptive][CROP] " .. err)
    timer:kill()
    return
end
```

**Step 5: Verify (Green)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua`
- Expect: PASS

**Step 6: Manual Test**
- Command: Open mpv with high-fps video (60fps)
- Action: Press Shift+6 to toggle RIFE
- Expect: VSR-only mode activates (no crop detection)
- Command: Check mpv log
- Expect: No crop detection errors

**Step 7: Git Commit**
- Command: `git add rife_state_manager.lua rife_main.lua tests/test_rife_state_manager.lua && git commit -m "feat: add validation to set_crop_detection_timer()"`

---

### Task 2.3: Add Validation to set_pipeline_targets()

**Goal:** Validate targets can only be set when RIFE is active

**Step 1: Write the Failing Test**
- File: `tests/test_rife_state_manager.lua`
- Code:
```lua
function TestStateManagerValidation:test_set_targets_without_rife_active_fails()
  local sm = StateManager:new("2006")
  local success, err = sm:set_pipeline_targets(1920, 1080, true)

  lu.assertFalse(success)
  lu.assertStrContains(err, "RIFE not active")
end

function TestStateManagerValidation:test_set_targets_when_active_succeeds()
  local sm = StateManager:new("2007")
  sm:activate_rife("normal")

  local success, err = sm:set_pipeline_targets(1920, 1080, true)

  lu.assertTrue(success)
  lu.assertNil(err)
  lu.assertEquals(sm:get_target_w(), 1920)
  lu.assertEquals(sm:get_target_h(), 1080)
  lu.assertTrue(sm:get_vsr_path_active())
end
```

**Step 2: Run Test (Red)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua`
- Expect: "1 failure" (set_pipeline_targets doesn't return success/error tuple)

**Step 3: Implementation (Green)**
- File: `rife_state_manager.lua`
- Action: Modify set_pipeline_targets() to return (success, error) and validate
- Code:
```lua
-- Set pipeline targets after resolution calculation
-- Returns: (success, error_message)
function StateManager:set_pipeline_targets(w, h, vsr_path)
  local valid, err = self:_validate_can_set_targets()
  if not valid then
    return false, err
  end

  self._target_w = w
  self._target_h = h
  self._vsr_path_active = vsr_path
  return true, nil
end
```

**Step 4: Update rife_main.lua to Handle Validation Errors**
- File: `rife_main.lua`
- Action: Update generate_and_apply_vpy() function (after line 224)
- Change:
```lua
-- OLD:
state.target_w = result.target_w
state.target_h = result.target_h
state.vsr_path_active = result.vsr_path

-- NEW:
local success, err = state_manager:set_pipeline_targets(
    result.target_w,
    result.target_h,
    result.vsr_path
)
if not success then
    mp.msg.error("[rife_adaptive][VPY] " .. err)
    return
end
```

**Step 5: Verify (Green)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua`
- Expect: PASS

**Step 6: Manual Test**
- Command: Open mpv with any video
- Action: Press Shift+6 to toggle RIFE on
- Expect: RIFE activates successfully, no errors in log

**Step 7: Git Commit**
- Command: `git add rife_state_manager.lua rife_main.lua tests/test_rife_state_manager.lua && git commit -m "feat: add validation to set_pipeline_targets()"`

---

### Task 2.4: Add Debug Snapshot Method

**Goal:** Implement get_debug_snapshot() for logging state

**Step 1: Write the Failing Test**
- File: `tests/test_rife_state_manager.lua`
- Code:
```lua
TestStateManagerDebug = {}

function TestStateManagerDebug:test_debug_snapshot_contains_all_fields()
  local sm = StateManager:new("3001")
  sm:activate_rife("normal")
  sm:set_fullscreen(true)

  local snapshot = sm:get_debug_snapshot()

  lu.assertStrContains(snapshot, "rife_active=true")
  lu.assertStrContains(snapshot, "vsr_only_mode=false")
  lu.assertStrContains(snapshot, "is_fullscreen=true")
  lu.assertStrContains(snapshot, "pid=3001")
end

function TestStateManagerDebug:test_debug_snapshot_with_crop()
  local sm = StateManager:new("3002")
  sm:activate_rife("normal")
  sm:complete_crop_detection({w = 1920, h = 800, x = 0, y = 140})

  local snapshot = sm:get_debug_snapshot()

  lu.assertStrContains(snapshot, "1920x800")
end
```

**Step 2: Run Test (Red)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua`
- Expect: "attempt to call method 'get_debug_snapshot'"

**Step 3: Implementation (Green)**
- File: `rife_state_manager.lua`
- Action: Add get_debug_snapshot() method
- Code:
```lua
-- Query: debug snapshot for logging
-- Returns: formatted string of all state fields
function StateManager:get_debug_snapshot()
  local parts = {
    "rife_active=" .. tostring(self._rife_active),
    "vsr_only_mode=" .. tostring(self._vsr_only_mode),
    "is_fullscreen=" .. tostring(self._is_fullscreen),
    "vsr_path_active=" .. tostring(self._vsr_path_active),
  }

  if self._current_crop then
    table.insert(parts, string.format("crop=%dx%d at (%d,%d)",
      self._current_crop.w,
      self._current_crop.h,
      self._current_crop.x,
      self._current_crop.y))
  else
    table.insert(parts, "crop=nil")
  end

  if self._target_w and self._target_h then
    table.insert(parts, string.format("target=%dx%d", self._target_w, self._target_h))
  else
    table.insert(parts, "target=nil")
  end

  table.insert(parts, "timer=" .. (self._cropdetect_timer and "active" or "nil"))
  table.insert(parts, "pid=" .. tostring(self._pid))

  return "{ " .. table.concat(parts, ", ") .. " }"
end
```

**Step 4: Verify (Green)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua`
- Expect: PASS

**Step 5: Git Commit**
- Command: `git add rife_state_manager.lua tests/test_rife_state_manager.lua && git commit -m "feat: add get_debug_snapshot() method"`

---

### Task 2.5: Add export_for_template() Method

**Goal:** Export state variables for template rendering

**Step 1: Write the Failing Test**
- File: `tests/test_rife_state_manager.lua`
- Code:
```lua
TestStateManagerExport = {}

function TestStateManagerExport:test_export_for_template_includes_pid()
  local sm = StateManager:new("4001")

  local vars = sm:export_for_template({extra_var = "test"})

  lu.assertEquals(vars.pid, "4001")
  lu.assertEquals(vars.extra_var, "test")
end

function TestStateManagerExport:test_export_with_crop()
  local sm = StateManager:new("4002")
  sm:activate_rife("normal")
  sm:complete_crop_detection({w = 1920, h = 1080, x = 0, y = 0})

  local vars = sm:export_for_template()

  lu.assertEquals(vars.crop_l, 0)
  lu.assertEquals(vars.crop_t, 0)
  lu.assertEquals(vars.crop_w, 1920)
  lu.assertEquals(vars.crop_h, 1080)
end

function TestStateManagerExport:test_export_with_no_crop_defaults_to_source()
  local sm = StateManager:new("4003")

  local vars = sm:export_for_template({
    source_w = 1920,
    source_h = 1080
  })

  -- When no crop, crop params should match source
  lu.assertEquals(vars.crop_l, 0)
  lu.assertEquals(vars.crop_t, 0)
  lu.assertEquals(vars.crop_w, 1920)
  lu.assertEquals(vars.crop_h, 1080)
end
```

**Step 2: Run Test (Red)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua`
- Expect: "attempt to call method 'export_for_template'"

**Step 3: Implementation (Green)**
- File: `rife_state_manager.lua`
- Action: Add export_for_template() method
- Code:
```lua
-- Export state for template rendering
-- additional_vars: table with extra template variables (multiplier, padding, etc.)
-- Returns: table with all template variables
function StateManager:export_for_template(additional_vars)
  additional_vars = additional_vars or {}

  local crop = self._current_crop

  -- If no crop detected, use source dimensions (passed in additional_vars)
  local crop_l = crop and crop.x or 0
  local crop_t = crop and crop.y or 0
  local crop_w = crop and crop.w or (additional_vars.source_w or 0)
  local crop_h = crop and crop.h or (additional_vars.source_h or 0)

  return {
    -- Process ID
    pid = self._pid,

    -- Crop parameters
    crop_l = crop_l,
    crop_t = crop_t,
    crop_w = crop_w,
    crop_h = crop_h,

    -- Target resolution
    target_w = self._target_w or 0,
    target_h = self._target_h or 0,

    -- Merge additional vars (multiplier, padding, model, gpu, etc.)
    unpack(additional_vars)
  }
end
```

**Note:** Lua's `unpack()` doesn't work on tables directly. Need to merge tables properly:

```lua
-- Alternative implementation:
function StateManager:export_for_template(additional_vars)
  additional_vars = additional_vars or {}

  local crop = self._current_crop
  local crop_l = crop and crop.x or 0
  local crop_t = crop and crop.y or 0
  local crop_w = crop and crop.w or (additional_vars.source_w or 0)
  local crop_h = crop and crop.h or (additional_vars.source_h or 0)

  -- Create base export
  local export = {
    pid = self._pid,
    crop_l = crop_l,
    crop_t = crop_t,
    crop_w = crop_w,
    crop_h = crop_h,
    target_w = self._target_w or 0,
    target_h = self._target_h or 0,
  }

  -- Merge additional vars
  for k, v in pairs(additional_vars) do
    export[k] = v
  end

  return export
end
```

**Step 4: Verify (Green)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua`
- Expect: PASS

**Step 5: Git Commit**
- Command: `git add rife_state_manager.lua tests/test_rife_state_manager.lua && git commit -m "feat: add export_for_template() method"`

---

## Phase 3: Template Extraction

### Task 3.1: Create Template File

**Goal:** Extract VPY template from rife_main.lua to external file

**Step 1: Create Template Directory**
- Command: `mkdir -p templates`
- Action: Create `templates` subdirectory

**Step 2: Extract Template Content**
- File: `templates/rife.vpy.template`
- Action: Create template file with mustache-style placeholders
- Code:
```python
# templates/rife.vpy.template
import sys
import os
sys.path.insert(0, r"{{script_dir}}")

import vapoursynth as vs
from vapoursynth import core
from rife_processor import process

clip = video_in

# Process with RIFE
clip = process(
    clip=clip,
    crop_l={{crop_l}},
    crop_t={{crop_t}},
    crop_w={{crop_w}},
    crop_h={{crop_h}},
    target_w={{target_w}},
    target_h={{target_h}},
    model={{model}},
    gpu_id={{gpu_id}},
    gpu_t={{gpu_t}},
    padding_enabled={{padding_enabled}},
    padding_orig_w={{padding_orig_w}},
    padding_orig_h={{padding_orig_h}},
    multiplier={{multiplier}}
)

clip.set_output()
```

**Step 3: Manual Verification**
- Action: Compare with existing inline template in rife_main.lua (lines 268-303)
- Expect: Identical Python code structure, only placeholders changed

**Step 4: Git Commit**
- Command: `git add templates/rife.vpy.template && git commit -m "feat: extract VPY template to external file"`

---

### Task 3.2: Create TemplateLoader Module

**Goal:** Implement template loading and rendering

**Step 1: Write the Failing Test**
- File: `tests/test_rife_template_loader.lua`
- Code:
```lua
local lu = require('luaunit')
local TemplateLoader = require('rife_template_loader')

TestTemplateLoaderLoad = {}

function TestTemplateLoaderLoad:test_load_existing_template()
  local template = TemplateLoader:load("fixtures/test_template.vpy.template")

  lu.assertNotNil(template)
  lu.assertEquals(type(template.render), "function")
end

function TestTemplateLoaderLoad:test_load_missing_file_errors()
  local success, err = pcall(function()
    TemplateLoader:load("nonexistent.vpy.template")
  end)

  lu.assertFalse(success)
  lu.assertStrContains(err, "Template file not found")
end
```

**Step 2: Create Test Fixture**
- File: `tests/fixtures/test_template.vpy.template`
- Code:
```python
import sys
sys.path.insert(0, r"{{script_dir}}")

clip = video_in
```

**Step 3: Run Test (Red)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua`
- Expect: "module 'rife_template_loader' not found"

**Step 4: Implementation (Green)**
- File: `rife_template_loader.lua`
- Action: Create TemplateLoader module
- Code:
```lua
-- rife_template_loader.lua - Template loading and rendering

local TemplateLoader = {}
TemplateLoader.__index = TemplateLoader

-- Template object (returned by load)
local Template = {}
Template.__index = Template

-- Load and parse template file
-- Returns: Template object with render() method
function TemplateLoader:load(template_path)
  -- Check file exists
  local f = io.open(template_path, "r")
  if not f then
    error("Template file not found: " .. template_path)
  end

  local content = f:read("*all")
  f:close()

  -- Create template object
  local template = {
    _content = content,
    _path = template_path
  }

  return setmetatable(template, Template)
end

-- Render template with variables
-- vars: table with template variable values
-- Returns: rendered string (valid Python code)
function Template:render(vars)
  vars = vars or {}

  local result = self._content

  -- Replace {{variable}} placeholders
  for key, value in pairs(vars) do
    local placeholder = "{{" .. key .. "}}"
    local replacement = tostring(value)
    result = result:gsub(placeholder, replacement)
  end

  -- Check for unreplaced placeholders
  local unreplaced = result:match("{{(%w+)}}")
  if unreplaced then
    error("Missing template variable: " .. unreplaced)
  end

  return result
end

-- Validate template syntax (basic check)
function TemplateLoader:validate(template_content)
  -- Check for balanced braces
  local open_count = 0
  for i = 1, #template_content do
    local char = template_content:sub(i, i)
    if char == "{" then
      open_count = open_count + 1
    elseif char == "}" then
      open_count = open_count - 1
    end
  end

  if open_count ~= 0 then
    return false, "Unbalanced braces in template"
  end

  return true, nil
end

return TemplateLoader
```

**Step 5: Verify (Green)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua`
- Expect: PASS

**Step 6: Git Commit**
- Command: `git add rife_template_loader.lua tests/test_rife_template_loader.lua tests/fixtures/test_template.vpy.template && git commit -m "feat: add TemplateLoader module with load/render"`

---

### Task 3.3: Add Template Rendering Tests

**Goal:** Test variable substitution and validation

**Step 1: Write the Failing Test**
- File: `tests/test_rife_template_loader.lua`
- Code:
```lua
TestTemplateLoaderRender = {}

function TestTemplateLoaderRender:test_render_simple_variables()
  local template = TemplateLoader:load("fixtures/test_template.vpy.template")
  local vars = {
    script_dir = "C:/test/path"
  }

  local result = template:render(vars)

  lu.assertStrContains(result, 'sys.path.insert(0, r"C:/test/path")')
  lu.assertNotStrContains(result, "{{")  -- No unreplaced placeholders
end

function TestTemplateLoaderRender:test_render_missing_variable_errors()
  local template = TemplateLoader:load("fixtures/test_template.vpy.template")
  local vars = {}  -- Missing script_dir

  local success, err = pcall(function()
    template:render(vars)
  end)

  lu.assertFalse(success)
  lu.assertStrContains(err, "Missing template variable")
end

function TestTemplateLoaderRender:test_render_boolean_values()
  local template = TemplateLoader:load("fixtures/bool_template.vpy.template")

  local result = template:render({enabled = true})

  lu.assertStrContains(result, "enabled=true")
end
```

**Step 2: Create Test Fixture**
- File: `tests/fixtures/bool_template.vpy.template`
- Code:
```python
enabled={{enabled}}
```

**Step 3: Run Test (Red)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua`
- Expect: "Missing template variable" (test should pass but we need to verify)

**Step 4: Verify (Green)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua`
- Expect: PASS

**Step 5: Git Commit**
- Command: `git add tests/test_rife_template_loader.lua tests/fixtures/bool_template.vpy.template && git commit -m "test: add template rendering tests"`

---

### Task 3.4: Integrate TemplateLoader into rife_main.lua

**Goal:** Replace inline string.format with template rendering

**Step 1: Add TemplateLoader Import**
- File: `rife_main.lua`
- Action: Add after core import (line 20)
- Change:
```lua
local core = require('rife_core')
local TemplateLoader = require('rife_template_loader')
```

**Step 2: Load Template on Script Init**
- File: `rife_main.lua`
- Action: Add after state_manager initialization (after line 61)
- Change:
```lua
local StateManager = require('rife_state_manager')
local state_manager = StateManager:new(mp.get_property_native("pid") or "0")

-- Load VPY template
local script_dir = mp.command_native({"expand-path", "~~/vs/rife_adapting_2"})
local template = TemplateLoader:load(script_dir .. "/templates/rife.vpy.template")
```

**Step 3: Replace Inline Template Generation**
- File: `rife_main.lua`
- Action: Update generate_and_apply_vpy() function (lines 268-303)
- Change:
```lua
-- OLD: Inline string.format with 36 lines of Python
local vpy_content = string.format([[
import sys
...
]], script_dir, crop_x, crop_y, ...)

-- NEW: Template rendering
local template_vars = state_manager:export_for_template({
    script_dir = script_dir,
    model = opts.model,
    gpu_id = opts.gpu_id,
    gpu_t = opts.gpu_threads,
    multiplier = multiplier,
    padding_enabled = result.padding.enabled,
    padding_orig_w = result.padding.orig_w,
    padding_orig_h = result.padding.orig_h,
})

local vpy_content = template:render(template_vars)
```

**Step 4: Manual Verification**
- Command: Open mpv with any video
- Action: Press Shift+6 to toggle RIFE on
- Expect: RIFE activates successfully
- Command: Check temp directory for VPY file
- Action: Read generated VPY file
- Expect: Valid Python code with all placeholders replaced

**Step 5: Git Commit**
- Command: `git add rife_main.lua && git commit -m "refactor: integrate TemplateLoader into rife_main.lua"`

---

## Phase 4: Integration & Testing

### Task 4.1: Run Full Test Suite

**Goal:** Verify all unit tests pass

**Step 1: Run All Tests**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua`
- Expect: PASS (all tests)

**Step 2: Check Test Coverage**
- File: Review test files
- Action: Ensure all StateManager public methods have tests
- Expect:
  - test_rife_state_manager.lua: 100% API coverage
  - test_rife_template_loader.lua: load/render/validate covered
  - test_rife_core.lua: Still passing (no regressions)

**Step 3: Git Commit**
- Command: `git add tests && git commit -m "test: ensure full test suite passes after refactor"`

---

### Task 4.2: Manual Integration Testing

**Goal:** Test RIFE functionality with real mpv

**Step 1: Test Normal RIFE Activation**
- Command: Open mpv with 24fps video (e.g., movie file)
- Action: Press Shift+6
- Expect: OSD shows crop detection → RIFE activation → resolution chain
- Command: Press Shift+6 again to toggle off
- Expect: OSD shows "OFF"

**Step 2: Test VSR-Only Mode**
- Command: Open mpv with 60fps video
- Action: Press Shift+6
- Expect: OSD shows "VSR-only (60.00 fps)"
- Action: Enter fullscreen
- Expect: VSR activates

**Step 3: Test Fullscreen Toggle**
- Command: Open mpv with 24fps video, activate RIFE
- Action: Toggle fullscreen (press `f` key)
- Expect: VSR activates/deactivates based on fullscreen state

**Step 4: Test Crop Detection**
- Command: Open mpv with letterboxed video
- Action: Activate RIFE
- Expect: Crop detection runs, black bars removed
- Command: Check mpv log
- Expect: `[rife_adaptive][CROP] Result: 1920x800` (example)

**Step 5: Test Rapid Toggle Spamming**
- Command: Open mpv
- Action: Press Shift+6 rapidly 5 times
- Expect: No crashes, state remains consistent
- Command: Check mpv log
- Expect: Validation errors logged (if any), no silent failures

**Step 6: Test Multiple mpv Instances**
- Command: Open 2 mpv windows with different videos
- Action: Activate RIFE in both
- Expect: Both work independently (different PIDs)
- Command: Check temp directory
- Expect: 2 VPY files with different PIDs

**Step 7: Document Test Results**
- File: Create `docs/integration-test-results.md`
- Action: Document pass/fail for each test scenario
- Commit if all tests pass

---

### Task 4.3: Performance Profiling

**Goal:** Ensure <1% performance overhead from refactoring

**Step 1: Profile Template Rendering**
- File: `tests/benchmark_template.lua`
- Code:
```lua
local TemplateLoader = require('rife_template_loader')
local script_dir = "C:/portable/mpv-lazy-new/mpv-lazy/portable_config/vs/rife_adapting_2"
local template = TemplateLoader:load(script_dir .. "/templates/rife.vpy.template")

local vars = {
  script_dir = script_dir,
  crop_l = 0, crop_t = 80, crop_w = 1920, crop_h = 1080,
  target_w = 1920, target_h = 1080,
  model = 4221, gpu_id = 0, gpu_t = 2,
  padding_enabled = true,
  padding_orig_w = 1920, padding_orig_h = 1080,
  multiplier = 2
}

local start = os.clock()
for i = 1, 1000 do
  template:render(vars)
end
local elapsed = os.clock() - start

print(string.format("1000 renders: %.3fs (%.3fms per render)",
  elapsed, (elapsed / 1000) * 1000))
```

- Command: `C:/portable/mpv-lazy-new/lua54.exe tests/benchmark_template.lua`
- Expect: "<1ms per render"

**Step 2: Profile StateManager Access**
- File: `tests/benchmark_state.lua`
- Code:
```lua
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

print(string.format("100000 * 4 calls: %.3fs (%.3fμs per call)",
  elapsed, (elapsed / 400000) * 1000000))
```

- Command: `C:/portable/mpv-lazy-new/lua54.exe tests/benchmark_state.lua`
- Expect: "<0.1ms per call"

**Step 3: Compare with Original Code (Optional)**
- Action: If you have a backup of original rife_main.lua, run same benchmarks
- Expect: "Overhead <1%"

**Step 4: Document Performance Results**
- File: Add to `docs/integration-test-results.md`
- Action: Document benchmark results

**Step 5: Git Commit**
- Command: `git add docs/integration-test-results.md tests/benchmark_*.lua && git commit -m "test: add performance profiling and results"`

---

### Task 4.4: Update Documentation

**Goal:** Update CLAUDE.md with new architecture

**Step 1: Update CLAUDE.md**
- File: `CLAUDE.md`
- Action: Update "Key Files" section
- Change:
```markdown
| File | Purpose |
|------|---------|
| `rife_main.lua` | mpv controller, VPY generation |
| `rife_processor.py` | VapourSynth RIFE pipeline |
| `rife_core.lua` | Pure testable functions (resolution logic) |
| `rife_state_manager.lua` | State encapsulation with validation |
| `rife_template_loader.lua` | VPY template loading and rendering |
| `templates/rife.vpy.template` | External VPY template |
| `tests/test_rife_state_manager.lua` | StateManager unit tests |
| `tests/test_rife_template_loader.lua` | TemplateLoader unit tests |
| `tests/test_rife_core.lua` | Core logic unit tests |
```

**Step 2: Update Architecture Diagram**
- File: `CLAUDE.md`
- Action: Update "Architecture" section
- Change:
```markdown
## Architecture

```
mpv (Lua) → StateManager → TemplateLoader → VPY generation
                ↓                    ↓
         validation logic    template rendering
                ↓
         rife_core.lua (resolution math)
                ↓
VapourSynth (Python) → RIFE → back to mpv
```
```

**Step 3: Add Refactoring Notes**
- File: `CLAUDE.md`
- Action: Add section after "Gotchas"
- Change:
```markdown
## Refactoring Notes (2026-01-19)

**StateManager Pattern:**
- All state encapsulated in `rife_state_manager.lua`
- State transitions validated (invariant checking)
- Use `state_manager:get_debug_snapshot()` for debugging

**Template System:**
- VPY template extracted to `templates/rife.vpy.template`
- Edit template without touching Lua code
- Use `{{variable}}` placeholders (mustache-style)

**Testing:**
- Unit tests: `cd tests && lua54.exe run_tests.lua`
- StateManager: 100% API coverage
- TemplateLoader: load/render/validate covered
```

**Step 4: Git Commit**
- Command: `git add CLAUDE.md && git commit -m "docs: update CLAUDE.md for StateManager/Template refactor"`

---

### Task 4.5: Final Verification and Tag

**Goal:** Final checks and version tagging

**Step 1: Check Git Status**
- Command: `git status`
- Expect: "nothing to commit, working tree clean"

**Step 2: Run Full Test Suite One More Time**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua`
- Expect: All tests pass

**Step 3: Review All Commits**
- Command: `git log --oneline --graph -20`
- Expect: Clean commit history with descriptive messages

**Step 4: Create Git Tag**
- Command: `git tag -a v2.0.0-refactor -m "StateManager & Template Refactor - Phase 1-4 complete"`
- Action: Tag the refactor milestone

**Step 5: Push to Remote (Optional)**
- Command: `git push origin master --tags`
- Action: Push if using remote repository

**Step 6: Final Git Commit**
- Command: `git add . && git commit --allow-empty -m "chore: complete StateManager & Template refactor (all 4 phases)"`

---

## Summary

**Total Tasks:** 26 tasks across 4 phases
**Estimated Time:** 6-10 hours
**Files Modified:**
- `rife_main.lua` (StateManager integration)
- `rife_state_manager.lua` (NEW)
- `rife_template_loader.lua` (NEW)
- `templates/rife.vpy.template` (NEW)
- `tests/test_rife_state_manager.lua` (NEW)
- `tests/test_rife_template_loader.lua` (NEW)
- `CLAUDE.md` (documentation)

**Success Criteria:**
- ✅ All unit tests pass
- ✅ Manual mpv testing successful
- ✅ Performance overhead <1%
- ✅ No regressions in existing functionality
