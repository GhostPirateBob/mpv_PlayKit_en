--[[
    rife_main.lua - Simplified RIFE controller

    Keybinding: Ctrl+6 to toggle RIFE on/off

    Features:
    - One-time black bar crop detection
    - Resolution downscaling based on GPU power
    - RIFE interpolation via k7sfunc
    - Nvidia VSR upscaling to screen height
]]

local mp = require 'mp'

-- Add script directory to package path for local modules
local script_path = debug.getinfo(1, "S").source:sub(2)  -- Remove @ prefix
local script_dir = script_path:match("(.*/)")  or script_path:match("(.*\\)") or ""
package.path = script_dir .. "?.lua;" .. package.path

local core = require('rife_core')
local StateManager = require('rife_state_manager')
local TemplateLoader = require('rife_template_loader')
local ConfigLoader = require('config_loader')
local PauseHandler = require('rife_pause_handler')

-----------
-- Configuration
-----------

local script_dir_full = mp.command_native({"expand-path", "~~/vs/rife_adapting_2"})
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

-----------
-- State
-----------

local state_manager = StateManager:new(mp.get_property_native("pid") or "0")

-- Load VPY template
local template = TemplateLoader:load(script_dir_full .. "/templates/rife.vpy.template")

-----------
-- Forward Declarations
-----------

local generate_and_apply_vpy

-----------
-- Helper Functions
-----------

local function get_temp_dir()
    return core.get_temp_dir_path({
        TEMP = os.getenv("TEMP"),
        TMP = os.getenv("TMP"),
        TMPDIR = os.getenv("TMPDIR")
    })
end

local function get_source_dims()
    local w = mp.get_property_native("video-params/w") or 1920
    local h = mp.get_property_native("video-params/h") or 1080
    return w, h
end

local function get_screen_dims()
    local w = mp.get_property_native("display-width") or mp.get_property_native("display-res-x")
    local h = mp.get_property_native("display-height") or mp.get_property_native("display-res-y")
    return w or 2560, h or 1440
end

local function get_container_fps()
    return mp.get_property_number("container-fps") or 24.0
end

local function osd_message(msg, duration)
    duration = duration or 3
    mp.osd_message("[RIFE] " .. msg, duration)
end

local function update_vsr_state()
    mp.msg.debug("[rife_adaptive][VSR] Update requested: rife_active=" .. tostring(state_manager:get_rife_active()) ..
                 ", vsr_path=" .. tostring(state_manager:get_vsr_path_active()) ..
                 ", fullscreen=" .. tostring(state_manager:get_is_fullscreen()) ..
                 ", target=" .. tostring(state_manager:get_target_w()) .. "x" .. tostring(state_manager:get_target_h()))

    if not state_manager:get_rife_active() or not state_manager:get_vsr_path_active() or not state_manager:get_target_w() then
        mp.commandv("vf", "remove", "@rife-vsr")
        mp.msg.debug("[rife_adaptive][VSR] Removed (not in VSR path or RIFE inactive)")
        return
    end

    if state_manager:get_is_fullscreen() then
        local screen_w, screen_h = get_screen_dims()

        mp.msg.debug("[rife_adaptive][VSR] Calculating scale: screen=" .. screen_w .. "x" .. screen_h ..
                     ", target=" .. state_manager:get_target_w() .. "x" .. state_manager:get_target_h())

        local scale_w = screen_w / state_manager:get_target_w()
        local scale_h = screen_h / state_manager:get_target_h()
        local vsr_scale = math.min(scale_w, scale_h)

        mp.msg.debug("[rife_adaptive][VSR] Scale check: " .. string.format("%.2f", vsr_scale) ..
                     " >= " .. config.thresholds.vsr_min_mult)

        if vsr_scale >= config.thresholds.vsr_min_mult then
            mp.commandv("vf", "remove", "@rife-vsr")
            mp.command(string.format('vf add @rife-vsr:d3d11vpp:scaling-mode=nvidia:scale=%.10f', vsr_scale))
            mp.msg.debug("[rife_adaptive][VSR] ACTIVATED: scale=" .. string.format("%.2f", vsr_scale))
            osd_message("VSR ON", 2)
            return
        else
            mp.msg.debug("[rife_adaptive][VSR] DEACTIVATED: scale too low (" .. string.format("%.2f", vsr_scale) .. ")")
        end
    end

    mp.commandv("vf", "remove", "@rife-vsr")
    if state_manager:get_is_fullscreen() then
        osd_message("VSR OFF", 2)
    end
