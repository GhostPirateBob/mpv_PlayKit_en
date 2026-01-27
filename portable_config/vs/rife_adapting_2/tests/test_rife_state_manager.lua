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

TestStateManagerValidation = {}

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
