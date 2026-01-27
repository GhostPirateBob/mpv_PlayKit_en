# RIFE Adapting - Frame Interpolation for mpv

Real-time 2x frame rate interpolation using RIFE + TensorRT. Toggled with `Shift+6`.

**Adaptive Mode:**
- fps < 50: Full RIFE pipeline (crop → resize → interpolation → VSR)
- fps ≥ 50: VSR-only mode (direct upscaling, no interpolation)

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

## Key Files

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

## Commands

**Run tests:**
```bash
cd tests && C:/portable/mpv-lazy-new/lua54.exe run_tests.lua
```

**Parse logs:**
JUST RUN IT. Never read the file first unless you need to change it.
Bash(cd mpv-lazy/portable_config/vs/rife_adapting_2 && python mpv_log_reader.py)

## Modifying Code

- Resolution logic → `calculate_targets()` in `rife_core.lua`
- RIFE params → `vsmlrt.RIFE()` call in `rife_processor.py`
- Config defaults → top of `rife_main.lua`

**Config defaults:**
- `enable_x3_adaptive` (default: false)
  - fps ≤ 30 AND resolution ≤ 50% of max_pixels_vsr_on → x3 interpolation
  - Otherwise → x2 interpolation (default)

## Gotchas

- TensorRT rebuilds engine on resolution change (~80s blank frames)
- First run per resolution is slow (engine compilation)
- VSR only works in fullscreen
- Temp files: `%TEMP%\rife_adapting_2_<PID>.vpy`
- High-fps content (≥50fps) bypasses RIFE entirely, applies VSR only
- x3 mode only activates at low resolutions with sufficient GPU headroom
