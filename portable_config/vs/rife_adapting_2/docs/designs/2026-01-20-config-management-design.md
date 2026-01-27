# Design: Configuration Management & Persistence

## 1. Problem Statement

All configuration is currently hardcoded in Lua (`rife_main.lua` opts table) and Python (`rife_processor.py`). This requires:
- Code changes for simple adjustments
- Source file editing for end users
- No persistent settings across updates
- Risk of merge conflicts when updating

## 2. Goals & Non-Goals

**Must do:**
- Single `config.json` with all configurable values
- Fail-fast if config missing or invalid (OSD error + log)
- No hardcoded defaults in code
- Schema validation with clear error messages
- Runtime reload capability (optional future)

**Won't do:**
- Color matrix mappings (stays in Python)
- Multiple config files
- Environment variable overrides
- GUI config editor

## 3. Proposed Architecture

```
config.json (required)
      ↓
ConfigLoader (new module)
      ↓
    Validation
      ↓
  rife_main.lua ────────→ TemplateLoader
      ↓                        ↓
   opts table           rendered VPY
      ↓
rife_processor.py (receives via template vars)
```

**New module:** `config_loader.lua`
- Loads `config.json` from script directory
- Validates all required fields exist
- Type-checks values
- Returns validated config table or throws error

## 4. Config Schema

```json
{
  "$schema": "./config.schema.json",

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

## 5. Module Interface

### config_loader.lua

```lua
local ConfigLoader = {}

-- Load and validate config from script_dir/config.json
-- @param script_dir: string path to script directory
-- @return config table with all validated values
-- @error throws if file missing, invalid JSON, or validation fails
function ConfigLoader.load(script_dir)
    -- 1. Construct file path
    -- 2. Read file content
    -- 3. Parse JSON
    -- 4. Validate schema
    -- 5. Return validated config
end

-- Internal validation
function ConfigLoader._validate(config)
    -- Check all required top-level sections
    -- Type check each value
    -- Range check numbers (gpu_id >= 0, etc.)
    -- Throw descriptive errors
end

return ConfigLoader
```

### Error Display

```lua
-- On load failure:
mp.osd_message("[RIFE] CONFIG ERROR: Missing 'gpu.device_id' in config.json", 10)
mp.msg.error("[CONFIG] Validation failed: Missing 'gpu.device_id'")
```

## 6. Validation Rules

| Path | Type | Range | Required |
|------|------|-------|----------|
| `gpu.device_id` | int | >= 0 | ✅ |
| `gpu.threads` | int | 1-8 | ✅ |
| `gpu.max_pixels_vsr_on` | float | > 0 | ✅ |
| `gpu.max_pixels_vsr_off` | float | > 0 | ✅ |
| `rife.model_number` | int | > 0 | ✅ |
| `rife.model_dir` | string | non-empty | ✅ |
| `rife.models` | object | ≥1 entry | ✅ |
| `rife.ensemble` | bool | - | ✅ |
| `rife.implementation` | int | 1-4 | ✅ |
| `thresholds.fps_vsr_only` | float | > 0 | ✅ |
| `thresholds.fps_x3_mode` | float | > 0 | ✅ |
| `thresholds.x3_pixel_ratio` | float | 0-1 | ✅ |
| `thresholds.vsr_min_mult` | float | > 0 | ✅ |
| `processing.block_align` | int | power of 2 | ✅ |
| `processing.min_dimension` | int | > 0 | ✅ |
| `processing.output_format` | string | valid VS format | ✅ |
| `processing.working_format` | string | valid VS format | ✅ |
| `tensorrt.int8` | bool | - | ✅ |
| `tensorrt.fp16` | bool | - | ✅ |
| `tensorrt.workspace` | int | > 0 | ✅ |
| `tensorrt.use_cuda_graph` | bool | - | ✅ |
| `tensorrt.use_cublas` | bool | - | ✅ |
| `tensorrt.use_cudnn` | bool | - | ✅ |
| `tensorrt.static_shape` | bool | - | ✅ |
| `features.enable_vsr` | bool | - | ✅ |
| `features.enable_x3_adaptive` | bool | - | ✅ |

## 7. Code Changes Required

### rife_main.lua
**Remove:** `opts` table (lines 29-36)
**Add:** Config loading at startup
```lua
local ConfigLoader = require('config_loader')
local config = ConfigLoader.load(script_dir_full)
```

### rife_core.lua
**Change:** Accept `config.processing.block_align` instead of hardcoded 32
**Change:** Accept `config.processing.min_dimension` instead of hardcoded 32

### rife_processor.py
**Add:** Template vars for all TensorRT params, model paths
**Change:** Read model path from template vars instead of hardcoded `rife_v2/`

### templates/rife.vpy.template
**Add:** New placeholders for all config values

## 8. Migration Strategy

1. Create `config_loader.lua` module with tests
2. Create `config.json` with current hardcoded values
3. Modify `rife_main.lua` to use ConfigLoader
4. Update template with new placeholders
5. Update `rife_processor.py` to use template vars
6. Update `rife_core.lua` for processing params
7. Delete hardcoded opts table
8. Update tests

## 9. Risks & Edge Cases

**What if config.json is deleted?**
- Script fails to load with OSD error
- User must restore or recreate config

**What if invalid JSON?**
- Parse error shown in OSD + log
- File path and line number included

**What if value out of range?**
- Validation error: "gpu.device_id must be >= 0, got -1"
- Script stops

**What if user edits config while mpv running?**
- Changes take effect on next mpv restart
- (Future: hot-reload with keybinding)

**What if new field added in update?**
- Validation fails with clear message
- User prompted to add new field
- Could provide "config.json.example" with all fields

## 10. Testing

```lua
-- tests/test_config_loader.lua
function test_load_valid_config()
function test_missing_file()
function test_invalid_json()
function test_missing_required_field()
function test_invalid_type()
function test_out_of_range()
function test_minimal_valid_config()
```

## 11. File Layout

```
rife_adapting_2/
├── config.json                 (NEW - required)
├── config_loader.lua           (NEW)
├── rife_main.lua              (MODIFIED - remove opts)
├── rife_core.lua              (MODIFIED - use config)
├── rife_processor.py          (MODIFIED - template vars)
├── templates/
│   └── rife.vpy.template      (MODIFIED - new placeholders)
└── tests/
    ├── test_config_loader.lua (NEW)
    └── ...
```
