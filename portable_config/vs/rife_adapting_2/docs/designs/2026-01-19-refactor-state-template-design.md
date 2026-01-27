# Design: State Management & Template Refactor

## 1. Problem Statement

### Current Issues
**State Management Complexity:**
- 9 scattered state variables in `rife_main.lua` with no encapsulation
- No validation of state transitions (e.g., VSR can theoretically activate without RIFE)
- Difficult to test state logic in isolation
- State mutations happen throughout the file, making bugs hard to track

**VPY Template Fragility:**
- 36 lines of inline Python code (lines 268-303) mixed with Lua string formatting
- Easy to break Python syntax when editing Lua code
- No separation of concerns (presentation logic embedded in controller)
- Template changes require modifying Lua source

### Goals
- Encapsulate state with validation and invariants checking
- Extract VPY template to external file for maintainability
- Enable unit testing of state transitions
- Prepare foundation for future config persistence

## 2. Goals & Non-Goals

### Must Do
- ✅ Create `StateManager` class with strict transition validation
- ✅ Extract VPY template to external `.vpy.template` file
- ✅ Add unit tests for StateManager state transitions
- ✅ Maintain backward compatibility (no behavior changes)
- ✅ Preserve all existing debug logging

### Won't Do
- ❌ Config file persistence (deferred to future work)
- ❌ Performance optimizations (current code is fast enough)
- ❌ Breaking changes to public API (script messages, keybindings)
- ❌ Integration tests for VPY execution (unit tests only)

## 3. Proposed Architecture

### High-Level Approach

```
┌─────────────────────────────────────────────────────┐
│                   rife_main.lua                     │
│  (Controller: orchestrates events, calls StateManager)│
└────────────────┬────────────────────────────────────┘
                 │
        ┌────────┴────────┐
        ▼                 ▼
┌──────────────┐  ┌────────────────┐
│ StateManager │  │ TemplateLoader │
│              │  │                │
│ - state      │  │ - load()       │
│ - validate() │  │ - render()     │
│ - transition│  │ - validate()   │
└──────────────┘  └────────────────┘
        │
        ▼
┌──────────────────┐
│  Unit Tests      │
│  (test_state_    │
│   manager.lua)   │
└──────────────────┘
```

### Key Components

#### Component 1: StateManager (`rife_state_manager.lua`)
**Responsibilities:**
- Encapsulate all 9 state variables
- Validate state transitions (invariant checking)
- Provide getter/setter methods with type safety
- Export state snapshots for debugging

**State Invariants:**
```lua
-- VSR can only be active when RIFE is active
-- VSR can only activate when in fullscreen (checked separately)
-- cropdetect_timer can only exist when rife_active=true
-- target_w/target_h must be set together (both nil or both numbers)
```

#### Component 2: TemplateLoader (`rife_template_loader.lua`)
**Responsibilities:**
- Load `.vpy.template` file from disk
- Validate template syntax (Python code integrity)
- Render template with variable substitution (JSON-driven)
- Cache compiled template for performance

#### Component 3: Unit Tests (`tests/test_rife_state_manager.lua`)
**Coverage:**
- All state transitions (activate, deactivate, VSR toggle, fullscreen change)
- Invariant violation detection
- Edge cases (nil values, type mismatches)
- State serialization/export

### File Structure
```
rife_adapting_2/
├── rife_main.lua                 (Modified: uses StateManager)
├── rife_state_manager.lua        (NEW: state encapsulation)
├── rife_template_loader.lua      (NEW: template rendering)
├── templates/
│   └── rife.vpy.template         (NEW: extracted VPY template)
├── tests/
│   ├── test_rife_state_manager.lua  (NEW: state unit tests)
│   └── test_rife_core.lua        (EXISTING: no changes)
└── docs/
    └── designs/
        └── 2026-01-19-refactor-state-template-design.md
```

## 4. Data Models / Schema

### StateManager Internal State
```lua
{
  -- Core mode
  rife_active = boolean,          -- Master switch
  vsr_only_mode = boolean,        -- High-fps bypass mode

  -- Crop detection
  current_crop = {
    w = number,
    h = number,
    x = number,
    y = number
  } | nil,
  cropdetect_timer = mpv_timer | nil,

  -- Display state
  is_fullscreen = boolean,

  -- RIFE pipeline targets
  target_w = number | nil,
  target_h = number | nil,
  vsr_path_active = boolean,

  -- Metadata
  pid = string                   -- Process ID (immutable after init)
}
```