end

-----------
-- Crop Detection
-----------

-- Config for crop detection
local MAX_CROP_RATIO = 0.30  -- Max 30% of height can be cropped (prevents false positives on dark scenes)
local CROP_LIMIT_RATIO = 16/255  -- limit=16/255 (~6.3%) instead of 24/255 (~9.4%) for dark scenes

local function finish_crop_detection()
    if state_manager:get_cropdetect_timer() then
        state_manager:get_cropdetect_timer():kill()
    end

    local meta = mp.get_property_native("vf-metadata/rife-cropdetect") or {}
    mp.commandv("vf", "remove", "@rife-cropdetect")

    local w = tonumber(meta["lavfi.cropdetect.w"])
    local h = tonumber(meta["lavfi.cropdetect.h"])
    local x = tonumber(meta["lavfi.cropdetect.x"])
    local y = tonumber(meta["lavfi.cropdetect.y"])

    mp.msg.debug("[rife_adaptive][CROP] Raw metadata: w=" .. (w or "nil") ..
                 ", h=" .. (h or "nil") ..
                 ", x=" .. (x or "nil") ..
                 ", y=" .. (y or "nil"))

    local crop_result
    if w and h and x and y then
        local source_w, source_h = get_source_dims()

        -- Calculate actual crop amounts from each side
        local crop_left = x
        local crop_right = source_w - (x + w)
        local crop_top = y
        local crop_bottom = source_h - (y + h)

        mp.msg.debug("[rife_adaptive][CROP] Crop amounts: L=" .. crop_left .. ", R=" .. crop_right ..
                     ", T=" .. crop_top .. ", B=" .. crop_bottom)

        -- Normalize to symmetric: use MIN crop from opposite sides
        -- Safer: if one side has excessive crop due to dark scene, we don't over-crop
        local crop_h_sym = math.min(crop_left, crop_right)
        local crop_v_sym = math.min(crop_top, crop_bottom)

        -- Recalculate centered crop
        x = crop_h_sym
        y = crop_v_sym
        w = source_w - (crop_h_sym * 2)
        h = source_h - (crop_v_sym * 2)

        mp.msg.debug("[rife_adaptive][CROP] Symmetric: using min H=" .. crop_h_sym .. ", V=" .. crop_v_sym ..
                     " → " .. w .. "x" .. h .. " at (" .. x .. "," .. y .. ")")

        if h < source_h then
            local removed_px = source_h - h
            local crop_ratio = removed_px / source_h

            -- Sanity check: don't crop if removing too much (likely dark scene content, not black bars)
            if crop_ratio > MAX_CROP_RATIO then
                crop_result = nil
                mp.msg.debug("[rife_adaptive][CROP] Rejected: would remove " .. string.format("%.1f%%", crop_ratio * 100) ..
                             " of frame (max " .. string.format("%.1f%%", MAX_CROP_RATIO * 100) .. ")")
                osd_message("Crop rejected (too aggressive)")
            else
                crop_result = { w = w, h = h, x = x, y = y }
                mp.msg.debug("[rife_adaptive][CROP] Result: " .. w .. "x" .. h ..
                             " at (" .. x .. "," .. y .. "), removed " .. removed_px .. "px vertical (" ..
                             string.format("%.1f%%", crop_ratio * 100) .. ")")
                osd_message(string.format("Crop: %dx%d", w, h))
            end
        else
            crop_result = nil
            mp.msg.debug("[rife_adaptive][CROP] No black bars detected, using full frame " .. source_w .. "x" .. source_h)
            osd_message("No black bars detected")
        end
    else
        crop_result = nil
        mp.msg.debug("[rife_adaptive][CROP] Detection failed, metadata incomplete")
        osd_message("Crop detection failed")
    end

    state_manager:complete_crop_detection(crop_result)
    generate_and_apply_vpy()
