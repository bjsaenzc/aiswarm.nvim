-- Clean headless worker bootstrap (SDD-069). Loads only bundled modules; never the user's config.
--   nvim --clean --headless --noplugin -u NONE -i NONE -n -l runtime/worker.lua --root R --attempt A
local plugin = vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)))
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. package.path
_G.AISWARM_PLUGIN_ROOT = plugin
local U = require("aiswarm.runtime.util")
local parsed = assert(U.parse_args(_G.arg or {}, {}))
local ok, err = xpcall(function() require("aiswarm.runtime.worker").main(parsed.opts) end, function(e)
  return (type(e) == "table" and (e.message or vim.inspect(e)) or tostring(e)) .. "\n" .. debug.traceback("", 2)
end)
if not ok then io.stderr:write("aiswarm worker: " .. tostring(err) .. "\n"); io.stderr:flush(); os.exit(1) end
os.exit(0)
