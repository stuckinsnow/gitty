local M = {}

local fzf = require("fzf-lua")
local comparison_utils = require("gitty.providers.github-compare.comparison-utils")
local validation_utils = require("gitty.providers.github-compare.validation-utils")
local picker_utils = require("gitty.providers.github-compare.picker-utils")
local minidiff_utils = require("gitty.providers.github-compare.minidiff-utils")
local file_view_utils = require("gitty.providers.github-compare.file-view-utils")
local blame_utils = require("gitty.providers.github-compare.blame-utils")
local github_compare_ai = require("gitty.providers.github-compare.github-compare-ai")

function M.git_compare_commits()
	fzf.fzf_exec({
		"1. Compare commits from current branch",
		"2. Compare commits from different branches",
		"3. Compare specific commit hashes",
		"4. Compare hash with current file",
		"5. Mini Diff (inline)",
		"6. View file at commit - Split",
		"7. Find when file changed",
		"8. Copy blame commit hash",
		"9. Diff Analyse - AI",
		"10. Cherry-pick file from different branch",
		"11. Open files from commit in new tab",
		"12. Open files from previous commits",
	}, {
		prompt = "Git Compare> ",
		winopts = {
			width = 0.6,
			height = 0.4,
		},
		actions = {
			["default"] = function(selected)
				local choice = selected[1]
				if not choice then
					return
				end

				if choice:match("Compare commits from current branch") then
					M.compare_from_current_branch()
				elseif choice:match("Compare specific commit hashes") then
					M.compare_by_hash()
				elseif choice:match("Compare hash with current file") then
					M.compare_hash_with_current()
				elseif choice:match("Mini Diff %(inline%)") then
					M.compare_with_minidiff()
				elseif choice:match("View file at commit") then
					M.view_file_at_commit_picker()
				elseif choice:match("Find when file changed") then
					M.find_file_history()
				elseif choice:match("Copy blame commit hash") then
					M.copy_blame_commit_hash()
				elseif choice:match("Diff Analyse") then
					github_compare_ai.fzf_github_analyse_ai()
				elseif choice:match("Cherry%-pick file from different branch") then
					M.cherry_pick_file_from_branch()
				elseif choice:match("Open files from commit in new tab") then
					picker_utils.open_files_from_branch_commit_in_new_tab()
				elseif choice:match("Open files from previous commits") then
					M.fzf_last_commit_files()
				elseif choice:match("Compare commits from different branches") then
					M.compare_by_picker()
				end
			end,
		},
	})
end

M.compare_by_hash = comparison_utils.compare_by_hash
M.compare_hash_with_current = comparison_utils.compare_hash_with_current
M.compare_by_picker = comparison_utils.compare_by_picker
M.compare_with_minidiff = comparison_utils.compare_with_minidiff
M.compare_selected_with_minidiff = comparison_utils.compare_selected_with_minidiff
M.compare_from_current_branch = comparison_utils.compare_from_current_branch

M.validate_commit = validation_utils.validate_commit
M.validate_and_compare_hashes = validation_utils.validate_and_compare_hashes
M.validate_and_setup_minidiff = validation_utils.validate_and_setup_minidiff

M.view_file_at_commit_picker = picker_utils.view_file_at_commit_picker
M.pick_branch_and_commit = picker_utils.pick_branch_and_commit
M.pick_commit_from_branch = picker_utils.pick_commit_from_branch
M.create_colorized_git_log_cmd = picker_utils.create_colorized_git_log_cmd
M.fzf_last_commit_files = picker_utils.fzf_last_commit_files
M.open_files_from_branch_commit_in_new_tab = picker_utils.open_files_from_branch_commit_in_new_tab
M.open_all_files_from_commit_in_new_tab = picker_utils.open_all_files_from_commit_in_new_tab

M.setup_minidiff = minidiff_utils.setup_minidiff
M.setup_minidiff_for_selection = minidiff_utils.setup_minidiff_for_selection
M.reset_minidiff = minidiff_utils.reset_minidiff