### State Transition API
```lua
-- Constructor
state = StateManager:new(pid)

-- Getters (read-only access)
state:get_rife_active() -> boolean
state:get_target_resolution() -> (w, h) | (nil, nil)
state:is_vsr_eligible() -> boolean

-- Setters (with validation)
state:activate_rife() -> success, error
state:deactivate_rife()
state:set_fullscreen(is_fullscreen)
state:set_crop_detection_timer(timer)
state:complete_crop_detection(crop_result)
state:set_pipeline_targets(w, h, vsr_path)

-- State queries
state:should_activate_vsr() -> boolean
state:needs_vpy_generation() -> boolean
state:get_debug_snapshot() -> string
```

### Template Variable Schema (JSON)
```json
{
  "script_dir": "string (path to rife_adapting_2)",
  "crop_l": "number",
  "crop_t": "number",
  "crop_w": "number",
  "crop_h": "number",
  "target_w": "number",
  "target_h": "number",
  "model": "number",
  "gpu_id": "number",
  "gpu_threads": "number",
  "padding_enabled": "boolean",
  "padding_orig_w": "number",
  "padding_orig_h": "number",
  "multiplier": "number (2 or 3)"
}
```

### VPY Template Format
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
    gpu_t={{gpu_threads}},
    padding_enabled={{padding_enabled}},
    padding_orig_w={{padding_orig_w}},
    padding_orig_h={{padding_orig_h}},
    multiplier={{multiplier}}
)

clip.set_output()
```

**Note:** Using `{{variable}}` syntax (mustache-style) for template substitution, avoiding Lua's `%` conflicts with Python formatting.

## 5. Interface / API Design

### StateManager Public Interface

```lua
-- rife_state_manager.lua
local StateManager = {}
StateManager.__index = StateManager

