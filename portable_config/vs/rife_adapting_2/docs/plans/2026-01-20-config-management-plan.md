# Implementation Plan - Config Management

> **Reference:** `docs/designs/2026-01-20-config-management-design.md`
> **Execution:** Use `executing-plans` skill.

---

## Task 1: Create config_loader.lua Module Skeleton

**Goal:** Create empty module with load() signature

**Step 1: Write the Failing Test**
- File: `tests/test_config_loader.lua`
- Code:
```lua
local lu = require("luaunit")
local ConfigLoader = require("config_loader")

function test_module_exists()
    lu.assertNotNil(ConfigLoader)
    lu.assertIsFunction(ConfigLoader.load)
end

function test_load_returns_table()
    local result = ConfigLoader.load("fake_path")
    lu.assertNil(result)  -- Will fail until we implement
end

os.exit(lu.LuaUnit.run())
```

**Step 2: Run Test (Red)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe test_config_loader.lua`
- Expect: "Error: module 'config_loader' not found"

**Step 3: Implementation (Green)**
- File: `config_loader.lua`
- Code:
```lua
local ConfigLoader = {}

function ConfigLoader.load(script_dir)
    return nil  -- TODO: implement
end

return ConfigLoader
```

**Step 4: Verify (Green)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe test_config_loader.lua`
- Expect: PASS (test_module_exists, test_load_returns_table passes with nil)

**Step 5: Git Commit**
- Command: `git add config_loader.lua tests/test_config_loader.lua && git commit -m "feat: add config_loader skeleton"`

---

## Task 2: Implement JSON File Reading

**Goal:** Read config.json from script_dir

**Step 1: Write the Failing Test**
- File: `tests/test_config_loader.lua`
- Code:
```lua
-- Add to existing tests
function test_read_valid_json()
    -- Create temp valid config
    local test_dir = "test_config_temp"
    os.execute("mkdir " .. test_dir .. " 2>nul")

    local f = io.open(test_dir .. "/config.json", "w")
    f:write('{"gpu":{"device_id":0,"threads":2,"max_pixels_vsr_on":2.0,"max_pixels_vsr_off":3.0}}')
    f:close()

    local config = ConfigLoader.load(test_dir)
    lu.assertNotNil(config)
    lu.assertEquals(config.gpu.device_id, 0)

    -- Cleanup
    os.execute("del /Q " .. test_dir .. "\\config.json")
    os.execute("rmdir " .. test_dir)
end
```

**Step 2: Run Test (Red)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe test_config_loader.lua`
- Expect: FAIL (returns nil)

**Step 3: Implementation (Green)**
- File: `config_loader.lua`
- Code:
```lua
local ConfigLoader = {}

function ConfigLoader.load(script_dir)
    local config_path = script_dir .. "/config.json"
    local file = io.open(config_path, "r")
    if not file then
        error("[CONFIG] File not found: " .. config_path)
    end
    local content = file:read("*all")
    file:close()

    -- Parse JSON (simple implementation for now)
    -- For Lua 5.4 without json lib, we'll use a simple parser
    return ConfigLoader._parse_json(content)
end

function ConfigLoader._parse_json(str)
    -- Minimal JSON parser for our config structure
    -- Using load() as safe JSON parser for controlled input
    local func, err = load("return " .. str, "json", "t", {})
    if not func then
        error("[CONFIG] Invalid JSON: " .. err)
    end
    local success, result = pcall(func)
    if not success then
        error("[CONFIG] JSON parse error: " .. result)
    end
    return result
end

return ConfigLoader
```

**Step 4: Verify (Green)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe test_config_loader.lua`
- Expect: PASS

**Step 5: Git Commit**
- Command: `git add config_loader.lua tests/test_config_loader.lua && git commit -m "feat: add JSON reading to config_loader"`

---

## Task 3: Implement Required Field Validation

**Goal:** Fail-fast when required fields missing

