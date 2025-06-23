local M = {}

local fzf = require("fzf-lua")
local picker_utils = require("gitty.providers.github-compare.picker-utils")
local validation_utils = require("gitty.providers.github-compare.validation-utils")
local minidiff_utils = require("gitty.providers.github-compare.minidiff-utils")

function M.compare_by_hash()
	-- Choose diff method first
	vim.ui.select({ "Diffview", "Mini Diff (inline)" }, {
		prompt = "Choose diff method:",
	}, function(diff_method)
		if not diff_method then
			return
		end

		if diff_method == "Mini Diff (inline)" then
			-- Mini Diff only needs one commit
			local commit = vim.fn.input("Enter commit hash: ")
			if not commit or commit:match("^%s*$") then
				return
			end

			commit = vim.trim(commit):match("(%w+)")
			if not commit then
				vim.notify("Invalid commit hash format", vim.log.levels.ERROR)
				return
			end

			validation_utils.validate_and_setup_minidiff(commit)
			return
		end

		-- For DiffView, get first commit
		local commit1 = vim.fn.input("Enter first commit hash: ")
		if not commit1 or commit1:match("^%s*$") then
			return
		end

		commit1 = vim.trim(commit1):match("(%w+)")
		if not commit1 then
			vim.notify("Invalid commit hash format", vim.log.levels.ERROR)
			return
		end

		-- Get second commit for DiffView
		local commit2 = vim.fn.input("Enter second commit hash (empty to pick from branch): ")

		if commit2 and not commit2:match("^%s*$") then
			commit2 = vim.trim(commit2):match("(%w+)")
			if not commit2 then
				vim.notify("Invalid second commit hash format", vim.log.levels.ERROR)
				return
			end
			validation_utils.validate_and_compare_hashes(commit1, commit2)
		else
			picker_utils.pick_branch_and_commit(commit1)
		end
	end)
end

function M.compare_hash_with_current()
	local commit = vim.fn.input("Enter commit hash: ")
	if not commit or commit:match("^%s*$") then
		return
	end

	commit = vim.trim(commit):match("(%w+)")
	if not commit then
		vim.notify("Invalid commit hash format", vim.log.levels.ERROR)
		return
	end

	-- Choose diff method
	vim.ui.select({ "Diffview", "Mini Diff (inline)" }, {
		prompt = "Choose diff method:",
	}, function(choice)
		if not choice then
			return
		end

		if choice == "Mini Diff (inline)" then
			validation_utils.validate_and_setup_minidiff(commit)
		else
			-- Validate first, then open DiffView
			validation_utils.validate_commit(commit, function()
				vim.cmd("DiffviewOpen " .. commit)
				vim.notify("Comparing " .. commit:sub(1, 7) .. " with working directory", vim.log.levels.INFO)
			end)
		end
	end)
end

