-- rife_core.lua - Pure functions for RIFE processing (no mpv/OS dependencies)

local M = {}

-- Get temp directory path from environment variables
-- env_vars: table with TEMP, TMP, TMPDIR keys (may be nil)
-- Returns: string path to temp directory
function M.get_temp_dir_path(env_vars)
    return env_vars.TEMP or env_vars.TMP or env_vars.TMPDIR or "/tmp"
end

-- Align value to nearest lower multiple
-- value: number to align
-- multiple: alignment boundary (e.g., 32 for GPU)
-- Returns: aligned integer
function M.align_to_multiple(value, multiple)
    return math.floor(value / multiple) * multiple
end

-- Align value to nearest higher multiple (ceiling)
-- value: number to align
-- multiple: alignment boundary (e.g., 32 for GPU)
-- Returns: aligned integer (rounded up)
function M.align_to_multiple_ceil(value, multiple)
    return math.ceil(value / multiple) * multiple
end

-- Calculate scale factor to fit source within max bounds (preserving AR)
-- Does not upscale (returns 1.0 if source smaller than bounds)
-- src_w, src_h: source dimensions
-- max_w, max_h: maximum dimensions
-- Returns: scale factor (0.0-1.0)
function M.calculate_scale_to_fit(src_w, src_h, max_w, max_h)
    local scale_w = max_w / src_w
    local scale_h = max_h / src_h
    local scale = math.min(scale_w, scale_h)

    -- Don't upscale - degrades quality before RIFE
    if scale > 1.0 then
        return 1.0
    end

    return scale
end

-- Calculate target dimensions and determine VSR path
-- This is the core resolution calculation logic (DRY constraint-based approach)
-- crop_w, crop_h: cropped source dimensions
-- screen_w, screen_h: display dimensions
-- config: configuration table with nested sections
-- Returns: table with target_w, target_h, vsr_path, scale, padding, pipeline
function M.calculate_targets(crop_w, crop_h, screen_w, screen_h, config)
    local block_align = config.processing.block_align

    -- 1. Determine Geometric Constraints
    local scale_w = screen_w / crop_w
    local scale_h = screen_h / crop_h
    local scale_screen = math.min(scale_w, scale_h)

    -- 2. Determine VSR Eligibility & Budget
    local use_vsr_path = false
    local budget_mb = config.gpu.max_pixels_vsr_off

    if config.features.enable_vsr then
        if scale_screen >= config.thresholds.vsr_min_mult then
            use_vsr_path = true
            budget_mb = config.gpu.max_pixels_vsr_on
        end
    end

    local max_pixels = budget_mb * 1000000

    -- 3. Check if Padding is Viable
    local padded_w = M.align_to_multiple_ceil(crop_w, block_align)
    local padded_h = M.align_to_multiple_ceil(crop_h, block_align)
    local padded_pixels = padded_w * padded_h

    local use_padding = false
    local target_w, target_h, actual_scale
    local orig_w, orig_h, pad_w, pad_h = crop_w, crop_h, 0, 0

    -- Padding only viable if:
    -- A) Padded dims fit within pixel budget
    -- B) Padded dims fit within screen (no upscaling needed)
    if padded_pixels <= max_pixels and padded_w <= screen_w and padded_h <= screen_h then
        -- Use padding path: no quality loss
        use_padding = true
        target_w = padded_w
        target_h = padded_h
        actual_scale = 1.0
        pad_w = padded_w - crop_w
        pad_h = padded_h - crop_h
    else
        -- Use downscale path (existing logic)
        local src_pixels = crop_w * crop_h
        local scale_budget = 1.0

        if src_pixels > max_pixels then
            scale_budget = math.sqrt(max_pixels / src_pixels)
        end

        local final_scale = math.min(scale_budget, scale_screen)
        local ar = crop_w / crop_h

        local is_screen_limited = (scale_screen < scale_budget)
        local is_width_limited = (scale_w < scale_h)

        if is_screen_limited and is_width_limited then
            target_w = M.align_to_multiple(screen_w, block_align)
            target_h = M.align_to_multiple(target_w / ar, block_align)
            if target_h < block_align then target_h = block_align end
        elseif is_screen_limited and not is_width_limited then
            target_h = M.align_to_multiple(screen_h, block_align)
            target_w = M.align_to_multiple(target_h * ar, block_align)
        else
            local raw_target_h = math.max(block_align, crop_h * final_scale)
            target_h = M.align_to_multiple(raw_target_h, block_align)
            target_w = M.align_to_multiple(target_h * ar, block_align)
        end

        -- Safety Clamp
        if target_w > screen_w then
            target_w = M.align_to_multiple(screen_w, block_align)
            target_h = M.align_to_multiple(target_w / ar, block_align)
            if target_h < block_align then target_h = block_align end
        end

        if target_h > screen_h then
            target_h = M.align_to_multiple(screen_h, block_align)
            target_w = M.align_to_multiple(target_h * ar, block_align)
        end

        actual_scale = target_h / crop_h
    end

    -- Build result table
    return {
        target_w = target_w,
        target_h = target_h,
        vsr_path = use_vsr_path,
        scale = actual_scale,
        padding = {
            enabled = use_padding,
            orig_w = orig_w,
            orig_h = orig_h,
            pad_w = pad_w,
            pad_h = pad_h,
        },
        pipeline = {
            crop_w = crop_w,
            crop_h = crop_h,
            process_w = target_w,
            process_h = target_h,
            output_w = use_padding and orig_w or target_w,
            output_h = use_padding and orig_h or target_h,
        }
    }
end

return M
