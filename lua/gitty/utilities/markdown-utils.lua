-- HACK: This writes to file and isn't ideal, but it adds colours
-- local M = {}
-- function M.markdown_to_ansi(body)
--   -- Uses the 'glow' CLI to render markdown to ANSI escape codes for terminal formatting.
--   local tmpfile = "/dev/shm/nvim_glow_" .. tostring(math.random(100000, 999999)) .. ".md"
--   local f = io.open(tmpfile, "w")
--   if f then
--     f:write(body or "")
--     f:close()
--     local handle = io.popen(
--       "glow -s dark -w 80 " .. tmpfile .. " | bat --color=always --paging=always --language=markdown --style=plain"
--     )
--     if handle then
--       local result = handle:read("*a")
--       handle:close()
--       os.remove(tmpfile)
--       return result
--     else
--       os.remove(tmpfile)
--       return body or ""
--     end
--   else
--     return body or ""
--   end
-- end
--
-- function M.setup()
--   M.fzf_markdown_utils()
-- end
--
-- return M

local M = {}
local Job = require("plenary.job")

function M.markdown_to_ansi(body)
	-- Renders markdown using Glow and pipes the output to bat without using a file.
	local result = ""
	Job:new({
		command = "sh",
		args = {
			"-c",
			'echo "$1" | glow -s dark -w 80 | bat --color=always --paging=always --language=markdown --style=plain',
			"_",
			body,
		},
		on_stdout = function(_, data)
			result = result .. data .. "\n"
		end,
		on_stderr = function(_, err)
			vim.notify("Glow error: " .. err, vim.log.levels.ERROR)
		end,
	}):sync()
	return result
end

function M.setup()
	M.fzf_markdown_utils()
end

return M
