-- Benchmark template rendering performance
package.path = package.path .. ';../?.lua;./?.lua'
local TemplateLoader = require('rife_template_loader')
local script_dir = "C:/portable/mpv-lazy-new/mpv-lazy/portable_config/vs/rife_adapting_2"
local template = TemplateLoader:load(script_dir .. "/templates/rife.vpy.template")

local vars = {
  script_dir = script_dir,
  crop_l = 0, crop_t = 80, crop_w = 1920, crop_h = 1080,
  target_w = 1920, target_h = 1080,
  model = 4221, gpu_id = 0, gpu_t = 2,
  padding_enabled = true,
  padding_orig_w = 1920, padding_orig_h = 1080,
  multiplier = 2
}

local start = os.clock()
for i = 1, 1000 do
  template:render(vars)
end
local elapsed = os.clock() - start

print(string.format("Template Rendering Benchmark:"))
print(string.format("  1000 renders: %.3fs total", elapsed))
print(string.format("  %.3fms per render", (elapsed / 1000) * 1000))
print(string.format("  %d renders per second", math.floor(1000 / elapsed)))

if (elapsed / 1000) * 1000 < 1.0 then
  print("  ✅ PASS: <1ms per render")
else
  print("  ❌ FAIL: >=1ms per render")
end
