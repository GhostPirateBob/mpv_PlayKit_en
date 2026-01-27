local lu = require('luaunit')
local TemplateLoader = require('rife_template_loader')

TestTemplateLoaderLoad = {}

function TestTemplateLoaderLoad:test_load_existing_template()
  local template = TemplateLoader:load("fixtures/test_template.vpy.template")

  lu.assertNotNil(template)
  lu.assertEquals(type(template.render), "function")
end

function TestTemplateLoaderLoad:test_load_missing_file_errors()
  local success, err = pcall(function()
    TemplateLoader:load("nonexistent.vpy.template")
  end)

  lu.assertFalse(success)
  lu.assertStrContains(err, "Template file not found")
end

TestTemplateLoaderRender = {}

function TestTemplateLoaderRender:test_render_simple_variables()
  local template = TemplateLoader:load("fixtures/test_template.vpy.template")
  local vars = {
    script_dir = "C:/test/path"
  }

  local result = template:render(vars)

  lu.assertStrContains(result, 'sys.path.insert(0, r"C:/test/path")')
  lu.assertNotStrContains(result, "{{")  -- No unreplaced placeholders
end

function TestTemplateLoaderRender:test_render_missing_variable_errors()
  local template = TemplateLoader:load("fixtures/test_template.vpy.template")
  local vars = {}  -- Missing script_dir

  local success, err = pcall(function()
    template:render(vars)
  end)

  lu.assertFalse(success)
  lu.assertStrContains(err, "Missing template variable")
end

function TestTemplateLoaderRender:test_render_boolean_values()
  local template = TemplateLoader:load("fixtures/bool_template.vpy.template")

  local result = template:render({enabled = true})

  lu.assertStrContains(result, "enabled=true")
end