function M.compare_by_picker()
	fzf.git_branches({
		prompt = "Select two branches for comparison: ",
		fzf_args = "--multi",
		fzf_opts = {
			["--header"] = ":: Multi-select two branches for comparison",
		},
		actions = {
			["ctrl-y"] = false,
			["ctrl-a"] = false,
			["ctrl-x"] = false,
			["default"] = function(selected)
				if not selected or #selected ~= 2 then
					vim.notify("Please select exactly two branches", vim.log.levels.WARN)
					return
				end

				local branch1 = selected[1]:match("([^%s]+)$")
				local branch2 = selected[2]:match("([^%s]+)$")

				if not branch1 or not branch2 then
					vim.notify("Failed to extract branch names", vim.log.levels.ERROR)
					return
				end

				vim.schedule(function()
					local n = 50
					local function get_commits(branch, label)
						local cmd = string.format(
							"git log --color=always --pretty=format:'%%h|%%ct|%%C(blue)%%h%%C(reset) %%C(green)%%ad%%C(reset) %%s %%C(red)%%an%%C(reset)' --date=format:'%%d/%%m/%%Y' %s -n %d",
							branch,
							n
						)
						local handle = io.popen(cmd)
						local commits = {}
						if handle then
							for line in handle:lines() do
								local hash, ts, rest = line:match("([^|]+)|([^|]+)|(.+)")
								if hash and ts and rest then
									commits[hash] = { ts = tonumber(ts), rest = rest, label = label }
								end
							end
							handle:close()
						end
						return commits
					end

					local commits1 = get_commits(branch1, "B1")
					local commits2 = get_commits(branch2, "B2")
					local all = {}

					-- Merge, mark B0 if in both
					for hash, c in pairs(commits1) do
						all[hash] = vim.deepcopy(c)
					end
					for hash, c in pairs(commits2) do
						if all[hash] then
							all[hash].label = "B0"
						else
							all[hash] = vim.deepcopy(c)
						end
					end

					local commit_list = {}
					for _, c in pairs(all) do
						local color = "\27[36m" -- Cyan for B0
						if c.label == "B1" then
							color = "\27[35m" -- Magenta for B1
						elseif c.label == "B2" then
							color = "\27[33m" -- Yellow for B2
						end
						table.insert(commit_list, {
							ts = c.ts,
							display = string.format("%s[%s]%s %s", color, c.label, "\27[0m", c.rest),
						})
					end
					table.sort(commit_list, function(a, b)
						return a.ts > b.ts
					end)
					local all_commits = {}
					for _, c in ipairs(commit_list) do
						table.insert(all_commits, c.display)
					end

					local prompt = string.format(
						"Select from \27[31m[%s]\27[0m, \27[32m[%s]\27[0m, \27[34m[both]\27[0m: ",
						branch1,
						branch2
					)
					fzf.fzf_exec(all_commits, {
						prompt = prompt,
						fzf_args = "--multi",
						fzf_opts = {
							["--header"] = ":: Multi-select two commits for comparison",
							["--preview"] = "git show {2} | delta --width $((FZF_PREVIEW_COLUMNS-1))",
						},
						actions = {
							["ctrl-y"] = false,
							["ctrl-a"] = false,
							["ctrl-x"] = false,
							["default"] = function(selected_commits)
								if not selected_commits or #selected_commits ~= 2 then
									vim.notify("Please select exactly two commits", vim.log.levels.WARN)
									return
								end
								local commit1 = selected_commits[1]:match("%]%s+(%w+)")
									or selected_commits[1]:match("^(%w+)")
								local commit2 = selected_commits[2]:match("%]%s+(%w+)")
									or selected_commits[2]:match("^(%w+)")
								if not commit1 or not commit2 then
									vim.notify("Failed to extract commit hashes", vim.log.levels.ERROR)
									return
								end
								vim.cmd("DiffviewOpen " .. commit1 .. ".." .. commit2)
								vim.notify(
									string.format("Comparing %s vs %s", commit1:sub(1, 7), commit2:sub(1, 7)),
									vim.log.levels.INFO
								)
							end,
						},
					})
				end)
			end,
		},
	})
end

