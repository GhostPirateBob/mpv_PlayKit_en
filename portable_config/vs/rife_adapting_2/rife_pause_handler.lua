--[[
    rife_pause_handler.lua - Handle pause/resume warmup for RIFE

    Problem: After long pause (60s+), TensorRT/GPU enters power-saving state.
    Solution: Seek forward/backward 1 frame to warmup pipeline before resume.

    User experience:
    - Unpause after <60s: instant resume (no warmup needed)
    - Unpause after ≥60s: ~1s delay, then smooth resume
]]

local PauseHandler = {}
PauseHandler.__index = PauseHandler

-- Config
local PAUSE_THRESHOLD = 60  -- seconds - only warmup after longer pauses
local WARMUP_SEEK = 1       -- frames - how far to seek for warmup

function PauseHandler:new(mp, state_manager)
    local handler = {
        mp = mp,
        state_manager = state_manager,
        pause_start_time = nil,
        warmup_in_progress = false,
        config = {
            threshold = PAUSE_THRESHOLD,
            seek_frames = WARMUP_SEEK
        }
    }
    setmetatable(handler, self)
    return handler
end

function PauseHandler:register_observers()
    self.mp.observe_property("pause", "bool", function(_, paused)
        self:on_pause_change(paused)
    end)
end

function PauseHandler:on_pause_change(paused)
    if paused then
        -- Video paused - record timestamp
        self.pause_start_time = os.time()
        self.mp.msg.debug("[rife_pause_handler] Paused at " .. self.pause_start_time)
    else
        -- Video unpaused - check if warmup needed
        self:handle_unpause()
    end
end

function PauseHandler:handle_unpause()
    if not self.pause_start_time then
        return  -- No pause recorded (startup case)
    end

    local pause_duration = os.time() - self.pause_start_time
    self.pause_start_time = nil

    self.mp.msg.debug("[rife_pause_handler] Unpaused after " .. pause_duration .. "s")

    -- Only warmup after long pauses
    if pause_duration >= self.config.threshold then
        self:warmup_gpu()
    end
end

function PauseHandler:warmup_gpu()
    -- Skip if RIFE not active (check via state manager)
    if not self.state_manager or not self.state_manager:get_rife_active() then
        self.mp.msg.debug("[rife_pause_handler] RIFE not active, skipping warmup")
        return
    end

    self.warmup_in_progress = true
    self.mp.msg.debug("[rife_pause_handler] Starting GPU warmup (seek ±" .. self.config.seek_frames .. " frame)")
    self.mp.osd_message("[RIFE] Warming up...", 2)

    local current_pos = self.mp.get_property_number("time-pos")

    -- Seek forward then back to force VapourSynth re-render
    self.mp.commandv("seek", self.config.seek_frames, "relative+keyframes")

    -- After seek completes, return to original position
    self.mp.add_timeout(0.5, function()
        if current_pos then
            self.mp.commandv("seek", current_pos, "absolute")
        end
        self.warmup_in_progress = false
        self.mp.msg.debug("[rife_pause_handler] Warmup complete")
    end)
end

return PauseHandler
