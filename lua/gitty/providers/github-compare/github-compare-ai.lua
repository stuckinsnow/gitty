local M = {}

local ai = require("gitty.utilities.ai")

function M.fzf_github_analyse_ai()
	local fzf = require("fzf-lua")
	local picker_utils = require("gitty.providers.github-compare.picker-utils")

	local git_log_cmd = picker_utils.create_themed_git_log_cmd(nil, 50)

	fzf.fzf_exec(git_log_cmd, {
		prompt = "Select 1-2 commits for AI analysis (TAB to multi-select): ",
		fzf_args = "--multi",
		fzf_opts = {
			["--header"] = ":: Select 1-2 commits :: ENTER=analyze with AI :: TAB=multi-select :: CTRL-Y=copy hash",
			["--preview"] = picker_utils.create_commit_preview_command(),
		},
		actions = {
			["ctrl-y"] = function(selected)
				if not selected or #selected == 0 then
					return
				end
				picker_utils.copy_commit_hash(selected)
			end,
			["default"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				if #selected > 2 then
					vim.notify("Please select only 1 or 2 commits", vim.log.levels.WARN)
					return
				end

				local commits = {}
				for _, item in ipairs(selected) do
					local commit = item:match("^(%w+)")
					if commit then
						table.insert(commits, commit)
					end
				end

				if #commits == 0 then
					vim.notify("No valid commits selected", vim.log.levels.ERROR)
					return
				end

				local diff_cmd
				if #commits == 1 then
					diff_cmd = string.format("git diff %s | head -n 300", commits[1])
					vim.notify("Comparing " .. commits[1] .. " with working tree...", vim.log.levels.INFO)
				else
					diff_cmd = string.format("git diff %s %s | head -n 300", commits[1], commits[2])
					vim.notify("Comparing " .. commits[1] .. " " .. commits[2] .. "...", vim.log.levels.INFO)
				end

				local diff = vim.fn.system(diff_cmd):gsub("\r", "")
				local prompt = string.format(
					"Analyze this git diff. Identify bugs, regressions, or risky changes:\n\n```diff\n%s\n```",
					diff
				)

				ai.run(prompt, function(result, err)
					if err then
						vim.notify("AI analysis failed: " .. err, vim.log.levels.ERROR)
						return
					end
					-- Show in a scratch buffer
					local buf = vim.api.nvim_create_buf(false, true)
					local lines = vim.split(result, "\n")
					vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
					vim.bo[buf].filetype = "markdown"
					vim.bo[buf].bufhidden = "wipe"
					vim.cmd("vsplit")
					vim.api.nvim_win_set_buf(0, buf)
				end)
			end,
		},
	})
end

function M.setup()
	vim.api.nvim_create_user_command("FzfGithubCompareAI", function()
		M.fzf_github_analyse_ai()
	end, {})
end

return M
