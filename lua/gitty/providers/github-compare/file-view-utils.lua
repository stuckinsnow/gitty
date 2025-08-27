local M = {}

local validation_utils = require("gitty.providers.github-compare.validation-utils")
local config = require("gitty.config")

function M.goto_file_at_commit(commit)
	local current_buf = vim.api.nvim_get_current_buf()
	local file_path = vim.api.nvim_buf_get_name(current_buf)

	if file_path == "" then
		vim.notify("No file in current buffer", vim.log.levels.ERROR)
		return
	end

	vim.system(
		{ "git", "show", string.format("%s:%s", commit, vim.fn.fnamemodify(file_path, ":~:.")) },
		{ text = true },
		function(result)
			vim.schedule(function()
				if result.code ~= 0 then
					vim.notify("Failed to get file from commit " .. commit:sub(1, 7), vim.log.levels.ERROR)
					return
				end

				-- Create buffers and setup content
				local commit_buf = vim.api.nvim_create_buf(false, true)
				local current_diff_buf = vim.api.nvim_create_buf(false, true)
				local commit_lines = vim.split(result.stdout or "", "\n")
				if commit_lines[#commit_lines] == "" then
					table.remove(commit_lines)
				end

				vim.api.nvim_buf_set_lines(commit_buf, 0, -1, false, commit_lines)
				vim.api.nvim_buf_set_lines(
					current_diff_buf,
					0,
					-1,
					false,
					vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)
				)
				-- Configure tree-sitter/syntax highlighting for buffers
				-- Left window (current version)
				if config.options.split_diff_treesitter_left then
					vim.bo[current_diff_buf].filetype = vim.bo[current_buf].filetype
				else
					vim.bo[current_diff_buf].filetype = ""
					vim.bo[current_diff_buf].syntax = "off"
				end

				-- Right window (commit version)
				if config.options.split_diff_treesitter_right then
					vim.bo[commit_buf].filetype = vim.bo[current_buf].filetype
				else
					vim.bo[commit_buf].filetype = ""
					vim.bo[commit_buf].syntax = "off"
				end

				-- Create layout
				local edit_win = vim.api.nvim_get_current_win()
				vim.cmd("split")
				vim.cmd("vsplit")
				local bottom_right_win = vim.api.nvim_get_current_win()
				local bottom_left_win = vim.fn.win_getid(vim.fn.winnr("#"))

				vim.api.nvim_win_set_buf(bottom_left_win, current_diff_buf)
				vim.api.nvim_win_set_buf(bottom_right_win, commit_buf)
				vim.wo[bottom_left_win].diff = true
				vim.wo[bottom_right_win].diff = true

				-- Add custom highlighting for better visual distinction
				vim.wo[bottom_left_win].winhighlight = "Normal:GittySplitLeft"
				vim.wo[bottom_right_win].winhighlight = "Normal:GittySplitRight"
				-- Add window titles for clarity
				vim.wo[bottom_left_win].winbar = "%#GittySplitLeftTitle#Current Version"
				vim.wo[bottom_right_win].winbar = "%#GittySplitRightTitle#Commit " .. commit:sub(1, 7)

				vim.api.nvim_set_current_win(edit_win)

				-- Setup cleanup state
				local closed = false
				local group = vim.api.nvim_create_augroup("CommitDiffView", { clear = true })

				local function close_diff_view()
					if closed then
						return
					end
					closed = true

					-- Clean up keymaps
					pcall(vim.keymap.del, "n", "<leader>q", { buffer = current_buf })
					pcall(vim.keymap.del, "n", "<leader>q", { buffer = commit_buf })
					pcall(vim.keymap.del, "n", "<leader>q", { buffer = current_diff_buf })

					-- Close windows and delete buffers
					if vim.api.nvim_win_is_valid(bottom_right_win) then
						vim.api.nvim_win_close(bottom_right_win, true)
					end
					if vim.api.nvim_win_is_valid(bottom_left_win) then
						vim.api.nvim_win_close(bottom_left_win, true)
					end
					if vim.api.nvim_buf_is_valid(commit_buf) then
						vim.api.nvim_buf_delete(commit_buf, { force = true })
					end
					if vim.api.nvim_buf_is_valid(current_diff_buf) then
						vim.api.nvim_buf_delete(current_diff_buf, { force = true })
					end

					pcall(vim.api.nvim_del_augroup_by_id, group)
					vim.api.nvim_set_current_win(edit_win)
				end

				-- Setup autocmds and keymaps
				vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
					group = group,
					buffer = current_buf,
					callback = function()
						vim.api.nvim_buf_set_lines(
							current_diff_buf,
							0,
							-1,
							false,
							vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)
						)
					end,
				})

				vim.api.nvim_create_autocmd("CursorMoved", {
					group = group,
					buffer = current_buf,
					callback = function()
						local current_win = vim.api.nvim_get_current_win()
						local line = vim.api.nvim_win_get_cursor(current_win)[1]
						for _, win in ipairs({ edit_win, bottom_left_win, bottom_right_win }) do
							if win ~= current_win and vim.api.nvim_win_is_valid(win) then
								pcall(vim.api.nvim_win_set_cursor, win, { line, 0 })
							end
						end
					end,
				})

				vim.api.nvim_create_autocmd("WinClosed", {
					group = group,
					callback = function(args)
						local closed_win = tonumber(args.match)
						if closed_win == bottom_left_win or closed_win == bottom_right_win then
							close_diff_view()
						end
					end,
				})

				-- Set keymaps
				local keymap_opts = { desc = "Close diff view", nowait = true }
				vim.keymap.set(
					"n",
					"<leader>q",
					close_diff_view,
					vim.tbl_extend("force", keymap_opts, { buffer = current_buf })
				)
				vim.keymap.set(
					"n",
					"<leader>q",
					close_diff_view,
					vim.tbl_extend("force", keymap_opts, { buffer = commit_buf })
				)
				vim.keymap.set(
					"n",
					"<leader>q",
					close_diff_view,
					vim.tbl_extend("force", keymap_opts, { buffer = current_diff_buf })
				)

				vim.notify(
					string.format(
						"3-pane diff: %s (left) vs %s (right) | <leader>q=close",
						vim.fn.fnamemodify(file_path, ":t"),
						commit:sub(1, 7)
					),
					vim.log.levels.INFO
				)
			end)
		end
	)