-- Create new state instance
function StateManager:new(pid)
  local state = {
    -- Private state (using closure encapsulation)
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

-- Activate RIFE (normal or vsr-only mode)
function StateManager:activate_rife(mode)
  -- mode: "normal" or "vsr_only"
  -- Returns: (success, error_message)
end

-- Deactivate RIFE (reset all state)
function StateManager:deactivate_rife()
  -- Clears: rife_active, crop, timer, targets
end

-- Update fullscreen state
function StateManager:set_fullscreen(is_fullscreen)
  -- Validates: fullscreen only relevant when rife_active
end

-- Set crop detection timer (pending detection)
function StateManager:set_crop_detection_timer(timer)
  -- Validates: timer only when rife_active and not vsr_only
end

-- Complete crop detection (store result, clear timer)
function StateManager:complete_crop_detection(crop_result)
  -- crop_result: {w, h, x, y} or nil (no black bars)
end

-- Set pipeline targets after resolution calculation
function StateManager:set_pipeline_targets(w, h, vsr_path)
  -- Validates: w, h set together; vsr_path requires rife_active
end

-- Query: should VSR activate now?
function StateManager:should_activate_vsr()
  -- Returns true if: rife_active AND vsr_path_active AND is_fullscreen
end

-- Query: debug snapshot for logging
function StateManager:get_debug_snapshot()
  -- Returns formatted string of all state fields
end

-- Export state for template rendering
function StateManager:export_for_template(additional_vars)
  -- Returns table with all template variables + metadata
end
```

### TemplateLoader Public Interface

```lua
-- rife_template_loader.lua
local TemplateLoader = {}
TemplateLoader.__index = TemplateLoader

-- Load and parse template file
function TemplateLoader:load(template_path)
  -- Returns: Template object with render() method
end

-- Render template with variables
function Template:render(vars)
  -- vars: table with template variable values
  -- Returns: rendered string (valid Python code)
  -- Raises: error if required variable missing
end

-- Validate template syntax (basic check)
function TemplateLoader:validate(template_content)
  -- Checks: balanced braces, valid placeholder names
end
```

### Integration Example (rife_main.lua)

```lua
-- Before refactoring (current code)
local state = {
    rife_active = false,
    current_crop = nil,
    -- ... 7 more fields
}

local function toggle_rife()
    if state.rife_active then
        state.rife_active = false
        state.current_crop = nil
        -- ... manual state reset
    else
        state.rife_active = true
        -- ... manual state updates
    end
end

-- After refactoring
local state_manager = StateManager:new(mp.get_property_native("pid") or "0")
local template = TemplateLoader:load(script_dir .. "/templates/rife.vpy.template")

local function toggle_rife()
    if state_manager:get_rife_active() then
        state_manager:deactivate_rife()
        osd_message("OFF")
    else
        local fps = get_container_fps()
        local mode = (fps >= 50) and "vsr_only" or "normal"
        local success, err = state_manager:activate_rife(mode)
        if not success then
            mp.msg.error("[STATE] " .. err)
            return
        end
        -- ... continue with crop detection
    end
end

local function generate_and_apply_vpy()
    -- Calculate targets
    local result = core.calculate_targets(...)

    -- Update state
    state_manager:set_pipeline_targets(
        result.target_w,
        result.target_h,
        result.vsr_path
    )

    -- Render template
    local template_vars = state_manager:export_for_template({
        multiplier = multiplier,
        padding_enabled = result.padding.enabled,
        -- ... other vars
    })

    local vpy_content = template:render(template_vars)

    -- Write VPY file...
end
```

## 6. Risks & Edge Cases

### Risk 1: Performance Regression
**Concern:** Additional function call overhead in hot path
**Mitigation:**
- Template compilation cached after first load
- StateManager methods are simple table access (no complex computations)
- Profile before/after to confirm <1% overhead

### Risk 2: State Invariant False Positives
**Concern:** Strict validation rejects valid edge cases
**Mitigation:**
- Add `debug_mode` flag to disable validation in production
- Log violations with context (expected vs actual)
- Make validation rules configurable

### Risk 3: Template File Missing/Corrupted
**Concern:** External template file dependency
**Mitigation:**
- Check template existence on script load, abort with clear error
- Include template checksum for integrity validation
- Fall back to embedded template if file missing (future enhancement)

### Edge Case: Multiple mpv Instances
**Scenario:** User runs multiple mpv windows simultaneously
**Current:** Handled via PID in temp file names
**After Refactor:** No change (PID stored in StateManager, template rendering per-instance)

### Edge Case: Rapid Toggle Spamming
**Scenario:** User presses Shift+6 rapidly during crop detection
**Current:** Timer killed, but state inconsistent
**After Refactor:** StateManager validates transitions, rejects invalid state changes

### Edge Case: VSR Activation Race Condition
**Scenario:** Fullscreen toggle during RIFE activation
**Current:** Separate observe_property handler
**After Refactor:** StateManager ensures consistent state via transition validation

## 7. Implementation Plan

### Phase 1: StateManager Foundation (Low Risk)
1. Create `rife_state_manager.lua` with basic getters/setters
2. Add unit tests for initialization and simple transitions
3. Integrate into `rife_main.lua` (replace direct state table access)

### Phase 2: Validation & Invariants (Medium Risk)
1. Add state transition validation logic
2. Add unit tests for invariant violations
3. Update existing code to handle validation errors

### Phase 3: Template Extraction (Low Risk)
1. Extract VPY template to `templates/rife.vpy.template`
2. Create `rife_template_loader.lua` with placeholder substitution
3. Add unit tests for template rendering
4. Replace inline `string.format` in `rife_main.lua`

### Phase 4: Integration & Testing (Low Risk)
1. Run existing integration tests (mpv manual testing)
2. Add regression tests for state machine edge cases
3. Performance profiling (ensure <1% overhead)

### Estimated Effort
- Phase 1: 2-3 hours
- Phase 2: 2-3 hours
- Phase 3: 1-2 hours
- Phase 4: 1-2 hours
- **Total: 6-10 hours**

### Rollback Strategy
- Keep old state table code commented out for one release
- Feature flag: `USE_STATE_MANAGER = true` (disable if issues found)
- Git revert available if all else fails

## 8. Testing Strategy

### Unit Tests for StateManager

**Test Categories:**
1. **Initialization Tests**
   - Valid PID creation
   - Default state values (all false/nil)

2. **Activation Tests**
   - Normal mode activation success
   - VSR-only mode activation success
   - Double-activation rejection

3. **Deactivation Tests**
   - Clean reset of all state
   - Deactivation when inactive (no-op)

4. **Crop Detection Tests**
   - Timer set only when active
   - Crop result storage
   - Crop cleared on deactivation

5. **Target Resolution Tests**
   - Valid w/h set together
   - Rejection of partial set (w nil, h number)
   - Target cleared on deactivation

6. **VSR Eligibility Tests**
   - VSR requires: active + vsr_path + fullscreen
   - All combinations of false positives

7. **Invariant Violation Tests**
   - Set timer without RIFE active → reject
   - Set targets without RIFE active → reject
   - Activate VSR-only with crop → reject

8. **Edge Cases**
   - Rapid toggle sequences
   - Missing nil values
   - Type mismatches (string instead of number)

**Example Test:**
```lua
function TestStateManager:test_vsr_eligibility_all_true()
  local sm = StateManager:new("123")
  sm:activate_rife("normal")
  sm:set_fullscreen(true)
  sm:set_pipeline_targets(1920, 1080, true)

  lu.assertTrue(sm:should_activate_vsr())
end

function TestStateManager:test_vsr_eligibility_not_fullscreen()
  local sm = StateManager:new("123")
  sm:activate_rife("normal")
  sm:set_fullscreen(false)  -- Not fullscreen
  sm:set_pipeline_targets(1920, 1080, true)

  lu.assertFalse(sm:should_activate_vsr())
end
```

### Unit Tests for TemplateLoader

**Test Categories:**
1. **Load Tests**
   - Valid template file loads successfully
   - Missing file raises error
   - Invalid syntax detected

2. **Render Tests**
   - Simple variable substitution
   - All required variables present
   - Missing variable raises error

3. **Format Tests**
   - Generated Python code is syntactically valid
   - No Lua string escaping issues

**Example Test:**
```lua
function TestTemplateLoader:test_render_full_template()
  local loader = TemplateLoader:load("fixtures/rife.vpy.template")
  local vars = {
    script_dir = "C:/path",
    crop_l = 0, crop_t = 20, crop_w = 1920, crop_h = 1080,
    target_w = 1920, target_h = 1080,
    model = 4221, gpu_id = 0, gpu_threads = 2,
    padding_enabled = false,
    padding_orig_w = 1920, padding_orig_h = 1080,
    multiplier = 2
  }

  local result = loader:render(vars)

  lu.assertStrContains(result, 'crop_l=0')
  lu.assertStrContains(result, 'model=4221')
  lu.assertStrContains(result, 'multiplier=2')
end
```

## 9. Success Criteria

### Functional Requirements
- ✅ All existing tests pass (no regressions)
- ✅ New unit tests for StateManager: 100% coverage of public API
- ✅ New unit tests for TemplateLoader: covers load/render/validate
- ✅ Manual mpv testing: all features work as before

### Code Quality Metrics
- ✅ No direct state table access in `rife_main.lua` (all via StateManager)
- ✅ No inline Python code in Lua files
- ✅ All state mutations validated
- ✅ Debug logging preserved (no lost information)

### Maintainability Improvements
- ✅ StateManager interface documented with examples
- ✅ Template file editable without touching Lua code
- ✅ Unit tests run fast (<1 second for full suite)
- ✅ Clear error messages for state violations

### Performance Requirements
- ✅ Template rendering overhead: <1ms
- ✅ StateManager access overhead: <0.1ms per call
- ✅ No measurable difference in VPY generation time

## 10. Open Questions

### Question 1: Template Syntax Choice
**Options:**
- `{{variable}}` (Mustache-style, chosen for design)
- `{variable}` (Jinja2-style, conflicts with Lua)
- `%s` (Lua-style, breaks Python format strings)

**Decision:** Use `{{variable}}` to avoid conflicts with both Lua and Python formatting.

### Question 2: Validation Strictness
**Should validation abort execution or log warnings?**
- **Abort:** Catches bugs immediately, but may break existing edge cases
- **Warn:** Preserves compatibility, but bugs slip through

**Decision:** Implement both modes via `strict_mode` flag (default: warn-only, can enable strict for debugging).

### Question 3: Backward Compatibility
**Should we keep old state table API for one release?**
- **Yes:** Easier rollback, gradual migration
- **No:** Clean break, forces migration

**Decision:** No - StateManager is internal refactoring, external API (keybindings, script messages) unchanged.