**Step 1: Write the Failing Test**
- File: `tests/test_config_loader.lua`
- Code:
```lua
function test_missing_required_section()
    local test_dir = "test_config_temp"
    os.execute("mkdir " .. test_dir .. " 2>nul")

    local f = io.open(test_dir .. "/config.json", "w")
    f:write('{"rife":{"model_number":4221}}')  -- Missing gpu section
    f:close()

    local ok, err = pcall(function()
        ConfigLoader.load(test_dir)
    end)
    lu.assertFalse(ok)
    lu.assertStrContains(err, "gpu")

    os.execute("del /Q " .. test_dir .. "\\config.json")
    os.execute("rmdir " .. test_dir)
end

function test_missing_gpu_device_id()
    local test_dir = "test_config_temp"
    os.execute("mkdir " .. test_dir .. " 2>nul")

    local f = io.open(test_dir .. "/config.json", "w")
    f:write('{"gpu":{"threads":2}}')  -- Missing device_id
    f:close()

    local ok, err = pcall(function()
        ConfigLoader.load(test_dir)
    end)
    lu.assertFalse(ok)
    lu.assertStrContains(err, "device_id")

    os.execute("del /Q " .. test_dir .. "\\config.json")
    os.execute("rmdir " .. test_dir)
end
```

**Step 2: Run Test (Red)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe test_config_loader.lua`
- Expect: FAIL (no validation yet)

**Step 3: Implementation (Green)**
- File: `config_loader.lua`
- Code:
```lua
-- Add after load() function
local REQUIRED_FIELDS = {
    "gpu", "rife", "thresholds", "processing", "tensorrt", "features"
}

local GPU_FIELDS = {"device_id", "threads", "max_pixels_vsr_on", "max_pixels_vsr_off"}
local RIFE_FIELDS = {"model_number", "model_dir", "models", "ensemble", "implementation"}
local THRESHOLDS_FIELDS = {"fps_vsr_only", "fps_x3_mode", "x3_pixel_ratio", "vsr_min_mult"}
local PROCESSING_FIELDS = {"block_align", "min_dimension", "output_format", "working_format"}
local TENSORRT_FIELDS = {"int8", "fp16", "workspace", "use_cuda_graph", "use_cublas", "use_cudnn", "static_shape"}
local FEATURES_FIELDS = {"enable_vsr", "enable_x3_adaptive"}

function ConfigLoader._validate(config)
    -- Check top-level sections
    for _, field in ipairs(REQUIRED_FIELDS) do
        if config[field] == nil then
            error("[CONFIG] Missing required section: '" .. field .. "'")
        end
    end

    -- Check gpu section
    for _, field in ipairs(GPU_FIELDS) do
        if config.gpu[field] == nil then
            error("[CONFIG] Missing required field: 'gpu." .. field .. "'")
        end
    end

    -- Check rife section
    for _, field in ipairs(RIFE_FIELDS) do
        if config.rife[field] == nil then
            error("[CONFIG] Missing required field: 'rife." .. field .. "'")
        end
    end

    -- Check thresholds section
    for _, field in ipairs(THRESHOLDS_FIELDS) do
        if config.thresholds[field] == nil then
            error("[CONFIG] Missing required field: 'thresholds." .. field .. "'")
        end
    end

    -- Check processing section
    for _, field in ipairs(PROCESSING_FIELDS) do
        if config.processing[field] == nil then
            error("[CONFIG] Missing required field: 'processing." .. field .. "'")
        end
    end

    -- Check tensorrt section
    for _, field in ipairs(TENSORRT_FIELDS) do
        if config.tensorrt[field] == nil then
            error("[CONFIG] Missing required field: 'tensorrt." .. field .. "'")
        end
    end

    -- Check features section
    for _, field in ipairs(FEATURES_FIELDS) do
        if config.features[field] == nil then
            error("[CONFIG] Missing required field: 'features." .. field .. "'")
        end
    end
end