end

local function start_crop_detection()
    -- Check if user requested to skip crop (from previous abort during engine build)
    if state_manager:get_skip_crop() then
        mp.msg.debug("[rife_adaptive][CROP] Skipping crop detection (user requested skip)")
        state_manager:complete_crop_detection(nil)  -- No crop
        generate_and_apply_vpy()
        return
    end

    state_manager:complete_crop_detection(nil)  -- Clear any existing crop
    state_manager:set_initializing(true)  -- Mark as initializing (for shutdown detection)
    mp.msg.debug("[rife_adaptive][CROP] Starting detection (1s timeout)")
    osd_message("Detecting black bars...", 1)

    -- Use stricter limit to avoid false positives on dark scenes
    mp.commandv("vf", "pre", "@rife-cropdetect:lavfi=[cropdetect=limit=" .. CROP_LIMIT_RATIO .. ":round=2:reset=1]")
    local timer = mp.add_timeout(1.0, finish_crop_detection)
    state_manager:set_crop_detection_timer(timer)
end

-----------
-- VPY Generation
-----------

-----------
-- Core Resolution Calculation (Unified Logic)
-----------

generate_and_apply_vpy = function()
    local source_w, source_h = get_source_dims()
    local crop_w, crop_h, crop_x, crop_y = source_w, source_h, 0, 0

    -- Use crop if detected
    local current_crop = state_manager:get_current_crop()
    if current_crop then
        crop_w = current_crop.w
        crop_h = current_crop.h
        crop_x = current_crop.x
        crop_y = current_crop.y
    end

    mp.msg.debug("[rife_adaptive][VPY] Source: " .. source_w .. "x" .. source_h ..
                 ", Crop: " .. crop_w .. "x" .. crop_h ..
                 " at (" .. crop_x .. "," .. crop_y .. ")")

    -- UNIFIED LOGIC: Calculate targets and determine path in one place
    local screen_w, screen_h = get_screen_dims()
    local result = core.calculate_targets(crop_w, crop_h, screen_w, screen_h, config)

    -- Store results in state
    state_manager:set_pipeline_targets(result.target_w, result.target_h, result.vsr_path)

    -- Calculate interpolation multiplier (x2 or x3)
    local fps = get_container_fps()
    local target_pixels = result.target_w * result.target_h
    local x3_threshold = config.gpu.max_pixels_vsr_on * 1000000 / 2
    local use_x3 = config.features.enable_x3_adaptive and fps <= 30 and target_pixels <= x3_threshold
    local multiplier = use_x3 and 3 or 2

    mp.msg.debug("[rife_adaptive][MULTI] fps=" .. fps ..
                 ", target_pixels=" .. target_pixels ..
                 ", x3_threshold=" .. x3_threshold ..
                 ", use_x3=" .. tostring(use_x3) ..
                 ", multiplier=" .. multiplier)

    -- Build pipeline string for OSD
    local mode_str = use_x3 and "x3" or "x2"
    local pipeline_str
    if result.padding.enabled then
        pipeline_str = string.format("%dx%d -> pad %dx%d -> RIFE [%s] -> %dx%d",
            result.pipeline.crop_w, result.pipeline.crop_h,
            result.pipeline.process_w, result.pipeline.process_h,
            mode_str,
            result.pipeline.output_w, result.pipeline.output_h)
    else
        pipeline_str = string.format("%dx%d -> scale %dx%d -> RIFE [%s] -> %dx%d",
            result.pipeline.crop_w, result.pipeline.crop_h,
            result.pipeline.process_w, result.pipeline.process_h,
            mode_str,
            result.pipeline.output_w, result.pipeline.output_h)
    end

    mp.msg.debug(string.format("[rife_adaptive][VPY] Resolution: %s (Scale %.2f) | VSR Path: %s | Padding: %s",
        pipeline_str, result.scale, tostring(result.vsr_path), tostring(result.padding.enabled)))

    -- Generate VPY content from template
    local template_vars = state_manager:export_for_template({
        script_dir = script_dir_full,
        multiplier = multiplier,
        padding_enabled = result.padding.enabled and "True" or "False",
        padding_orig_w = result.padding.orig_w,
        padding_orig_h = result.padding.orig_h,
    })

    local vpy_content = template:render(template_vars, config)

    -- Write VPY file (unique per PID to support multiple mpv instances)
    local vpy_path = get_temp_dir() .. "/rife_adapting_2_" .. state_manager:get_pid() .. ".vpy"
    local f = io.open(vpy_path, "w")
    if not f then
        mp.msg.debug("[rife_adaptive][VPY] ERROR: Failed to create VPY file at " .. vpy_path)
        osd_message("Failed to create VPY", 5)
        return
    end
    f:write(vpy_content)
    f:close()

    mp.msg.debug("[rife_adaptive][VPY] Script written to: " .. vpy_path)

    -- Remove our filters (safe if not present)
    mp.commandv("vf", "remove", "@rife-vsr")
    mp.commandv("vf", "remove", "@rife-vs")

    -- Apply vapoursynth filter WITH LABEL for proper removal
    mp.command(string.format('vf add @rife-vs:vapoursynth="%s"', vpy_path))
    mp.msg.debug("[rife_adaptive][VPY] VapourSynth filter applied")

    -- Clear initializing flag - activation complete
    state_manager:set_initializing(false)

    -- Clear skip_crop flag after successful activation
    if state_manager:get_skip_crop() then
        state_manager:clear_skip_crop()
        mp.msg.debug("[rife_adaptive][VPY] Cleared skip_crop flag (activation succeeded)")
    end

    -- Update VSR state
    update_vsr_state()

    -- Show OSD status
    local vsr_status
    if state_manager:get_vsr_path_active() then
        if state_manager:get_is_fullscreen() then
            local _, screen_h_disp = get_screen_dims()
            vsr_status = tostring(screen_h_disp) .. "p (VSR)"
        else
            vsr_status = tostring(result.pipeline.output_h) .. "p (VSR ready)"
        end
    else
        vsr_status = tostring(result.pipeline.output_h) .. "p"
    end

    local status = string.format("%dx%d -> %s -> %s",
        source_w, source_h,
        pipeline_str,
        vsr_status)
    osd_message(status, 4)
