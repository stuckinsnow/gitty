local M = {}

local comparison_utils = require("gitty.providers.github-compare.comparison-utils")
local validation_utils = require("gitty.providers.github-compare.validation-utils")
local picker_utils = require("gitty.providers.github-compare.picker-utils")
local minidiff_utils = require("gitty.providers.github-compare.minidiff-utils")
local file_view_utils = require("gitty.providers.github-compare.file-view-utils")

function M.git_compare_commits()
	vim.ui.select({
		"Select from list - Current branch",
		"Select from list",
		"Enter hashes directly",
		"Compare hash with current file",
		"Mini Diff (inline)",
		"View file at commit - Split",
		"Find when file changed",
	}, {
		prompt = "How would you like to compare?",
	}, function(choice)
		if not choice then
			return
		end

		if choice == "Select from list - Current branch" then
			M.compare_from_current_branch()
		elseif choice == "Enter hashes directly" then
			M.compare_by_hash()
		elseif choice == "Compare hash with current file" then
			M.compare_hash_with_current()
		elseif choice == "Mini Diff (inline)" then
			M.compare_with_minidiff()
		elseif choice == "View file at commit - Split" then
			M.view_file_at_commit_picker()
		elseif choice == "Find when file changed" then
			M.find_file_history()
		else
			M.compare_by_picker()
		end
	end)
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

M.setup_minidiff = minidiff_utils.setup_minidiff
M.setup_minidiff_for_selection = minidiff_utils.setup_minidiff_for_selection
M.reset_minidiff = minidiff_utils.reset_minidiff

M.goto_file_at_commit = file_view_utils.goto_file_at_commit
M.find_file_history = file_view_utils.find_file_history
M.show_commit_diff = file_view_utils.show_commit_diff

function M.setup()
	vim.keymap.set("n", "<leader>g2", M.git_compare_commits, { desc = "Git Compare" })
	vim.keymap.set("n", "<leader>g3", M.compare_with_minidiff, { desc = "Git Mini Diff" })
	vim.keymap.set("v", "<leader>g3", M.compare_selected_with_minidiff, { desc = "Git Mini Diff Selection" })
end

return M
