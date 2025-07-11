local M = {}

function M.fzf_github_analyse_ai()
	local fzf = require("fzf-lua")

	fzf.git_commits({
		prompt = "Select 1-2 commits for AI analysis (TAB to multi-select): ",
		fzf_args = "--multi",
		cmd = "git log --color=always --pretty=format:'%C(blue)%h%C(reset) %C(green)%ad%C(reset) %s %C(red)%an%C(reset)' --date=format:'%d/%m/%Y' -n 50",
		fzf_opts = {
			["--header"] = ":: Select 1-2 commits :: ENTER=analyze with AI :: TAB=multi-select :: CTRL-Y=copy hash",
		},
		actions = {
			["ctrl-y"] = function(selected)
				if not selected or #selected == 0 then
					return
				end
				require("gitty.providers.github-compare.picker-utils").copy_commit_hash(selected)
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

				if #commits == 1 then
					-- Compare selected commit with working tree (staged + unstaged changes)
					vim.g.codecompanion_input = commits[1]
					vim.cmd("CodeCompanion /compare_two")
					vim.notify(
						"Comparing " .. commits[1] .. " with working tree (staged + unstaged changes)",
						vim.log.levels.INFO
					)
				else
					-- Two commits: compare between them
					vim.g.codecompanion_input = commits[1] .. " " .. commits[2]
					vim.cmd("CodeCompanion /compare_two")
					vim.notify("Comparing commits: " .. commits[1] .. " " .. commits[2], vim.log.levels.INFO)
				end
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
