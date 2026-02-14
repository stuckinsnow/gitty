--- AI helper: shells out to opencode with copilot 4.1

local M = {}

local model = "github-copilot/gpt-4.1"
local active = nil

local function has_noice()
  return pcall(require, "noice.message")
end

local function update_loop()
  if not active or active.stopped then return end
  local Format = require("noice.text.format")
  local Manager = require("noice.message.manager")
  Manager.add(Format.format(active.message, "lsp_progress"))
  vim.defer_fn(update_loop, 200)
end

local function spinner_stop(text)
  if not active or not has_noice() then return end
  active.stopped = true
  active.message.opts.progress.message = text or "Done"
  local Format = require("noice.text.format")
  local Manager = require("noice.message.manager")
  local Router = require("noice.message.router")
  Manager.add(Format.format(active.message, "lsp_progress"))
  Router.update()
  local msg = active.message
  active = nil
  vim.defer_fn(function() Manager.remove(msg) end, 2000)
end

local function spinner_start(text)
  if not has_noice() then return end
  spinner_stop()
  local Message = require("noice.message")
  local msg = Message("lsp", "progress")
  msg.opts.progress = {
    client_id = "gitty_" .. vim.uv.hrtime(),
    client = "gitty",
    id = vim.uv.hrtime(),
    message = text or "AI processing...",
  }
  active = { message = msg, stopped = false }
  update_loop()
end

--- Run a prompt through opencode and return the result async
--- @param prompt string
--- @param callback fun(result: string?, err: string?)
function M.run(prompt, callback)
  spinner_start("AI processing...")

  vim.system(
    { "opencode", "run", "--agent", "build", "-m", model, prompt },
    { text = true, cwd = vim.fn.getcwd() },
    vim.schedule_wrap(function(obj)
      spinner_stop("AI complete")
      if obj.code ~= 0 then
        callback(nil, obj.stderr or "opencode failed")
      else
        callback(vim.trim(obj.stdout or ""), nil)
      end
    end)
  )
end

return M