end

function M.find_file_history()
	-- Get current file
	local file_path = vim.api.nvim_buf_get_name(0)

	if file_path == "" then
		vim.notify("No file in current buffer", vim.log.levels.ERROR)
		return
	end

	local fzf = require("fzf-lua")
	local relative_path = vim.fn.fnamemodify(file_path, ":~:.")

	-- Use git log directly instead of through picker-utils
	local base_cmd = string.format(
		"git log --color=always --no-abbrev-commit --pretty=format:'%%C(blue)%%h%%C(reset) %%C(green)%%ad%%C(reset) %%s %%C(red)%%an%%C(reset)' --date=format:'%%d/%%m/%%Y' --follow %s",
		vim.fn.shellescape(relative_path)
	)

	local cmd = base_cmd
		.. " | sed -E 's/^(.*) (feat[^[:space:]]*)/\\1 \\x1b[33m\\2\\x1b[0m/I; s/^(.*) (fix[^[:space:]]*)/\\1 \\x1b[32m\\2\\x1b[0m/I; s/^(.*) (chore[^[:space:]]*)/\\1 \\x1b[31m\\2\\x1b[0m/I; s/^(.*) (add[^[:space:]]*)/\\1 \\x1b[35m\\2\\x1b[0m/I'"

	fzf.git_commits({
		prompt = string.format("Commits that modified %s: ", vim.fn.fnamemodify(file_path, ":t")),
		cmd = cmd,
		fzf_opts = {
			["--header"] = ":: File history :: ENTER=copy short hash :: CTRL-V=split view",
		},
		actions = {
			["ctrl-y"] = false,
			["default"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				local commit = selected[1]:match("^(%w+)")
				if not commit then
					vim.notify("Invalid commit", vim.log.levels.ERROR)
					return
				end

				-- Copy short commit hash to system clipboard
				vim.fn.setreg("+", commit)
				vim.notify("Copied short commit hash: " .. commit, vim.log.levels.INFO)
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

				M.goto_file_at_commit(commit)
			end,
		},
	})
end

function M.show_commit_diff(commit)
	validation_utils.validate_commit(commit, function()
		vim.cmd("DiffviewOpen " .. commit .. "^.." .. commit)
		vim.notify("Showing changes in commit " .. commit:sub(1, 7), vim.log.levels.INFO)
	end)
end

function M.view_files_from_commits()
	local picker_utils = require("gitty.providers.github-compare.picker-utils")
	picker_utils.fzf_last_commit_files()
end
return M