-- Modify load() to call validate:
function ConfigLoader.load(script_dir)
    local config_path = script_dir .. "/config.json"
    local file = io.open(config_path, "r")
    if not file then
        error("[CONFIG] File not found: " .. config_path)
    end
    local content = file:read("*all")
    file:close()

    local config = ConfigLoader._parse_json(content)
    ConfigLoader._validate(config)
    return config
end
```

**Step 4: Verify (Green)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe test_config_loader.lua`
- Expect: PASS

**Step 5: Git Commit**
- Command: `git add config_loader.lua tests/test_config_loader.lua && git commit -m "feat: add required field validation"`

---

## Task 4: Implement Type and Range Validation

**Goal:** Validate value types and ranges

**Step 1: Write the Failing Test**
- File: `tests/test_config_loader.lua`
- Code:
```lua
function test_invalid_gpu_id_negative()
    local test_dir = "test_config_temp"
    os.execute("mkdir " .. test_dir .. " 2>nul")

    local f = io.open(test_dir .. "/config.json", "w")
    f:write('{"gpu":{"device_id":-1,"threads":2,"max_pixels_vsr_on":2.0,"max_pixels_vsr_off":3.0},"rife":{"model_number":4221,"model_dir":"rife_v2","models":{},"ensemble":false,"implementation":2},"thresholds":{"fps_vsr_only":50,"fps_x3_mode":30,"x3_pixel_ratio":0.5,"vsr_min_mult":1.3},"processing":{"block_align":32,"min_dimension":32,"output_format":"YUV420P10","working_format":"RGBH"},"tensorrt":{"int8":false,"fp16":true,"workspace":256,"use_cuda_graph":true,"use_cublas":true,"use_cudnn":true,"static_shape":true},"features":{"enable_vsr":true,"enable_x3_adaptive":true}}')
    f:close()

    local ok, err = pcall(function()
        ConfigLoader.load(test_dir)
    end)
    lu.assertFalse(ok)
    lu.assertStrContains(err, ">= 0")

    os.execute("del /Q " .. test_dir .. "\\config.json")
    os.execute("rmdir " .. test_dir)
end

function test_invalid_threads_range()
    local test_dir = "test_config_temp"
    os.execute("mkdir " .. test_dir .. " 2>nul")

    local f = io.open(test_dir .. "/config.json", "w")
    f:write('{"gpu":{"device_id":0,"threads":0,"max_pixels_vsr_on":2.0,"max_pixels_vsr_off":3.0},"rife":{"model_number":4221,"model_dir":"rife_v2","models":{},"ensemble":false,"implementation":2},"thresholds":{"fps_vsr_only":50,"fps_x3_mode":30,"x3_pixel_ratio":0.5,"vsr_min_mult":1.3},"processing":{"block_align":32,"min_dimension":32,"output_format":"YUV420P10","working_format":"RGBH"},"tensorrt":{"int8":false,"fp16":true,"workspace":256,"use_cuda_graph":true,"use_cublas":true,"use_cudnn":true,"static_shape":true},"features":{"enable_vsr":true,"enable_x3_adaptive":true}}')
    f:close()

    local ok, err = pcall(function()
        ConfigLoader.load(test_dir)
    end)
    lu.assertFalse(ok)
    lu.assertStrContains(err, "1-8")

    os.execute("del /Q " .. test_dir .. "\\config.json")
    os.execute("rmdir " .. test_dir)
end
```

