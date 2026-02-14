--- AI helper: shells out to opencode with copilot 4.1

local M = {}

local model = "github-copilot/gpt-4.1"
local frames = { "⣷", "⣯", "⣟", "⡿", "⢿", "⣻", "⣽", "⣾" }

--- Run a prompt through opencode and return the result async
--- @param prompt string
--- @param callback fun(result: string?, err: string?)
function M.run(prompt, callback)
  local frame_idx = 1
  local timer = vim.uv.new_timer()
  timer:start(0, 120, vim.schedule_wrap(function()
    frame_idx = frame_idx % #frames + 1
    vim.notify(frames[frame_idx] .. " AI processing...", vim.log.levels.INFO, { replace = "gitty_ai_spinner" })
  end))

  vim.system(
    { "opencode", "run", "--agent", "build", "-m", model, prompt },
    { text = true, cwd = vim.fn.getcwd() },
    vim.schedule_wrap(function(obj)
      timer:stop()
      timer:close()
      vim.notify("", vim.log.levels.INFO, { replace = "gitty_ai_spinner", hide = true })
      if obj.code ~= 0 then
        callback(nil, obj.stderr or "opencode failed")
      else
        callback(vim.trim(obj.stdout or ""), nil)
      end
    end)
  )
end

return M
