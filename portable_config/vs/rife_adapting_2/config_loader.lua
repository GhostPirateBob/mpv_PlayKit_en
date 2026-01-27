local ConfigLoader = {}

-- Required field definitions
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
    if align <= 0 or bit.band(align, align - 1) ~= 0 then
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
end

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

function ConfigLoader._parse_json(str)
    -- Convert JSON to Lua table syntax
    -- Use a simple state machine to track whether we're in a key or value

    local result = {}
    local i = 1
    local in_string = false
    local escape_next = false
    local capturing_key = false  -- true when we've identified this as a key
    local key_chars = {}  -- accumulate key characters

    while i <= #str do
        local char = str:sub(i, i)

        if escape_next then
            if in_string then
                table.insert(result, char)
            elseif capturing_key then
                table.insert(key_chars, char)
            end
            escape_next = false
            i = i + 1
        elseif char == '\\' then
            if in_string then
                table.insert(result, '\\')
            elseif capturing_key then
                table.insert(key_chars, '\\')
            end
            escape_next = true
            i = i + 1
        elseif char == '"' then
            if not in_string and not capturing_key then
                -- Start of a quoted string - peek ahead to see if it's a key
                local peek = i + 1
                local found_closing_quote = false
                local peek_pos = peek

                -- Find the matching closing quote (accounting for escapes)
                while peek_pos <= #str do
                    local c = str:sub(peek_pos, peek_pos)
                    if c == '\\' then
                        peek_pos = peek_pos + 2  -- Skip escaped char
                    elseif c == '"' then
                        found_closing_quote = true
                        break
                    else
                        peek_pos = peek_pos + 1
                    end
                end

                if found_closing_quote then
                    -- Check what's after the closing quote
                    local after_quote = peek_pos + 1
                    while after_quote <= #str and str:sub(after_quote, after_quote) == ' ' do
                        after_quote = after_quote + 1
                    end

                    if after_quote <= #str and str:sub(after_quote, after_quote) == ':' then
                        -- This is a key!
                        capturing_key = true
                        key_chars = {}
                        i = i + 1  -- Skip opening quote
                    else
                        -- This is a string value
                        in_string = true
                        table.insert(result, '"')
                        i = i + 1
                    end
                else
                    -- Unclosed string, treat as value
                    in_string = true
                    table.insert(result, '"')
                    i = i + 1
                end
            elseif capturing_key then
                -- End of key
                capturing_key = false
                i = i + 1  -- Skip closing quote

                -- Skip to and past the colon
                while i <= #str and (str:sub(i, i) == ' ' or str:sub(i, i) == ':') do
                    i = i + 1
                end

                -- Output ["key"]=
                table.insert(result, '["')
                for _, c in ipairs(key_chars) do
                    table.insert(result, c)
                end
                table.insert(result, '"]=')
            else
                -- End of string value
                table.insert(result, '"')
                in_string = false
                i = i + 1
            end
        else
            if capturing_key then
                table.insert(key_chars, char)
                i = i + 1
            elseif in_string then
                table.insert(result, char)
                i = i + 1
            else
                -- Replace keywords
                if char == 'f' and str:sub(i, i+4) == 'false' then
                    table.insert(result, 'false')
                    i = i + 5
                elseif char == 't' and str:sub(i, i+3) == 'true' then
                    table.insert(result, 'true')
                    i = i + 4
                elseif char == 'n' and str:sub(i, i+3) == 'null' then
                    table.insert(result, 'nil')
                    i = i + 4
                else
                    table.insert(result, char)
                    i = i + 1
                end
            end
        end
    end

    local lua_str = table.concat(result)

    local func, err = load("return " .. lua_str, "json", "t", {})
    if not func then
        error("[CONFIG] Invalid JSON: " .. err)
    end
    local success, result_val = pcall(func)
    if not success then
        error("[CONFIG] JSON parse error: " .. result_val)
    end
    return result_val
end

return ConfigLoader