**Step 2: Run Test (Red)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe test_config_loader.lua`
- Expect: FAIL (no range validation yet)

**Step 3: Implementation (Green)**
- File: `config_loader.lua`
- Code:
```lua
-- Add to _validate() function, after field existence checks:

    -- Type and range checks: gpu
    if type(config.gpu.device_id) ~= "number" then
        error("[CONFIG] 'gpu.device_id' must be a number")
    end
    if config.gpu.device_id < 0 then
        error("[CONFIG] 'gpu.device_id' must be >= 0, got " .. config.gpu.device_id)
    end

    if type(config.gpu.threads) ~= "number" then
        error("[CONFIG] 'gpu.threads' must be a number")
    end
    if config.gpu.threads < 1 or config.gpu.threads > 8 then
        error("[CONFIG] 'gpu.threads' must be 1-8, got " .. config.gpu.threads)
    end

    if type(config.gpu.max_pixels_vsr_on) ~= "number" then
        error("[CONFIG] 'gpu.max_pixels_vsr_on' must be a number")
    end
    if config.gpu.max_pixels_vsr_on <= 0 then
        error("[CONFIG] 'gpu.max_pixels_vsr_on' must be > 0")
    end

    if type(config.gpu.max_pixels_vsr_off) ~= "number" then
        error("[CONFIG] 'gpu.max_pixels_vsr_off' must be a number")
    end
    if config.gpu.max_pixels_vsr_off <= 0 then
        error("[CONFIG] 'gpu.max_pixels_vsr_off' must be > 0")
    end

    -- Type and range checks: rife
    if type(config.rife.model_number) ~= "number" then
        error("[CONFIG] 'rife.model_number' must be a number")
    end
    if config.rife.model_number <= 0 then
        error("[CONFIG] 'rife.model_number' must be > 0")
    end

    if type(config.rife.model_dir) ~= "string" then
        error("[CONFIG] 'rife.model_dir' must be a string")
    end
    if #config.rife.model_dir == 0 then
        error("[CONFIG] 'rife.model_dir' cannot be empty")
    end

    if type(config.rife.ensemble) ~= "boolean" then
        error("[CONFIG] 'rife.ensemble' must be a boolean")
    end

    if type(config.rife.implementation) ~= "number" then
        error("[CONFIG] 'rife.implementation' must be a number")
    end
    if config.rife.implementation < 1 or config.rife.implementation > 4 then
        error("[CONFIG] 'rife.implementation' must be 1-4")
    end

    -- Type and range checks: thresholds
    if type(config.thresholds.fps_vsr_only) ~= "number" then
        error("[CONFIG] 'thresholds.fps_vsr_only' must be a number")
    end
    if config.thresholds.fps_vsr_only <= 0 then
        error("[CONFIG] 'thresholds.fps_vsr_only' must be > 0")
    end

    if type(config.thresholds.x3_pixel_ratio) ~= "number" then
        error("[CONFIG] 'thresholds.x3_pixel_ratio' must be a number")
    end
    if config.thresholds.x3_pixel_ratio < 0 or config.thresholds.x3_pixel_ratio > 1 then
        error("[CONFIG] 'thresholds.x3_pixel_ratio' must be 0-1")
    end

    -- Type checks: processing
    if type(config.processing.block_align) ~= "number" then
        error("[CONFIG] 'processing.block_align' must be a number")
    end
    local align = config.processing.block_align
    if align <= 0 or (align & (align - 1)) ~= 0 then
        error("[CONFIG] 'processing.block_align' must be power of 2")
    end

    if type(config.processing.min_dimension) ~= "number" then
        error("[CONFIG] 'processing.min_dimension' must be a number")
    end
    if config.processing.min_dimension <= 0 then
        error("[CONFIG] 'processing.min_dimension' must be > 0")
    end

    -- Type checks: tensorrt
    if type(config.tensorrt.int8) ~= "boolean" then
        error("[CONFIG] 'tensorrt.int8' must be a boolean")
    end
    if type(config.tensorrt.fp16) ~= "boolean" then
        error("[CONFIG] 'tensorrt.fp16' must be a boolean")
    end

    -- Type checks: features
    if type(config.features.enable_vsr) ~= "boolean" then
        error("[CONFIG] 'features.enable_vsr' must be a boolean")
    end
    if type(config.features.enable_x3_adaptive) ~= "boolean" then
        error("[CONFIG] 'features.enable_x3_adaptive' must be a boolean")
    end
```

**Step 4: Verify (Green)**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe test_config_loader.lua`
- Expect: PASS

**Step 5: Git Commit**
- Command: `git add config_loader.lua tests/test_config_loader.lua && git commit -m "feat: add type and range validation"`

---

## Task 5: Create config.json with Current Hardcoded Values

