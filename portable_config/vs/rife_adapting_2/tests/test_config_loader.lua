local lu = require("luaunit")
-- Add parent directory to package.path so we can require config_loader
package.path = package.path .. ";../?.lua"
local ConfigLoader = require("config_loader")

function test_module_exists()
    lu.assertNotNil(ConfigLoader)
    lu.assertIsFunction(ConfigLoader.load)
end

function test_load_returns_table()
    -- load() now throws error on missing file
    local ok, err = pcall(function()
        ConfigLoader.load("fake_path")
    end)
    lu.assertFalse(ok)
    lu.assertStrContains(err, "File not found")
end

function test_read_valid_json()
    -- Create temp valid config
    local test_dir = "test_config_temp"
    os.execute("mkdir " .. test_dir .. " 2>nul")

    local f = io.open(test_dir .. "/config.json", "w")
    f:write('{"gpu":{"device_id":0,"threads":2,"max_pixels_vsr_on":2.0,"max_pixels_vsr_off":3.0},"rife":{"model_number":4221,"model_dir":"rife_v2","models":{},"ensemble":false,"implementation":2},"thresholds":{"fps_vsr_only":50,"fps_x3_mode":30,"x3_pixel_ratio":0.5,"vsr_min_mult":1.3},"processing":{"block_align":32,"min_dimension":32,"output_format":"YUV420P10","working_format":"RGBH"},"tensorrt":{"int8":false,"fp16":true,"workspace":256,"use_cuda_graph":true,"use_cublas":true,"use_cudnn":true,"static_shape":true},"features":{"enable_vsr":true,"enable_x3_adaptive":true}}')
    f:close()

    local config = ConfigLoader.load(test_dir)
    lu.assertNotNil(config)
    lu.assertEquals(config.gpu.device_id, 0)

    -- Cleanup
    os.execute("del /Q " .. test_dir .. "\\config.json")
    os.execute("rmdir " .. test_dir)
end

function test_missing_required_section()
    local test_dir = "test_config_temp"
    os.execute("mkdir " .. test_dir .. " 2>nul")

    local f = io.open(test_dir .. "/config.json", "w")
    f:write('{"rife":{"model_number":4221,"model_dir":"rife_v2","models":{},"ensemble":false,"implementation":2},"thresholds":{"fps_vsr_only":50,"fps_x3_mode":30,"x3_pixel_ratio":0.5,"vsr_min_mult":1.3},"processing":{"block_align":32,"min_dimension":32,"output_format":"YUV420P10","working_format":"RGBH"},"tensorrt":{"int8":false,"fp16":true,"workspace":256,"use_cuda_graph":true,"use_cublas":true,"use_cudnn":true,"static_shape":true},"features":{"enable_vsr":true,"enable_x3_adaptive":true}}')  -- Missing gpu section
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
    f:write('{"gpu":{"threads":2},"rife":{"model_number":4221,"model_dir":"rife_v2","models":{},"ensemble":false,"implementation":2},"thresholds":{"fps_vsr_only":50,"fps_x3_mode":30,"x3_pixel_ratio":0.5,"vsr_min_mult":1.3},"processing":{"block_align":32,"min_dimension":32,"output_format":"YUV420P10","working_format":"RGBH"},"tensorrt":{"int8":false,"fp16":true,"workspace":256,"use_cuda_graph":true,"use_cublas":true,"use_cudnn":true,"static_shape":true},"features":{"enable_vsr":true,"enable_x3_adaptive":true}}')  -- Missing device_id
    f:close()

    local ok, err = pcall(function()
        ConfigLoader.load(test_dir)
    end)
    lu.assertFalse(ok)
    lu.assertStrContains(err, "device_id")

    os.execute("del /Q " .. test_dir .. "\\config.json")
    os.execute("rmdir " .. test_dir)
end

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