function M.compare_with_minidiff()
	-- Step 1: Select branch first (like in compare_by_picker)
	fzf.git_branches({
		prompt = "Select branch for inline diff: ",
		fzf_opts = {
			["--header"] = ":: Select branch to choose commit from",
		},
		actions = {
			["ctrl-y"] = false,
			["ctrl-a"] = false,
			["ctrl-x"] = false,
			["default"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				local branch = selected[1]:match("([^%s]+)$")
				if not branch then
					vim.notify("Failed to extract branch name", vim.log.levels.ERROR)
					return
				end

				-- Step 2: Select commit from the chosen branch with proper date formatting
				fzf.git_commits({
					prompt = string.format("Select commit from %s for inline diff: ", branch),
					cmd = picker_utils.create_colorized_git_log_cmd(
						string.format(
							"git log --color=always --pretty=format:'%%C(blue)%%h%%C(reset) %%C(green)%%ad%%C(reset) %%s %%C(red)%%an%%C(reset)' --date=format:'%%d/%%m/%%Y' %s -n 50",
							branch
						)
					),
					fzf_opts = {
						["--header"] = string.format(":: ENTER=diff :: CTRL-V=view file at commit from %s", branch),
					},
					actions = {
						["ctrl-y"] = false,
						["ctrl-a"] = false,
						["ctrl-x"] = false,
						["default"] = function(selected_commit)
							if not selected_commit or #selected_commit == 0 then
								return
							end

							local commit = selected_commit[1]:match("^(%w+)")
							if not commit then
								vim.notify("Invalid commit", vim.log.levels.ERROR)
								return
							end

							minidiff_utils.setup_minidiff(commit)
						end,
						["ctrl-v"] = function(selected_commit)
							if not selected_commit or #selected_commit == 0 then
								return
							end

							local commit = selected_commit[1]:match("^(%w+)")
							if not commit then
								vim.notify("Invalid commit", vim.log.levels.ERROR)
								return
							end

							require("gitty.providers.github-compare.file-view-utils").goto_file_at_commit(commit)
						end,
					},
				})
			end,
		},
	})
end

function M.compare_selected_with_minidiff()
	-- Get visual selection
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")
	local start_line = start_pos[2]
	local end_line = end_pos[2]

	if start_line > end_line then
		start_line, end_line = end_line, start_line
	end

	fzf.git_commits({
		prompt = "Select commit for selected text diff: ",
		actions = {
			["ctrl-y"] = false,
			["ctrl-a"] = false,
			["ctrl-x"] = false,
			["default"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				local commit = selected[1]:match("^(%w+)")
				if not commit then
					vim.notify("Invalid commit", vim.log.levels.ERROR)
					return
				end

				minidiff_utils.setup_minidiff_for_selection(commit, start_line, end_line)
			end,
		},
	})
end

function M.compare_from_current_branch()
	local current_branch = vim.fn.system("git branch --show-current"):gsub("%s+", "")
	if current_branch == "" then
		vim.notify("Failed to get current branch or not on a branch", vim.log.levels.ERROR)
		return
	end

	fzf.git_commits({
		prompt = string.format("Select two commits from %s: ", current_branch),
		fzf_args = "--multi",
		fzf_opts = {
			["--header"] = string.format(
				":: Multi-select two commits from %s (ENTER=diff, CTRL-E=show diff)",
				current_branch
			),
		},
		cmd = string.format(
			"git log --color=always --pretty=format:'%%C(blue)%%h%%C(reset) %%C(green)%%ad%%C(reset) %%s %%C(red)%%an%%C(reset)' --date=format:'%%d/%%m/%%Y' %s -n 50",
			current_branch
		),
		actions = {
			["ctrl-y"] = false,
			["ctrl-a"] = false,
			["ctrl-x"] = false,
			["default"] = function(selected)
				if not selected or #selected ~= 2 then
					vim.notify("Please select exactly two commits", vim.log.levels.WARN)
					return
				end

				local commit1 = selected[1]:match("^(%w+)")
				local commit2 = selected[2]:match("^(%w+)")
				if not commit1 or not commit2 then
					vim.notify("Failed to extract commit hashes", vim.log.levels.ERROR)
					return
				end

				validation_utils.validate_and_compare_hashes(commit1, commit2)
			end,
			["ctrl-e"] = function(selected)
				if not selected or #selected ~= 2 then
					vim.notify("Please multi-select exactly two commits for diff (use <Tab>)", vim.log.levels.WARN)
					return
				end

				local commit1 = selected[1]:match("^(%w+)")
				local commit2 = selected[2]:match("^(%w+)")
				if not commit1 or not commit2 then
					vim.notify("Failed to extract commit hashes", vim.log.levels.ERROR)
					return
				end

				vim.system({ "git", "diff", commit1 .. ".." .. commit2 }, { text = true }, function(result)
					vim.schedule(function()
						if result.code ~= 0 then
							vim.notify("Failed to get diff", vim.log.levels.ERROR)
							return
						end

						local diff_content = result.stdout or ""
						if diff_content == "" then
							vim.notify("No differences found between commits", vim.log.levels.INFO)
							return
						end

						local github_utils = require("gitty.utilities.github-utils")
						local win, buf = github_utils.create_side_buffer("git_diff", 0.6, "diff")

						local header_lines = {
							"# Git Diff",
							"",
							string.format("**From:** %s (%s)", commit1:sub(1, 7), current_branch),
							string.format("**To:** %s (%s)", commit2:sub(1, 7), current_branch),
							"",
							"---",
							"",
						}
						local diff_lines = vim.split(diff_content, "\n")
						local all_lines = {}
						vim.list_extend(all_lines, header_lines)
						vim.list_extend(all_lines, diff_lines)

						vim.api.nvim_buf_set_lines(buf, 0, -1, false, all_lines)
						vim.bo[buf].modifiable = false
						vim.bo[buf].filetype = "diff"

						vim.keymap.set("n", "<leader>q", function()
							vim.api.nvim_win_close(win, true)
						end, { buffer = buf, nowait = true, desc = "Close diff" })

						vim.notify(
							string.format("Showing diff: %s..%s", commit1:sub(1, 7), commit2:sub(1, 7)),
							vim.log.levels.INFO
						)
					end)
				end)
			end,
		},
	})
end

return M