**Goal:** Create default config file

**Step 1: Create File**
- File: `config.json`
- Code:
```json
{
  "gpu": {
    "device_id": 0,
    "threads": 2,
    "max_pixels_vsr_on": 2.0,
    "max_pixels_vsr_off": 3.0
  },
  "rife": {
    "model_number": 4221,
    "model_dir": "rife_v2",
    "models": {
      "4151": "rife_v4.15_lite",
      "4221": "rife_v4.22_lite"
    },
    "ensemble": false,
    "implementation": 2
  },
  "thresholds": {
    "fps_vsr_only": 50,
    "fps_x3_mode": 30,
    "x3_pixel_ratio": 0.5,
    "vsr_min_mult": 1.3
  },
  "processing": {
    "block_align": 32,
    "min_dimension": 32,
    "output_format": "YUV420P10",
    "working_format": "RGBH"
  },
  "tensorrt": {
    "int8": false,
    "fp16": true,
    "workspace": 256,
    "use_cuda_graph": true,
    "use_cublas": true,
    "use_cudnn": true,
    "static_shape": true
  },
  "features": {
    "enable_vsr": true,
    "enable_x3_adaptive": true
  }
}
```

**Step 2: Verify File Loads**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe -e "local cl=require('config_loader'); local c=cl.load('../'); print('gpu.device_id='..c.gpu.device_id)"`
- Expect: "gpu.device_id=0"

**Step 3: Git Commit**
- Command: `git add config.json && git commit -m "feat: add config.json with default values"`

---

## Task 6: Modify rife_main.lua to Use ConfigLoader

**Goal:** Replace hardcoded opts with config.json

**Step 1: Read Current Code**
- File: `rife_main.lua`
- Note lines 29-47 (opts table and log)

**Step 2: Backup Current Implementation (Reference)**
- The opts table currently has:
```lua
local opts = {
    max_pixels_vsr_on = 2.0,
    max_pixels_vsr_off = 3.0,
    model = 4221,
    gpu_id = 0,
    gpu_threads = 2,
    enable_vsr = true,
    min_vsr_mult = 1.3,
    enable_x3_adaptive = true,
}
```

**Step 3: Modify rife_main.lua**
- File: `rife_main.lua`
- Action: Replace lines 29-36 with ConfigLoader
- Code:
```lua
-- After local core = require('rife_core')
local ConfigLoader = require('config_loader')
local config = ConfigLoader.load(script_dir_full)

-- Log configuration on load
mp.msg.debug("[rife_adaptive][INIT] Configuration loaded: enable_vsr=" .. tostring(config.features.enable_vsr) ..
             ", max_pixels_vsr_on=" .. config.gpu.max_pixels_vsr_on ..
             ", max_pixels_vsr_off=" .. config.gpu.max_pixels_vsr_off ..
             ", model=" .. config.rife.model_number ..
             ", gpu_id=" .. config.gpu.device_id ..
             ", gpu_threads=" .. config.gpu.threads ..
             ", min_vsr_mult=" .. config.thresholds.vsr_min_mult ..
             ", enable_x3_adaptive=" .. tostring(config.features.enable_x3_adaptive))
