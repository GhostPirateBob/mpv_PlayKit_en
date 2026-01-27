local lu = require('luaunit')
local core = require('rife_core')

-- Helper to create minimal config for tests
local function make_test_opts(enable_vsr, max_on, max_off, min_mult)
  return {
    features = { enable_vsr = enable_vsr },
    gpu = { max_pixels_vsr_on = max_on, max_pixels_vsr_off = max_off },
    thresholds = { vsr_min_mult = min_mult },
    processing = { block_align = 32 }
  }
end

TestTempDir = {}

function TestTempDir:test_uses_TEMP_first()
  local result = core.get_temp_dir_path({TEMP="C:\\Windows\\Temp", TMP="C:\\tmp", TMPDIR="/tmp"})
  lu.assertEquals(result, "C:\\Windows\\Temp")
end

function TestTempDir:test_uses_TMP_when_TEMP_missing()
  local result = core.get_temp_dir_path({TMP="C:\\tmp", TMPDIR="/tmp"})
  lu.assertEquals(result, "C:\\tmp")
end

function TestTempDir:test_uses_TMPDIR_when_TEMP_TMP_missing()
  local result = core.get_temp_dir_path({TMPDIR="/tmp"})
  lu.assertEquals(result, "/tmp")
end

function TestTempDir:test_defaults_to_tmp_when_all_missing()
  local result = core.get_temp_dir_path({})
  lu.assertEquals(result, "/tmp")
end

TestAlignment = {}

function TestAlignment:test_already_aligned()
  lu.assertEquals(core.align_to_multiple(1920, 32), 1920)
  lu.assertEquals(core.align_to_multiple(1024, 32), 1024)
end

function TestAlignment:test_align_down()
  lu.assertEquals(core.align_to_multiple(1919, 32), 1888)
  lu.assertEquals(core.align_to_multiple(533, 32), 512)
  lu.assertEquals(core.align_to_multiple(1281, 32), 1280)
end

function TestAlignment:test_small_values()
  lu.assertEquals(core.align_to_multiple(31, 32), 0)
  lu.assertEquals(core.align_to_multiple(0, 32), 0)
end

function TestAlignment:test_different_multiples()
  lu.assertEquals(core.align_to_multiple(100, 16), 96)
  lu.assertEquals(core.align_to_multiple(100, 10), 100)
end

TestAlignmentCeil = {}

function TestAlignmentCeil:test_already_aligned()
  lu.assertEquals(core.align_to_multiple_ceil(1920, 32), 1920)
  lu.assertEquals(core.align_to_multiple_ceil(1024, 32), 1024)
end

function TestAlignmentCeil:test_align_up()
  lu.assertEquals(core.align_to_multiple_ceil(1080, 32), 1088)
  lu.assertEquals(core.align_to_multiple_ceil(720, 32), 736)
  lu.assertEquals(core.align_to_multiple_ceil(1921, 32), 1952)
end

function TestAlignmentCeil:test_small_values()
  lu.assertEquals(core.align_to_multiple_ceil(1, 32), 32)
  lu.assertEquals(core.align_to_multiple_ceil(31, 32), 32)
  lu.assertEquals(core.align_to_multiple_ceil(0, 32), 0)
end

TestScaleToFit = {}

function TestScaleToFit:test_landscape_constrained_by_width()
  local scale = core.calculate_scale_to_fit(3840, 1600, 2560, 1440)
  lu.assertAlmostEquals(scale, 2560/3840, 0.001)
end

function TestScaleToFit:test_landscape_constrained_by_height()
  local scale = core.calculate_scale_to_fit(1920, 1200, 2560, 1440)
  lu.assertEquals(scale, 1.0)  -- No upscaling
end

function TestScaleToFit:test_portrait_video()
  local scale = core.calculate_scale_to_fit(1080, 1920, 2560, 1440)
  lu.assertAlmostEquals(scale, 1440/1920, 0.001)
end

function TestScaleToFit:test_source_smaller_than_screen()
  local scale = core.calculate_scale_to_fit(1280, 720, 2560, 1440)
  lu.assertEquals(scale, 1.0)  -- No upscaling
end

function TestScaleToFit:test_exact_fit()
  local scale = core.calculate_scale_to_fit(2560, 1440, 2560, 1440)
  lu.assertEquals(scale, 1.0)
end

TestCalculateTargets = {}

