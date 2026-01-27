-- rife_state_manager.lua - State encapsulation with validation

local StateManager = {}
StateManager.__index = StateManager

-- Persistent storage file for skip_crop flag
local function get_persistent_file(pid)
  local temp_dir = os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
  return temp_dir .. "/rife_adapting_2_" .. (pid or "0") .. "_state.txt"
end

-- Load persistent state from file
local function load_persistent_state(pid)
  local filepath = get_persistent_file(pid)
  local f = io.open(filepath, "r")
  if not f then return { skip_crop = false } end

  local content = f:read("*a")
  f:close()

  -- Parse simple key=value format
  local state = { skip_crop = false }
  for key, value in content:gmatch("([%w_]+)=([%w_]+)") do
    state[key] = (value == "true")
  end
  return state
end

-- Save persistent state to file
local function save_persistent_state(pid, skip_crop)
  local filepath = get_persistent_file(pid)
  local f = io.open(filepath, "w")
  if not f then return end

  f:write("skip_crop=" .. tostring(skip_crop))
  f:close()
end

-- Create new state instance
function StateManager:new(pid)
  -- Load persistent state
  local persistent = load_persistent_state(pid)

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
    _pid = pid,
    _skip_crop = persistent.skip_crop,  -- Load from persistent storage
  }

  return setmetatable(state, self)
end

-- Getters
function StateManager:get_pid()
  return self._pid
end

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

function StateManager:get_skip_crop()
  return self._skip_crop
end

-- Request skipping crop detection (called when user aborts during engine build)
-- Persists to disk so next run will skip crop
function StateManager:request_skip_crop()
  self._skip_crop = true
  save_persistent_state(self._pid, true)
end

-- Clear skip crop flag (called after successful activation)
function StateManager:clear_skip_crop()
  self._skip_crop = false
  save_persistent_state(self._pid, false)
end

-- Initializing flag (true when crop detection is in progress, false after successful VPY)
function StateManager:get_initializing()
  return self._initializing or false
end

function StateManager:set_initializing(value)
  self._initializing = value
end

-- Check if we should set skip_crop on shutdown (still initializing when closing)
function StateManager:should_skip_on_shutdown()
  return self._initializing or false
end

-- Deactivate RIFE (reset all state)
function StateManager:deactivate_rife()
  self._rife_active = false
  self._vsr_only_mode = false
  self._current_crop = nil
  self._cropdetect_timer = nil
  self._target_w = nil
  self._target_h = nil
  self._vsr_path_active = false
  self._initializing = false
  -- Note: is_fullscreen and pid are preserved
end

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

-- Complete crop detection (store result, clear timer)
-- crop_result: {w, h, x, y} or nil (no black bars)
function StateManager:complete_crop_detection(crop_result)
  self._current_crop = crop_result
  self._cropdetect_timer = nil  -- Clear timer
end

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

return StateManager