```

**Step 4: Update All References to opts**
- File: `rife_main.lua`
- Find and replace all `opts.` references with `config.` sections:
  - `opts.max_pixels_vsr_on` → `config.gpu.max_pixels_vsr_on`
  - `opts.max_pixels_vsr_off` → `config.gpu.max_pixels_vsr_off`
  - `opts.model` → `config.rife.model_number`
  - `opts.gpu_id` → `config.gpu.device_id`
  - `opts.gpu_threads` → `config.gpu.threads`
  - `opts.enable_vsr` → `config.features.enable_vsr`
  - `opts.min_vsr_mult` → `config.thresholds.vsr_min_mult`
  - `opts.enable_x3_adaptive` → `config.features.enable_x3_adaptive`

**Step 5: Verify Script Loads**
- Command: Check mpv log on script load
- Expect: "[rife_adaptive][INIT] Configuration loaded: ..."

**Step 6: Git Commit**
- Command: `git add rife_main.lua && git commit -m "refactor: use config_loader instead of hardcoded opts"`

---

## Task 7: Update rife_core.lua to Use Config.block_align

**Goal:** Remove hardcoded 32 alignment value

**Step 1: Find Hardcoded Align Values**
- File: `rife_core.lua`
- Search: All occurrences of `32` as alignment value

**Step 2: Modify calculate_targets() signature**
- File: `rife_core.lua`
- Change function signature to accept block_align:
```lua
function M.calculate_targets(crop_w, crop_h, screen_w, screen_h, opts, block_align)
```

**Step 3: Replace Hardcoded 32 with block_align parameter**
- File: `rife_core.lua`
- Replace:
  - `M.align_to_multiple_ceil(crop_w, 32)` → `M.align_to_multiple_ceil(crop_w, block_align)`
  - `M.align_to_multiple_ceil(crop_h, 32)` → `M.align_to_multiple_ceil(crop_h, block_align)`
  - `M.align_to_multiple(screen_w, 32)` → `M.align_to_multiple(screen_w, block_align)`
  - `M.align_to_multiple(screen_h, 32)` → `M.align_to_multiple(screen_h, block_align)`
  - `if target_h < 32 then target_h = 32 end` → `if target_h < block_align then target_h = block_align end`

**Step 4: Update rife_main.lua Call Site**
- File: `rife_main.lua`
- Find: `core.calculate_targets(...)` call
- Add `config.processing.block_align` as last argument

**Step 5: Git Commit**
- Command: `git add rife_core.lua rife_main.lua && git commit -m "refactor: use config.block_align in rife_core"`

---

## Task 8: Update Template with New Placeholders

**Goal:** Add all config values to VPY template

**Step 1: Read Current Template**
- File: `templates/rife.vpy.template`
- Note existing placeholders: `{{crop_l}}`, `{{crop_t}}`, etc.

**Step 2: Add New Placeholders**
- File: `templates/rife.vpy.template`
- Add to process() function call and parameters:
```python
# Add these new placeholders in the process() call:
model={{model_number}},
gpu_id={{gpu_device_id}},
gpu_t={{gpu_threads}},
multiplier={{multiplier}},

# Add TensorRT backend params:
int8={{trt_int8}},
fp16={{trt_fp16}},
workspace={{trt_workspace}},
use_cuda_graph={{trt_cuda_graph}},
use_cublas={{trt_cublas}},
use_cudnn={{trt_cudnn}},
static_shape={{trt_static_shape}},

