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
												["--header"] = string.format(":: Select commit from %s", second_branch),
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

	fzf.git_commits({
		prompt = "Select commit for inline diff: ",
		fzf_opts = {
			["--header"] = ":: ENTER=diff :: CTRL-V=view file at commit",
		},
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

				minidiff_utils.setup_minidiff(commit)
			end,
			["ctrl-v"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				local commit = selected[1]:match("^(%w+)")
				if not commit then
					vim.notify("Invalid commit", vim.log.levels.ERROR)
					return
				end

				require("gitty.providers.github-compare.file-view-utils").goto_file_at_commit(commit)
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

return M
