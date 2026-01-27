-- rife_template_loader.lua - Template loading and rendering

local TemplateLoader = {}
TemplateLoader.__index = TemplateLoader

-- Convert Lua boolean to Python boolean string
local function to_python_bool(value)
  if value then
    return "True"
  else
    return "False"
  end
end

-- Template object (returned by load)
local Template = {}
Template.__index = Template

-- Load and parse template file
-- Returns: Template object with render() method
function TemplateLoader:load(template_path)
  -- Check file exists
  local f = io.open(template_path, "r")
  if not f then
    error("Template file not found: " .. template_path)
  end

  local content = f:read("*all")
  f:close()

  -- Create template object
  local template = {
    _content = content,
    _path = template_path
  }

  return setmetatable(template, Template)
end

-- Render template with variables
-- vars: table with template variable values
-- config: configuration table with nested sections (optional)
-- Returns: rendered string (valid Python code)
function Template:render(vars, config)
  vars = vars or {}

  -- Merge all config values into vars
  local all_vars = {}
  for k, v in pairs(vars) do
    all_vars[k] = v
  end

  if config then
    -- Flatten config into template variables
    all_vars.model_number = config.rife.model_number
    all_vars.gpu_device_id = config.gpu.device_id
    all_vars.gpu_threads = config.gpu.threads
    all_vars.model_dir = config.rife.model_dir

    -- Convert models table to JSON-like string for Python
    local models_str = "{"
    local first = true
    for k, v in pairs(config.rife.models) do
      if not first then models_str = models_str .. ", " end
      models_str = models_str .. k .. ": '" .. v .. "'"
      first = false
    end
    models_str = models_str .. "}"
    all_vars.model_map = models_str

    all_vars.ensemble = to_python_bool(config.rife.ensemble)
    all_vars.implementation = config.rife.implementation

    -- TensorRT config
    all_vars.trt_int8 = to_python_bool(config.tensorrt.int8)
    all_vars.trt_fp16 = to_python_bool(config.tensorrt.fp16)
    all_vars.trt_workspace = config.tensorrt.workspace
    all_vars.trt_cuda_graph = to_python_bool(config.tensorrt.use_cuda_graph)
    all_vars.trt_cublas = to_python_bool(config.tensorrt.use_cublas)
    all_vars.trt_cudnn = to_python_bool(config.tensorrt.use_cudnn)
    all_vars.trt_static_shape = to_python_bool(config.tensorrt.static_shape)
  end

  local result = self._content

  -- Helper function to escape magic characters in Lua patterns
  local function escape_pattern(text)
    return text:gsub("([^%w])", "%%%1")
  end

  -- Replace {{variable}} placeholders
  for key, value in pairs(all_vars) do
    local placeholder = "{{" .. key .. "}}"
    local escaped = escape_pattern(placeholder)
    local replacement = tostring(value)
    result = result:gsub(escaped, replacement)
  end

  -- Check for unreplaced placeholders
  -- Note: { is magic in Lua but } is not, so we escape the {
  local unreplaced = result:match("{{([^}]+)}}")
  if unreplaced then
    error("Missing template variable: " .. unreplaced)
  end

  return result
end

-- Validate template syntax (basic check)
function TemplateLoader:validate(template_content)
  -- Check for balanced braces
  local open_count = 0
  for i = 1, #template_content do
    local char = template_content:sub(i, i)
    if char == "{" then
      open_count = open_count + 1
    elseif char == "}" then
      open_count = open_count - 1
    end
  end

  if open_count ~= 0 then
    return false, "Unbalanced braces in template"
  end

  return true, nil
end

return TemplateLoader