# Add model path construction:
mdl_pname = "{{model_dir}}/"
mdl_fname = {{model_map}}
```

**Step 3: Git Commit**
- Command: `git add templates/rife.vpy.template && git commit -m "feat: add config placeholders to VPY template"`

---

## Task 9: Update rife_processor.py to Use Template Vars

**Goal:** Remove hardcoded values from Python

**Step 1: Read Current rife_processor.py**
- File: `rife_processor.py`
- Note hardcoded values:
  - `mdl_pname = "rife_v2/"`
  - Model mapping dict
  - TensorRT params

**Step 2: Modify process() Function**
- File: `rife_processor.py`
- Add parameters for all config values:
```python
def process(
    clip: vs.VideoNode,
    crop_l: int,
    crop_t: int,
    crop_w: int,
    crop_h: int,
    target_w: int,
    target_h: int,
    model: int,
    gpu_id: int,
    gpu_t: int,
    padding_enabled: bool = False,
    padding_orig_w: int = 0,
    padding_orig_h: int = 0,
    multiplier: int = 2,
    # NEW: Config from template
    model_dir: str = "rife_v2",
    model_map: str = "{}",  # JSON string of model mapping
    ensemble: bool = False,
    implementation: int = 2,
    trt_int8: bool = False,
    trt_fp16: bool = True,
    trt_workspace: int = 256,
    trt_cuda_graph: bool = True,
    trt_cublas: bool = True,
    trt_cudnn: bool = True,
    trt_static_shape: bool = True,
) -> vs.VideoNode:
```

**Step 3: Replace Hardcoded Values**
- File: `rife_processor.py`
- Replace:
  - `mdl_pname = "rife_v2/"` → `mdl_pname = model_dir + "/"`
  - Model mapping dict → Parse from `model_map` JSON or use new params
  - Hardcoded TensorRT params → Use function parameters

**Step 4: Git Commit**
- Command: `git add rife_processor.py && git commit -m "refactor: use template vars for config in rife_processor"`

---

## Task 10: Update TemplateLoader to Pass Config Values

**Goal:** Render template with all config values

**Step 1: Read TemplateLoader**
- File: `rife_template_loader.lua`
- Note current render() function

**Step 2: Modify render() to Accept config**
- File: `rife_template_loader.lua`
- Add config parameter and merge with template vars:
```lua
function TemplateLoader.render(template_content, vars, config)
    local all_vars = {}
    -- Copy existing vars
    for k, v in pairs(vars) do
        all_vars[k] = v
    end
    -- Add config values
    all_vars.model_number = config.rife.model_number
    all_vars.gpu_device_id = config.gpu.device_id
    all_vars.gpu_threads = config.gpu.threads
    all_vars.model_dir = config.rife.model_dir
    all_vars.trt_int8 = tostring(config.tensorrt.int8)
    -- ... all other config values

    -- Existing placeholder replacement logic
    for k, v in pairs(all_vars) do
        template_content = template_content:gsub("{{" .. k .. "}}", tostring(v))
    end
    return template_content
end
```

**Step 3: Update rife_main.lua Call Site**
- File: `rife_main.lua`
- Pass `config` to `TemplateLoader.render()`

**Step 4: Git Commit**
- Command: `git add rife_template_loader.lua rife_main.lua && git commit -m "feat: pass config to template renderer"`

---

## Task 11: Update Existing Tests for New Signature

**Goal:** Fix tests that call calculate_targets()

**Step 1: Find All calculate_targets() Calls in Tests**
- Command: `cd tests && grep -n "calculate_targets" test_rife_core.lua`

**Step 2: Update Test Calls**
- File: `tests/test_rife_core.lua`
- For each call, add `block_align` parameter (usually 32):
```lua
-- Before:
local result = core.calculate_targets(1920, 1080, 2560, 1440, opts)

-- After:
local result = core.calculate_targets(1920, 1080, 2560, 1440, opts, 32)
```

**Step 3: Run All Tests**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua`
- Expect: All PASS

**Step 4: Git Commit**
- Command: `git add tests/test_rife_core.lua && git commit -m "test: update calculate_targets calls with block_align"`

---

## Task 12: Integration Test - End to End

**Goal:** Verify full pipeline works with config.json

**Step 1: Run mpv with Script**
- Command: Open mpv with any video file
- Press: `Shift+6` to toggle RIFE

**Step 2: Verify Config Loading**
- Check mpv log for: "[rife_adaptive][INIT] Configuration loaded"
- Verify all config values match config.json

**Step 3: Verify VPY Generation**
- Check temp directory for generated .vpy file
- Open and verify template placeholders replaced with config values

**Step 4: Test Invalid Config**
- Temporarily rename config.json
- Start mpv
- Expect: OSD error "[RIFE] CONFIG ERROR: File not found"
- Restore config.json

**Step 5: Git Commit**
- Command: `git commit --allow-empty -m "test: verify end-to-end config integration"`

---

## Task 13: Clean Up - Remove Old Tests Temp Directory

**Goal:** Remove test_config_temp if exists

**Step 1: Check for Artifacts**
- Command: `dir test_config_temp 2>nul`
- If exists, remove it

**Step 2: Final Test Run**
- Command: `cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua`
- Expect: All tests PASS

**Step 3: Git Commit**
- Command: `git add . && git commit -m "chore: cleanup config management implementation complete"`
