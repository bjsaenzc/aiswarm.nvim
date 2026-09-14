-- One session per project: chooses the v2 (legacy) engine or the v3 transport by board schema.
local M = { root = nil, engine = nil }

function M.engine_for(root)
  local schema = require("aiswarm.project").schema(root)
  if schema == "v3" then
    local ok, transport = pcall(require, "aiswarm.transport")
    if ok and transport.supported then return transport, "v3" end
  end
  return require("aiswarm.legacy.state"), schema == "v3" and "v3-fallback" or "v2"
end

function M.start(root)
  local engine, mode = M.engine_for(root)
  M.root, M.engine, M.mode = root, engine, mode
  local store = require("aiswarm.store")
  store.reset()
  require("aiswarm.view_state").reset()   -- selections are identities of the previous board
  store.board.root, store.board.schema = root, require("aiswarm.project").schema(root)
  if mode ~= "v3" then M.unsub = require("aiswarm.adapter").attach(store, engine) end
  M.transport = mode == "v3"
  engine.start(root)
  require("aiswarm.notify").claim_owner(root)
end

function M.stop()
  if M.unsub then pcall(M.unsub); M.unsub = nil end
  if M.engine then pcall(M.engine.stop) end
  M.engine, M.root, M.mode = nil, nil, nil
end

function M.state() return M.engine or require("aiswarm.legacy.state") end

return M