function TestCalculateTargets:test_vsr_disabled_uses_vsr_off_budget()
  local opts = make_test_opts(false, 2.0, 2.9, 1.5)
  local result = core.calculate_targets(1920, 800, 2560, 1440, opts)
  local tw, th, vsr, scale = result.target_w, result.target_h, result.vsr_path, result.scale

  lu.assertFalse(vsr)
  lu.assertTrue(tw > 0 and th > 0)
  -- Should use 2.9MP budget
  local pixels = tw * th
  lu.assertTrue(pixels <= 2900000)
end

function TestCalculateTargets:test_source_larger_than_screen_clamps_to_screen()
  local opts = make_test_opts(true, 2.0, 2.9, 1.5)
  -- 4K source on 1440p screen - must never exceed screen dimensions
  local result = core.calculate_targets(3840, 1600, 2560, 1440, opts)
  local tw, th, vsr, scale = result.target_w, result.target_h, result.vsr_path, result.scale

  lu.assertTrue(tw <= 2560 and th <= 1440)  -- Must fit screen
  -- VSR can activate if downscaled result allows meaningful upscale (ratio >= 1.5)
end

function TestCalculateTargets:test_width_limited_clamps_to_screen_width()
  local opts = make_test_opts(false, 2.0, 3.0, 1.5)
  -- Ultrawide 4K on 2560x1440 screen - width is limiting factor
  -- Budget (3.0 MP) allows, but screen limits scale to ~0.667
  local result = core.calculate_targets(3840, 1608, 2560, 1440, opts)
  local tw, th, vsr, scale = result.target_w, result.target_h, result.vsr_path, result.scale

  lu.assertTrue(tw <= 2560)  -- Must not exceed screen width
  lu.assertTrue(th <= 1440)  -- Height must also fit
  lu.assertEquals(tw % 32, 0) -- Must be aligned
end

function TestCalculateTargets:test_height_limited_clamps_to_screen_height()
  local opts = make_test_opts(false, 2.0, 3.0, 1.5)
  -- Tall content on wide screen - height is limiting factor
  local result = core.calculate_targets(1920, 2160, 2560, 1440, opts)
  local tw, th, vsr, scale = result.target_w, result.target_h, result.vsr_path, result.scale

  lu.assertTrue(tw <= 2560)
  lu.assertEquals(th, 1440)  -- Must clamp to screen height
end

function TestCalculateTargets:test_budget_used_when_smaller_than_screen()
  local opts = make_test_opts(false, 2.0, 1.0, 1.5)
  -- 4K source with 1.0 MP budget - budget limits before screen does
  local result = core.calculate_targets(3840, 2160, 2560, 1440, opts)
  local tw, th, vsr, scale = result.target_w, result.target_h, result.vsr_path, result.scale

  local pixels = tw * th
  lu.assertTrue(pixels <= 1100000)  -- ~1 MP with alignment tolerance
  lu.assertTrue(tw < 2560)  -- Budget limited, not screen limited
end

function TestCalculateTargets:test_vsr_insufficient_ratio_uses_standard_path()
  local opts = make_test_opts(true, 2.0, 2.9, 1.5)
  -- Small crop where VSR ratio would be < 1.5
  local result = core.calculate_targets(1920, 1000, 2560, 1440, opts)
  local tw, th, vsr, scale = result.target_w, result.target_h, result.vsr_path, result.scale

  lu.assertFalse(vsr)  -- Ratio insufficient
  local pixels = tw * th
  lu.assertTrue(pixels <= 2900000)  -- Uses vsr_off budget
end

function TestCalculateTargets:test_vsr_path_selected_when_ratio_sufficient()
  local opts = make_test_opts(true, 2.0, 2.9, 1.5)
  -- 1600x800 crop on 2560x1440 screen - BOTH ratios must be >= 1.5
  -- ratio_w = 2560/1600 = 1.6, ratio_h = 1440/800 = 1.8, min = 1.6 >= 1.5
  local result = core.calculate_targets(1600, 800, 2560, 1440, opts)
  local tw, th, vsr, scale = result.target_w, result.target_h, result.vsr_path, result.scale

  lu.assertTrue(vsr)  -- Should use VSR path
  local pixels = tw * th
  lu.assertTrue(pixels <= 2000000)  -- Uses vsr_on budget
end

function TestCalculateTargets:test_vsr_uses_min_of_both_ratios()
  local opts = make_test_opts(true, 2.0, 2.9, 1.5)
  -- Wide content: height ratio good (1.8x) but width ratio bad (1.33x)
  -- 1920x800 on 2560x1440: ratio_w=1.33, ratio_h=1.8, min=1.33 < 1.5
  local result = core.calculate_targets(1920, 800, 2560, 1440, opts)
  local tw, th, vsr, scale = result.target_w, result.target_h, result.vsr_path, result.scale

  lu.assertFalse(vsr)  -- Width ratio insufficient, should NOT use VSR path
  local pixels = tw * th
  lu.assertTrue(pixels <= 2900000)  -- Uses vsr_off budget instead