end

-----------
-- Toggle Handler
-----------

local function toggle_rife()
    if state_manager:get_rife_active() then
        -- Turn off
        mp.msg.debug("[rife_adaptive][TOGGLE] RIFE deactivation requested")

        if state_manager:get_cropdetect_timer() then
            state_manager:get_cropdetect_timer():kill()
            mp.msg.debug("[rife_adaptive][TOGGLE] Killed pending crop detection timer")
        end

        mp.commandv("vf", "remove", "@rife-vsr")
        mp.commandv("vf", "remove", "@rife-vs")
        state_manager:deactivate_rife()
        mp.msg.debug("[rife_adaptive][TOGGLE] RIFE deactivated, filters removed, state reset")
        osd_message("OFF")
    else
        -- Turn on
        local fps = get_container_fps()
        mp.msg.debug("[rife_adaptive][TOGGLE] RIFE activation requested, container_fps=" .. fps)

        if fps >= 50 then
            -- High-FPS mode: VSR only, skip RIFE/crop/VPY
            mp.msg.debug("[rife_adaptive][TOGGLE] FPS check: " .. fps .. " >= 50 = VSR-only mode")
            state_manager:activate_rife("vsr_only")

            local source_w, source_h = get_source_dims()
            state_manager:set_pipeline_targets(source_w, source_h, true)

            mp.msg.debug("[rife_adaptive][TOGGLE] VSR-only mode: target=" .. source_w .. "x" .. source_h)
            update_vsr_state()
            osd_message(string.format("VSR-only (%.2f fps)", fps), 3)
        else
            -- Normal RIFE mode
            mp.msg.debug("[rife_adaptive][TOGGLE] FPS check: " .. fps .. " < 50 = RIFE mode")
            state_manager:activate_rife("normal")
            start_crop_detection()
        end
    end