M.goto_file_at_commit = file_view_utils.goto_file_at_commit
M.find_file_history = file_view_utils.find_file_history
M.show_commit_diff = file_view_utils.show_commit_diff
M.view_files_from_commits = file_view_utils.view_files_from_commits
M.copy_blame_commit_hash = blame_utils.copy_blame_commit_hash_for_current_line

function M.cherry_pick_file_from_branch()
	local fzf = require("fzf-lua")
	local current_file = vim.api.nvim_buf_get_name(0)

	if current_file == "" then
		vim.notify("No file in current buffer", vim.log.levels.ERROR)
		return
	end

	local relative_path = vim.fn.fnamemodify(current_file, ":~:.")

	-- Step 1: Select branch
	fzf.git_branches({
		prompt = "Select branch to cherry-pick file from: ",
		fzf_opts = {
			["--header"] = ":: Select source branch for " .. vim.fn.fnamemodify(current_file, ":t") .. " ::",
		},
		actions = {
			["ctrl-x"] = false,
			["ctrl-a"] = false,
			["default"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				local branch = selected[1]:match("([^%s]+)$")
				if not branch then
					vim.notify("Failed to extract branch name", vim.log.levels.ERROR)
					return
				end

				M.select_commit_from_branch_for_cherry_pick(branch, relative_path, current_file)
			end,
		},
	})
end

function M.select_commit_from_branch_for_cherry_pick(branch, relative_path, current_file)
	local fzf = require("fzf-lua")

	-- Step 2: Select commit from the chosen branch
	-- Use fzf_exec instead of git_commits to get full control over preview
	local git_log_cmd = picker_utils.create_colorized_git_log_cmd(
		string.format(
			"git log --color=always --pretty=format:'%%C(blue)%%h%%C(reset) %%C(green)%%ad%%C(reset) %%s %%C(red)%%an%%C(reset)' --date=format:'%%d/%%m/%%Y' %s -n 50",
			branch
		)
	)

	fzf.fzf_exec(git_log_cmd, {
		prompt = string.format("Select commit from %s: ", branch),
		fzf_opts = {
			["--header"] = string.format(
				":: Select commit from %s for %s ::",
				branch,
				vim.fn.fnamemodify(current_file, ":t")
			),
			["--preview"] = picker_utils.create_commit_preview_command(),
		},
		actions = {
			["ctrl-x"] = false,
			["ctrl-a"] = false,
			["default"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				local commit = selected[1]:match("^(%w+)")
				if not commit then
					vim.notify("Failed to extract commit hash", vim.log.levels.ERROR)
					return
				end

				M.show_file_from_commit_with_cherry_pick(branch, commit, relative_path, current_file)
			end,
		},
	})
end

function M.show_file_from_commit_with_cherry_pick(branch, commit, relative_path, current_file)
	-- Get the file content from the specific commit
	vim.system({ "git", "show", string.format("%s:%s", commit, relative_path) }, { text = true }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				vim.notify(
					string.format("File '%s' not found in commit '%s'", relative_path, commit:sub(1, 7)),
					vim.log.levels.ERROR
				)
				return
			end

			-- Create buffer for the branch version
			local branch_buf = vim.api.nvim_create_buf(false, true)
			local branch_lines = vim.split(result.stdout or "", "\n")
			if branch_lines[#branch_lines] == "" then
				table.remove(branch_lines)
			end

			vim.api.nvim_buf_set_lines(branch_buf, 0, -1, false, branch_lines)

			-- Set same filetype as current buffer for syntax highlighting
			local current_buf = vim.api.nvim_get_current_buf()
			vim.bo[branch_buf].filetype = vim.bo[current_buf].filetype

			-- Create split to show the file from the branch
			local current_win = vim.api.nvim_get_current_win()
			vim.cmd("vsplit")
			local branch_win = vim.api.nvim_get_current_win()
			vim.api.nvim_win_set_buf(branch_win, branch_buf)

			-- Set window titles
			vim.wo[current_win].winbar = "%#GittyCurrentTitle#Current ("
				.. vim.fn.fnamemodify(current_file, ":t")
				.. ")"
			vim.wo[branch_win].winbar = "%#GittyBranchTitle#"
				.. branch
				.. "@"
				.. commit:sub(1, 7)
				.. " ("
				.. vim.fn.fnamemodify(current_file, ":t")
				.. ")"

			-- Set up keymaps for cherry-picking
			vim.keymap.set("n", "<CR>", function()
				M.confirm_cherry_pick_from_commit(
					branch,
					commit,
					relative_path,
					current_file,
					branch_buf,
					branch_win,
					current_win,
					current_buf
				)
			end, { buffer = branch_buf, desc = "Cherry-pick this file content" })

			vim.keymap.set("n", "<leader>q", function()
				M.close_cherry_pick_view(branch_buf, branch_win, current_win)
			end, { buffer = branch_buf, desc = "Close cherry-pick view" })

			-- Also add the same keymaps to current buffer for convenience
			vim.keymap.set("n", "<leader>q", function()
				M.close_cherry_pick_view(branch_buf, branch_win, current_win)
			end, { buffer = current_buf, desc = "Close cherry-pick view" })

			vim.notify(
				string.format(
					"Viewing '%s' from %s@%s | <CR>=cherry-pick | <leader>q=close",
					vim.fn.fnamemodify(current_file, ":t"),
					branch,
					commit:sub(1, 7)
				),
				vim.log.levels.INFO
			)
		end)
	end)
end

function M.confirm_cherry_pick_from_commit(
	branch,
	commit,
	relative_path,
	current_file,
	branch_buf,
	branch_win,
	current_win,
	target_buf
)
	local choice = vim.fn.confirm(
		string.format(
			"Cherry-pick file '%s' from %s@%s?\nThis will replace the current file content.",
			vim.fn.fnamemodify(current_file, ":t"),
			branch,
			commit:sub(1, 7)
		),
		"&Yes\n&No",
		2
	)

	if choice == 1 then
		-- Get content from branch buffer
		local branch_lines = vim.api.nvim_buf_get_lines(branch_buf, 0, -1, false)

		-- Replace target buffer content (the original file buffer)
		vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, branch_lines)

		-- Mark buffer as modified
		vim.bo[target_buf].modified = true

		-- Close the cherry-pick view
		M.close_cherry_pick_view(branch_buf, branch_win, current_win)

		vim.notify(
			string.format(
				"Cherry-picked '%s' from %s@%s",
				vim.fn.fnamemodify(current_file, ":t"),
				branch,
				commit:sub(1, 7)
			),
			vim.log.levels.INFO
		)
	end
end

function M.close_cherry_pick_view(branch_buf, branch_win, current_win)
	-- Clean up keymaps
	local current_buf = vim.api.nvim_get_current_buf()
	pcall(vim.keymap.del, "n", "<leader>q", { buffer = current_buf })
	pcall(vim.keymap.del, "n", "<CR>", { buffer = branch_buf })
	pcall(vim.keymap.del, "n", "<leader>q", { buffer = branch_buf })

	-- Close window and delete buffer
	if vim.api.nvim_win_is_valid(branch_win) then
		vim.api.nvim_win_close(branch_win, true)
	end
	if vim.api.nvim_buf_is_valid(branch_buf) then
		vim.api.nvim_buf_delete(branch_buf, { force = true })
	end

	-- Clear window titles
	if vim.api.nvim_win_is_valid(current_win) then
		vim.wo[current_win].winbar = ""
		vim.api.nvim_set_current_win(current_win)
	end
end

function M.setup()
	vim.keymap.set("n", "<leader>g2", M.git_compare_commits, { desc = "Git Compare" })
	vim.keymap.set("n", "<leader>g3", M.compare_with_minidiff, { desc = "Git Mini Diff" })
	vim.keymap.set("v", "<leader>g3", M.compare_selected_with_minidiff, { desc = "Git Mini Diff Selection" })
end

return M