end

function TestCalculateTargets:test_aspect_ratio_preserved()
  local opts = make_test_opts(false, 2.0, 2.9, 1.5)

  local crop_w, crop_h = 1920, 800
  local result = core.calculate_targets(crop_w, crop_h, 2560, 1440, opts)
  local tw, th = result.target_w, result.target_h

  local source_ar = crop_w / crop_h
  local target_ar = tw / th

  -- AR should be preserved within alignment tolerance
  lu.assertAlmostEquals(source_ar, target_ar, 0.05)
end

function TestCalculateTargets:test_dimensions_aligned_to_32px()
  local opts = make_test_opts(false, 2.0, 2.9, 1.5)

  local result = core.calculate_targets(1920, 800, 2560, 1440, opts)
  local tw, th = result.target_w, result.target_h

  lu.assertEquals(tw % 32, 0)
  lu.assertEquals(th % 32, 0)
end

function TestCalculateTargets:test_pixel_budget_enforced()
  local opts = make_test_opts(false, 2.0, 2.9, 1.5)

  -- Large source that needs downscaling
  local result = core.calculate_targets(3840, 2160, 2560, 1440, opts)
  local tw, th = result.target_w, result.target_h
  local pixels = tw * th

  lu.assertTrue(pixels <= 2900000)  -- Within budget
end

function TestCalculateTargets:test_no_upscaling_small_source()
  local opts = make_test_opts(false, 2.0, 2.9, 1.5)

  -- Small source under budget
  local crop_w, crop_h = 1280, 720
  local result = core.calculate_targets(crop_w, crop_h, 2560, 1440, opts)
  local tw, th, vsr, scale = result.target_w, result.target_h, result.vsr_path, result.scale

  -- With padding, dimensions may round up to align, but scale should remain 1.0
  -- 1280x720 -> 1280x736 (720 aligns up to 736)
  lu.assertEquals(tw, 1280)  -- Already aligned
  lu.assertEquals(th, 736)   -- Padded (720 -> 736)
  lu.assertEquals(scale, 1.0) -- No actual scaling, just padding
end

function TestCalculateTargets:test_extreme_aspect_ratio()
  local opts = make_test_opts(false, 2.0, 2.9, 1.5)

  -- Ultra-wide 21:9
  local result = core.calculate_targets(2560, 1080, 2560, 1440, opts)
  local tw, th = result.target_w, result.target_h

  lu.assertTrue(tw > 0 and th > 0)
  lu.assertEquals(tw % 32, 0)
  lu.assertEquals(th % 32, 0)
end

-- ============================================================================
-- TestAspectRatios - Real-world aspect ratio scenarios
-- ============================================================================

TestAspectRatios = {}

-- Standard settings for these tests
local std_opts = make_test_opts(true, 8.0, 8.0, 1.0)

TestBoundaryConditions = {}

function TestBoundaryConditions:test_alignment_does_not_exceed_screen()
  -- Input perfectly matches screen
  local result = core.calculate_targets(2560, 1440, 2560, 1440, std_opts)
  local tw, th = result.target_w, result.target_h
  lu.assertTrue(tw <= 2560)
  lu.assertTrue(th <= 1440)

  -- Input slightly larger (e.g. overscan crop)
  -- 2561 width should be clamped to 2560 (or aligned down to 2560)
  local result2 = core.calculate_targets(2561, 1441, 2560, 1440, std_opts)
  local tw2, th2 = result2.target_w, result2.target_h
  lu.assertTrue(tw2 <= 2560)
  lu.assertTrue(th2 <= 1440)
end

function TestBoundaryConditions:test_width_limited_downscale_maximizes_width()
  -- REGRESSION TEST: Real scenario from mpv log
  -- Source: 3840x1608 (ultrawide 4K after crop)
  -- Screen: 2560x1440
  -- Budget: 3.0 MP (allows ~2700x1130 but screen limits first)
  --
  -- Width is limiting: scale_w = 2560/3840 = 0.667
  -- Height allows more: scale_h = 1440/1608 = 0.895
  --
  -- BUG: Old code applies 0.667 scale to HEIGHT first:
  --   target_h = align(1608 * 0.667) = align(1072) = 1056
  --   target_w = align(1056 * 2.388) = align(2522) = 2496  <-- WRONG!
  --
  -- EXPECTED: When width-limited, set width to screen first:
  --   target_w = align(2560) = 2560
  --   target_h = align(2560 / 2.388) = align(1072) = 1056

  local opts = make_test_opts(false, 2.0, 3.0, 1.5)

  local result = core.calculate_targets(3840, 1608, 2560, 1440, opts)
  local tw, th, vsr, scale = result.target_w, result.target_h, result.vsr_path, result.scale

  -- Width MUST reach screen width (aligned) when width is the limiting factor
  lu.assertEquals(tw, 2560, "Width-limited downscale should maximize to screen width")
  lu.assertEquals(th, 1056)  -- Height derived from width, maintaining AR
  lu.assertTrue(tw * th <= 3000000)  -- Must still fit budget