end

-----------
-- Fullscreen Observer
-----------

-- Skip crop detection and retry with 0 crop
-- Use this when crop detection is causing issues or engine build is taking too long
local function skip_crop_and_retry()
    if not state_manager:get_rife_active() then
        osd_message("RIFE not active", 2)
        return
    end

    -- Set skip_crop flag (persists to disk)
    state_manager:request_skip_crop()
    mp.msg.debug("[rife_adaptive][SKIP_CROP] User requested skip crop - retrying with full frame")

    -- Kill any pending crop detection
    if state_manager:get_cropdetect_timer() then
        state_manager:get_cropdetect_timer():kill()
    end

    -- Remove filters and regenerate VPY with no crop
    mp.commandv("vf", "remove", "@rife-vsr")
    mp.commandv("vf", "remove", "@rife-vs")
    state_manager:complete_crop_detection(nil)  -- Clear crop
    generate_and_apply_vpy()
    osd_message("Retry: No crop", 3)
end

local function on_fullscreen_change(name, value)
    state_manager:set_fullscreen(value or false)
    mp.msg.debug("[rife_adaptive][FULLSCREEN] State changed: " .. tostring(state_manager:get_is_fullscreen()) ..
                 ", rife_active=" .. tostring(state_manager:get_rife_active()))
    if state_manager:get_rife_active() then
        update_vsr_state()
    end
end

-----------
-- Shutdown Handler
-----------

-- Detect when mpv closes during RIFE initialization (e.g., during TensorRT engine build)
-- Automatically sets skip_crop flag so next run will skip crop detection
local function on_shutdown()
    if state_manager:should_skip_on_shutdown() then
        state_manager:request_skip_crop()
        mp.msg.debug("[rife_adaptive][SHUTDOWN] RIFE was still initializing - set skip_crop for next run")
    end
end

mp.register_event("shutdown", on_shutdown)

-----------
-- Keybinding
-----------

-- Bind Shift+6 across different keyboard layouts
-- US QWERTY: ^ | German QWERTZ: & | French AZERTY: ° | Spanish: ^ | Italian: ° | Russian: :
local shift6_keys = {"^", "&", "°", ":"}
for _, key in ipairs(shift6_keys) do
    mp.add_key_binding(key, "toggle-rife-" .. key, toggle_rife)
end

-- Also bind literal Shift+6 (works on some systems)
mp.add_forced_key_binding("Shift+6", "toggle-rife-shift6", toggle_rife)

-- Bind Alt+6 for skip crop and retry (when crop detection is problematic)
mp.add_key_binding("Alt+6", "skip-crop-retry", skip_crop_and_retry)

mp.register_script_message("toggle-adaptive-rife", toggle_rife)
mp.register_script_message("skip-crop-retry", skip_crop_and_retry)

-----------
-- Pause Handler (GPU Warmup)
-----------

local pause_handler = PauseHandler:new(mp, state_manager)
pause_handler:register_observers()

-----------
-- Initialization
-----------

-- Initialize fullscreen state
state_manager:set_fullscreen(mp.get_property_native("fullscreen") or false)

-- Observe fullscreen changes
mp.observe_property("fullscreen", "bool", on_fullscreen_change)

-- Show startup message to confirm script loaded
mp.add_timeout(3, function()
    mp.msg.info("RIFE rife_adapting_2 loaded - Press Shift+6 to toggle")
    mp.msg.debug("[rife_adaptive][INIT] Script fully initialized, keybindings registered")
    osd_message("Loaded (Shift+6)", 2)
end)