function test_invalid_device_id_type()
    local test_dir = "test_config_temp"
    os.execute("mkdir " .. test_dir .. " 2>nul")

    local f = io.open(test_dir .. "/config.json", "w")
    f:write('{"gpu":{"device_id":"0","threads":2,"max_pixels_vsr_on":2.0,"max_pixels_vsr_off":3.0},"rife":{"model_number":4221,"model_dir":"rife_v2","models":{},"ensemble":false,"implementation":2},"thresholds":{"fps_vsr_only":50,"fps_x3_mode":30,"x3_pixel_ratio":0.5,"vsr_min_mult":1.3},"processing":{"block_align":32,"min_dimension":32,"output_format":"YUV420P10","working_format":"RGBH"},"tensorrt":{"int8":false,"fp16":true,"workspace":256,"use_cuda_graph":true,"use_cublas":true,"use_cudnn":true,"static_shape":true},"features":{"enable_vsr":true,"enable_x3_adaptive":true}}')
    f:close()

    local ok, err = pcall(function()
        ConfigLoader.load(test_dir)
    end)
    lu.assertFalse(ok)
    lu.assertStrContains(err, "must be a number")

    os.execute("del /Q " .. test_dir .. "\\config.json")
    os.execute("rmdir " .. test_dir)
end

function test_invalid_ensemble_type()
    local test_dir = "test_config_temp"
    os.execute("mkdir " .. test_dir .. " 2>nul")

    local f = io.open(test_dir .. "/config.json", "w")
    f:write('{"gpu":{"device_id":0,"threads":2,"max_pixels_vsr_on":2.0,"max_pixels_vsr_off":3.0},"rife":{"model_number":4221,"model_dir":"rife_v2","models":{},"ensemble":"false","implementation":2},"thresholds":{"fps_vsr_only":50,"fps_x3_mode":30,"x3_pixel_ratio":0.5,"vsr_min_mult":1.3},"processing":{"block_align":32,"min_dimension":32,"output_format":"YUV420P10","working_format":"RGBH"},"tensorrt":{"int8":false,"fp16":true,"workspace":256,"use_cuda_graph":true,"use_cublas":true,"use_cudnn":true,"static_shape":true},"features":{"enable_vsr":true,"enable_x3_adaptive":true}}')
    f:close()

    local ok, err = pcall(function()
        ConfigLoader.load(test_dir)
    end)
    lu.assertFalse(ok)
    lu.assertStrContains(err, "must be a boolean")

    os.execute("del /Q " .. test_dir .. "\\config.json")
    os.execute("rmdir " .. test_dir)
end

function test_invalid_x3_pixel_ratio_range()
    local test_dir = "test_config_temp"
    os.execute("mkdir " .. test_dir .. " 2>nul")

    local f = io.open(test_dir .. "/config.json", "w")
    f:write('{"gpu":{"device_id":0,"threads":2,"max_pixels_vsr_on":2.0,"max_pixels_vsr_off":3.0},"rife":{"model_number":4221,"model_dir":"rife_v2","models":{},"ensemble":false,"implementation":2},"thresholds":{"fps_vsr_only":50,"fps_x3_mode":30,"x3_pixel_ratio":1.5,"vsr_min_mult":1.3},"processing":{"block_align":32,"min_dimension":32,"output_format":"YUV420P10","working_format":"RGBH"},"tensorrt":{"int8":false,"fp16":true,"workspace":256,"use_cuda_graph":true,"use_cublas":true,"use_cudnn":true,"static_shape":true},"features":{"enable_vsr":true,"enable_x3_adaptive":true}}')
    f:close()

    local ok, err = pcall(function()
        ConfigLoader.load(test_dir)
    end)
    lu.assertFalse(ok)
    lu.assertStrContains(err, "0-1")

    os.execute("del /Q " .. test_dir .. "\\config.json")
    os.execute("rmdir " .. test_dir)
end

os.exit(lu.LuaUnit.run())