end


TestPaddingDecision = {}

function TestPaddingDecision:test_padding_enabled_when_under_budget()
  -- 1920x1080 padded to 1920x1088 = 2,088,960 pixels (~2.09 MP)
  -- Budget: 2.5 MP - should use padding
  local opts = make_test_opts(false, 2.0, 2.5, 1.5)
  local result = core.calculate_targets(1920, 1080, 2560, 1440, opts)
  local tw, th, vsr, scale = result.target_w, result.target_h, result.vsr_path, result.scale

  lu.assertTrue(result.padding.enabled)
  lu.assertEquals(result.scale, 1.0)
  lu.assertEquals(result.target_w, 1920)
  lu.assertEquals(result.target_h, 1088)
  lu.assertEquals(result.padding.orig_w, 1920)
  lu.assertEquals(result.padding.orig_h, 1080)
  lu.assertEquals(result.padding.pad_w, 0)
  lu.assertEquals(result.padding.pad_h, 8)
end

function TestPaddingDecision:test_padding_disabled_when_over_budget()
  -- 1920x1080 padded to 1920x1088 = 2,088,960 pixels (~2.09 MP)
  -- Budget: 2.0 MP - should downscale instead
  local opts = make_test_opts(false, 2.0, 2.0, 1.5)
  local result = core.calculate_targets(1920, 1080, 2560, 1440, opts)
  local tw, th, vsr, scale = result.target_w, result.target_h, result.vsr_path, result.scale

  lu.assertFalse(result.padding.enabled)
  lu.assertTrue(result.scale < 1.0)
  -- Should downscale
  lu.assertTrue(result.target_w * result.target_h <= 2000000)
end

function TestPaddingDecision:test_padding_both_dimensions()
  -- 1366x768: ceil to 1376x768 (768 already aligned)
  -- 1376 * 768 = 1,056,768 pixels (~1.06 MP) - well under any budget
  local opts = make_test_opts(false, 2.0, 2.5, 1.5)
  local result = core.calculate_targets(1366, 768, 2560, 1440, opts)
  local tw, th, vsr, scale = result.target_w, result.target_h, result.vsr_path, result.scale

  lu.assertTrue(result.padding.enabled)
  lu.assertEquals(result.target_w, 1376)
  lu.assertEquals(result.target_h, 768)
  lu.assertEquals(result.padding.pad_w, 10)
  lu.assertEquals(result.padding.pad_h, 0)
end

TestPipelineData = {}

function TestPipelineData:test_pipeline_with_padding()
  local opts = make_test_opts(false, 2.0, 2.5, 1.5)
  local result = core.calculate_targets(1920, 1080, 2560, 1440, opts)

  lu.assertEquals(result.pipeline.crop_w, 1920)
  lu.assertEquals(result.pipeline.crop_h, 1080)
  lu.assertEquals(result.pipeline.process_w, 1920)  -- padded width (already aligned)
  lu.assertEquals(result.pipeline.process_h, 1088) -- padded height
  lu.assertEquals(result.pipeline.output_w, 1920)  -- original width
  lu.assertEquals(result.pipeline.output_h, 1080)  -- original height
end

function TestPipelineData:test_pipeline_with_downscale()
  local opts = make_test_opts(false, 2.0, 1.5, 1.5)
  local result = core.calculate_targets(1920, 1080, 2560, 1440, opts)

  lu.assertEquals(result.pipeline.crop_w, 1920)
  lu.assertEquals(result.pipeline.crop_h, 1080)
  -- Process and output same when downscaling (no crop-back needed)
  lu.assertEquals(result.pipeline.process_w, result.pipeline.output_w)
  lu.assertEquals(result.pipeline.process_h, result.pipeline.output_h)
  lu.assertTrue(result.pipeline.output_w < 1920)
  lu.assertTrue(result.pipeline.output_h < 1080)
end
