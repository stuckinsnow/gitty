--- AI helper: runs prompts using the provider & model selected in lg.nvim.

local M = {}

--- Run a prompt via lg.nvim's active provider and selected model.
--- @param prompt string
--- @param callback fun(result: string?, err: string?)
function M.run(prompt, callback)
	local ok, subagent = pcall(require, "lg.session.subagent")
	if not ok or not subagent._ensure_acp then
		callback(nil, "lg.nvim is not loaded or initialized")
		return
	end

	subagent.run({
		prompt = { { type = "text", text = prompt } },
		label = "Gitty AI",
		on_text = function() end,
		finish_subagent = false,
		fire_autocmds = false,
		track_tool_errors = false,
		on_done = function(text, tool_error)
			local trimmed = vim.trim(text or "")
			if trimmed == "" and tool_error then
				callback(nil, tool_error)
			else
				callback(trimmed, nil)
			end
		end,
		on_fail = function()
			callback(nil, "lg AI request failed")
		end,
	})
end

return M
