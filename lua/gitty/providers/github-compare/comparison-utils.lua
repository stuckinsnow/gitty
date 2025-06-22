local M = {}

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
	-- Step 1: Select first branch
	local fzf = require("fzf-lua")

	fzf.git_branches({
		prompt = "Select first branch: ",
		fzf_opts = {
			["--header"] = ":: Select first branch for comparison",
		},
		actions = {
			["default"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				local first_branch = selected[1]:match("([^%s]+)$")
				if not first_branch then
					vim.notify("Failed to extract branch name", vim.log.levels.ERROR)
					return
				end

				-- Step 2: Select commit from first branch
				fzf.git_commits({
					prompt = string.format("Select commit from %s: ", first_branch),
					cmd = picker_utils.create_colorized_git_log_cmd(
						string.format(
							"git log --color=always --pretty=format:'%%C(blue)%%h%%C(reset) %%C(green)%%ad%%C(reset) %%s %%C(red)%%an%%C(reset)' --date=format:'%%d/%%m/%%Y' %s -n 50",
							first_branch
						)
					),
					fzf_opts = {
						["--header"] = string.format(":: Select commit from %s", first_branch),
					},
					actions = {
						["default"] = function(selected_commit1)
							if not selected_commit1 or #selected_commit1 == 0 then
								return
							end

							local commit1 = selected_commit1[1]:match("^(%w+)")
							if not commit1 then
								vim.notify("Failed to extract commit hash", vim.log.levels.ERROR)
								return
							end

							-- Step 3: Select second branch
							fzf.git_branches({
								prompt = string.format(
									"Select second branch (comparing %s from %s): ",
									commit1:sub(1, 7),
									first_branch
								),
								fzf_opts = {
									["--header"] = ":: Select second branch for comparison",
								},
								actions = {
									["default"] = function(selected2)
										if not selected2 or #selected2 == 0 then
											return
										end

										local second_branch = selected2[1]:match("([^%s]+)$")
										if not second_branch then
											vim.notify("Failed to extract branch name", vim.log.levels.ERROR)
											return
										end

										-- Step 4: Select commit from second branch
										fzf.git_commits({
											prompt = string.format("Select commit from %s: ", second_branch),
											cmd = picker_utils.create_colorized_git_log_cmd(
												string.format(
													"git log --color=always --pretty=format:'%%C(blue)%%h%%C(reset) %%C(green)%%ad%%C(reset) %%s %%C(red)%%an%%C(reset)' --date=format:'%%d/%%m/%%Y' %s -n 50",
													second_branch
												)
											),
											fzf_opts = {
												["--header"] = string.format(
													":: Select commit from %s :: ENTER=diffview :: CTRL-E=show diff",
													second_branch
												),
											},
											actions = {
												["default"] = function(selected_commit2)
													if not selected_commit2 or #selected_commit2 == 0 then
														return
													end

													local commit2 = selected_commit2[1]:match("^(%w+)")
													if not commit2 then
														vim.notify(
															"Failed to extract commit hash",
															vim.log.levels.ERROR
														)
														return
													end

													-- Step 5: Compare the commits
													vim.cmd("DiffviewOpen " .. commit1 .. ".." .. commit2)
													vim.notify(
														string.format(
															"Comparing %s (%s) vs %s (%s)",
															commit1:sub(1, 7),
															first_branch,
															commit2:sub(1, 7),
															second_branch
														),
														vim.log.levels.INFO
													)
												end,

												["ctrl-e"] = function(selected_commit2)
													if not selected_commit2 or #selected_commit2 == 0 then
														return
													end

													local commit2 = selected_commit2[1]:match("^(%w+)")
													if not commit2 then
														vim.notify(
															"Failed to extract commit hash",
															vim.log.levels.ERROR
														)
														return
													end

													-- Get the diff and show it in a buffer
													vim.system(
														{ "git", "diff", commit1 .. ".." .. commit2 },
														{ text = true },
														function(result)
															vim.schedule(function()
																if result.code ~= 0 then
																	vim.notify(
																		"Failed to get diff",
																		vim.log.levels.ERROR
																	)
																	return
																end

																local diff_content = result.stdout or ""
																if diff_content == "" then
																	vim.notify(
																		"No differences found between commits",
																		vim.log.levels.INFO
																	)
																	return
																end

																-- Create buffer for diff
																local github_utils =
																	require("gitty.utilities.github-utils")
																local win, buf = github_utils.create_side_buffer(
																	"git_diff",
																	0.6,
																	"diff"
																)

																-- Add header with commit info
																local header_lines = {
																	"# Git Diff",
																	"",
																	string.format(
																		"**From:** %s (%s)",
																		commit1:sub(1, 7),
																		first_branch
																	),
																	string.format(
																		"**To:** %s (%s)",
																		commit2:sub(1, 7),
																		second_branch
																	),
																	"",
																	"---",
																	"",
																}

																-- Split diff content into lines
																local diff_lines = vim.split(diff_content, "\n")

																-- Combine header and diff
																local all_lines = {}
																vim.list_extend(all_lines, header_lines)
																vim.list_extend(all_lines, diff_lines)

																vim.api.nvim_buf_set_lines(buf, 0, -1, false, all_lines)
																vim.bo[buf].modifiable = false
																vim.bo[buf].filetype = "diff" -- This will give proper diff syntax highlighting

																vim.keymap.set(
																	"n",
																	"<leader>q",
																	function()
																		vim.api.nvim_win_close(win, true)
																	end,
																	{ buffer = buf, nowait = true, desc = "Close diff" }
																)

																vim.notify(
																	string.format(
																		"Showing diff: %s..%s",
																		commit1:sub(1, 7),
																		commit2:sub(1, 7)
																	),
																	vim.log.levels.INFO
																)
															end)
														end
													)
												end,
											},
										})
									end,
								},
							})
						end,
					},
				})
			end,
		},
	})
end

function M.compare_with_minidiff()
	local fzf = require("fzf-lua")

	-- Step 1: Select branch first (like in compare_by_picker)
	fzf.git_branches({
		prompt = "Select branch for inline diff: ",
		fzf_opts = {
			["--header"] = ":: Select branch to choose commit from",
		},
		actions = {
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

	local fzf = require("fzf-lua")

	fzf.git_commits({
		prompt = "Select commit for selected text diff: ",
		actions = {
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
	local fzf = require("fzf-lua")

	-- Get current branch name
	vim.system({ "git", "branch", "--show-current" }, { text = true }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				vim.notify("Failed to get current branch", vim.log.levels.ERROR)
				return
			end

			local current_branch = vim.trim(result.stdout or "")
			if current_branch == "" then
				vim.notify("Not on a branch", vim.log.levels.ERROR)
				return
			end

			-- Single multi-select picker for two commits
			fzf.git_commits({
				prompt = string.format("Select two commits from %s: ", current_branch),
				cmd = picker_utils.create_colorized_git_log_cmd(
					string.format(
						"git log --color=always --pretty=format:'%%C(blue)%%h%%C(reset) %%C(green)%%ad%%C(reset) %%s %%C(red)%%an%%C(reset)' --date=format:'%%d/%%m/%%Y' %s -n 50",
						current_branch
					)
				),
				fzf_opts = {
					["--header"] = string.format(":: Multi-select two commits from %s (ENTER=diff)", current_branch),
					["--multi"] = true,
				},
				actions = {
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
				},
			})
		end)
	end)
end

return M
