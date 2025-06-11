local M = {}

function M.git_compare_commits()
	vim.ui.select({
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

		if choice == "Enter hashes directly" then
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

function M.view_file_at_commit_picker()
	local fzf = require("fzf-lua")

	fzf.git_commits({
		prompt = "Select commit to view file: ",
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

				M.goto_file_at_commit(commit)
			end,
		},
	})
end

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

			M.validate_and_setup_minidiff(commit)
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
			M.validate_and_compare_hashes(commit1, commit2)
		else
			M.pick_branch_and_commit(commit1)
		end
	end)
end

local function create_colorized_git_log_cmd(base_cmd)
	return base_cmd
		.. " | sed -E 's/^(.*) (feat[^[:space:]]*)/\\1 \\x1b[33m\\2\\x1b[0m/I; s/^(.*) (fix[^[:space:]]*)/\\1 \\x1b[32m\\2\\x1b[0m/I; s/^(.*) (chore[^[:space:]]*)/\\1 \\x1b[31m\\2\\x1b[0m/I; s/^(.*) (add[^[:space:]]*)/\\1 \\x1b[35m\\2\\x1b[0m/I'"
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
			M.validate_and_setup_minidiff(commit)
		else
			-- Validate first, then open DiffView
			M.validate_commit(commit, function()
				vim.cmd("DiffviewOpen " .. commit)
				vim.notify("Comparing " .. commit:sub(1, 7) .. " with working directory", vim.log.levels.INFO)
			end)
		end
	end)
end

function M.validate_commit(commit, callback)
	vim.system({ "git", "rev-parse", "--verify", commit }, { text = true }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				vim.notify("Commit not found: " .. commit, vim.log.levels.ERROR)
			else
				callback()
			end
		end)
	end)
end

function M.validate_and_compare_hashes(commit1, commit2)
	M.validate_commit(commit1, function()
		M.validate_commit(commit2, function()
			vim.cmd("DiffviewOpen " .. commit1 .. ".." .. commit2)
			vim.notify(string.format("Comparing %s..%s", commit1:sub(1, 7), commit2:sub(1, 7)), vim.log.levels.INFO)
		end)
	end)
end

function M.validate_and_setup_minidiff(commit)
	M.validate_commit(commit, function()
		M.setup_minidiff(commit)
	end)
end

function M.pick_branch_and_commit(commit1)
	local fzf = require("fzf-lua")

	M.validate_commit(commit1, function()
		fzf.git_branches({
			prompt = "Select branch for second commit: ",
			fzf_opts = {
				["--header"] = ":: Select branch for second commit",
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

					M.pick_commit_from_branch(commit1, branch)
				end,
			},
		})
	end)
end

function M.pick_commit_from_branch(commit1, branch)
	local fzf = require("fzf-lua")

	fzf.git_commits({
		prompt = string.format("Select commit from %s: ", branch),
		cmd = create_colorized_git_log_cmd(
			string.format(
				"git log --color=always --pretty=format:'%%C(blue)%%h%%C(reset) %%C(green)%%ad%%C(reset) %%s %%C(red)%%an%%C(reset)' --date=format:'%%d/%%m/%%Y' %s -n 50",
				branch
			)
		),
		fzf_opts = {
			["--header"] = string.format(":: Select commit from %s", branch),
		},
		actions = {
			["default"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				local commit2 = selected[1]:match("^(%w+)")
				if not commit2 then
					vim.notify("Failed to extract commit hash", vim.log.levels.ERROR)
					return
				end

				vim.cmd("DiffviewOpen " .. commit1 .. ".." .. commit2)
				vim.notify(
					string.format("Comparing %s..%s (from %s)", commit1:sub(1, 7), commit2:sub(1, 7), branch),
					vim.log.levels.INFO
				)
			end,
		},
	})
end

-- Keep the rest of the functions from the simplified version
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
					cmd = create_colorized_git_log_cmd(
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
											cmd = create_colorized_git_log_cmd(
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

				M.setup_minidiff(commit)
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
				vim.bo[commit_buf].filetype = vim.bo[current_buf].filetype
				vim.bo[current_diff_buf].filetype = vim.bo[current_buf].filetype

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
						"3-pane diff: %s vs %s | <leader>q=close",
						vim.fn.fnamemodify(file_path, ":t"),
						commit:sub(1, 7)
					),
					vim.log.levels.INFO
				)
			end)
		end
	)
end

function M.setup_minidiff(commit)
	local minidiff = require("mini.diff")

	local buf = vim.api.nvim_get_current_buf()
	local file_path = vim.api.nvim_buf_get_name(buf)

	if file_path == "" then
		vim.notify("No file in current buffer", vim.log.levels.ERROR)
		return
	end

	-- Reset mini.diff state
	if not M.reset_minidiff(buf) then
		vim.notify("mini.diff not available", vim.log.levels.ERROR)
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

				local ref_text = result.stdout or ""
				minidiff.set_ref_text(buf, ref_text)
				minidiff.toggle_overlay(buf)

				-- Close mini.diff
				vim.keymap.set("n", "gq", function()
					minidiff.disable(buf)
					vim.notify("Mini.diff closed", vim.log.levels.INFO)
				end, { buffer = buf, desc = "Close mini.diff" })

				-- Accept current hunk (keep current version of hunk)
				vim.keymap.set("n", "ga", function()
					local summary = minidiff.get_buf_data(buf)
					if not summary or not summary.hunks or #summary.hunks == 0 then
						vim.notify("No hunks found", vim.log.levels.WARN)
						return
					end

					local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
					local current_hunk = nil

					for _, hunk in ipairs(summary.hunks) do
						if cursor_line >= hunk.buf_start and cursor_line <= hunk.buf_start + hunk.buf_count - 1 then
							current_hunk = hunk
							break
						end
					end

					if current_hunk then
						-- Get current buffer lines for this hunk
						local current_lines = vim.api.nvim_buf_get_lines(
							buf,
							current_hunk.buf_start - 1,
							current_hunk.buf_start + current_hunk.buf_count - 1,
							false
						)

						-- Update reference text by replacing the hunk portion
						local ref_lines = vim.split(ref_text, "\n")

						-- Remove old reference lines for this hunk
						for i = current_hunk.ref_count, 1, -1 do
							table.remove(ref_lines, current_hunk.ref_start + i - 1)
						end

						-- Insert current buffer lines at the reference position
						for i, line in ipairs(current_lines) do
							table.insert(ref_lines, current_hunk.ref_start + i - 1, line)
						end

						-- Update the reference text
						ref_text = table.concat(ref_lines, "\n")
						minidiff.set_ref_text(buf, ref_text)

						vim.notify(
							string.format(
								"Hunk accepted (lines %d-%d kept as current)",
								current_hunk.buf_start,
								current_hunk.buf_start + current_hunk.buf_count - 1
							),
							vim.log.levels.INFO
						)
					else
						vim.notify("No hunk found at cursor position", vim.log.levels.WARN)
					end
				end, { buffer = buf, desc = "Accept current hunk" })

				-- Reject current hunk (revert hunk to commit version)
				vim.keymap.set("n", "gr", function()
					local summary = minidiff.get_buf_data(buf)
					if not summary or not summary.hunks or #summary.hunks == 0 then
						vim.notify("No hunks found", vim.log.levels.WARN)
						return
					end

					local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
					local current_hunk = nil

					for _, hunk in ipairs(summary.hunks) do
						if cursor_line >= hunk.buf_start and cursor_line <= hunk.buf_start + hunk.buf_count - 1 then
							current_hunk = hunk
							break
						end
					end

					if current_hunk then
						-- Get the reference lines for this hunk
						local ref_lines = vim.split(ref_text, "\n")
						local hunk_ref_lines = {}

						for i = current_hunk.ref_start, current_hunk.ref_start + current_hunk.ref_count - 1 do
							table.insert(hunk_ref_lines, ref_lines[i] or "")
						end

						-- Replace the hunk in current buffer with reference version
						vim.api.nvim_buf_set_lines(
							buf,
							current_hunk.buf_start - 1,
							current_hunk.buf_start + current_hunk.buf_count - 1,
							false,
							hunk_ref_lines
						)

						vim.notify(
							string.format(
								"Hunk rejected (lines %d-%d reverted to commit %s)",
								current_hunk.buf_start,
								current_hunk.buf_start + current_hunk.buf_count - 1,
								commit:sub(1, 7)
							),
							vim.log.levels.INFO
						)
					else
						vim.notify("No hunk found at cursor position", vim.log.levels.WARN)
					end
				end, { buffer = buf, desc = "Reject current hunk" })

				vim.notify(
					"Comparing with commit " .. commit:sub(1, 7) .. " | ga=accept hunk, gr=reject hunk, gq=close",
					vim.log.levels.INFO
				)
			end)
		end
	)
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

				M.setup_minidiff_for_selection(commit, start_line, end_line)
			end,
		},
	})
end

function M.setup_minidiff_for_selection(commit, start_line, end_line)
	local minidiff = require("mini.diff")

	local buf = vim.api.nvim_get_current_buf()
	local file_path = vim.api.nvim_buf_get_name(buf)

	if file_path == "" then
		vim.notify("No file in current buffer", vim.log.levels.ERROR)
		return
	end

	-- Reset mini.diff state
	if not M.reset_minidiff(buf) then
		vim.notify("mini.diff not available", vim.log.levels.ERROR)
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

				local ref_text = result.stdout or ""
				local ref_lines = vim.split(ref_text, "\n")

				-- Get current buffer content
				local current_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

				-- Create modified reference: use current content but replace selected region with commit version
				local modified_ref_lines = vim.deepcopy(current_lines)
				for i = start_line, end_line do
					if ref_lines[i] then
						modified_ref_lines[i] = ref_lines[i]
					end
				end

				-- Set up mini.diff inline on current buffer
				local modified_ref_text = table.concat(modified_ref_lines, "\n")
				minidiff.set_ref_text(buf, modified_ref_text)
				minidiff.toggle_overlay(buf)

				-- Close mini.diff for selection
				vim.keymap.set("n", "gq", function()
					minidiff.disable(buf)
					vim.notify("Selection diff closed", vim.log.levels.INFO)
				end, { buffer = buf, desc = "Close selection diff" })

				-- Accept selection (keep current version in selected region)
				vim.keymap.set("n", "ga", function()
					local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
					if cursor_line >= start_line and cursor_line <= end_line then
						-- Get current buffer lines for selected region
						local current_selected_lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)

						-- Update the reference text to match current buffer in selected region
						local updated_ref_lines = vim.deepcopy(modified_ref_lines)
						for i = start_line, end_line do
							local line_index = i - start_line + 1
							if current_selected_lines[line_index] then
								updated_ref_lines[i] = current_selected_lines[line_index]
							end
						end

						-- Update the reference text
						local updated_ref_text = table.concat(updated_ref_lines, "\n")
						minidiff.set_ref_text(buf, updated_ref_text)

						vim.notify(
							string.format("Selection (lines %d-%d) kept as current", start_line, end_line),
							vim.log.levels.INFO
						)
					else
						vim.notify(
							"Cursor not in selected region (lines " .. start_line .. "-" .. end_line .. ")",
							vim.log.levels.WARN
						)
					end
				end, { buffer = buf, desc = "Accept selection" })

				-- Reject selection (revert selected region to commit version)
				vim.keymap.set("n", "gr", function()
					local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
					if cursor_line >= start_line and cursor_line <= end_line then
						-- Replace selected lines with commit version
						local commit_lines = {}
						for i = start_line, end_line do
							table.insert(commit_lines, ref_lines[i] or "")
						end

						vim.api.nvim_buf_set_lines(buf, start_line - 1, end_line, false, commit_lines)

						vim.notify(
							string.format(
								"Selection (lines %d-%d) reverted to commit %s",
								start_line,
								end_line,
								commit:sub(1, 7)
							),
							vim.log.levels.INFO
						)
					else
						vim.notify(
							"Cursor not in selected region (lines " .. start_line .. "-" .. end_line .. ")",
							vim.log.levels.WARN
						)
					end
				end, { buffer = buf, desc = "Reject selection" })

				vim.notify(
					string.format(
						"Comparing lines %d-%d with commit %s | ga=keep current, gr=revert to commit, gq=close",
						start_line,
						end_line,
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

	-- Use git log to find all commits that modified this file, showing short hash
	local cmd = create_colorized_git_log_cmd(
		string.format(
			"git log --color=always --no-abbrev-commit --pretty=format:'%%C(blue)%%h%%C(reset) %%C(green)%%ad%%C(reset) %%s %%C(red)%%an%%C(reset)' --date=format:'%%d/%%m/%%Y' --follow %s",
			vim.fn.shellescape(relative_path)
		)
	)

	fzf.git_commits({
		prompt = string.format("Commits that modified %s: ", vim.fn.fnamemodify(file_path, ":t")),
		cmd = cmd,
		fzf_opts = {
			["--header"] = ":: File history :: ENTER=copy short hash",
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
	M.validate_commit(commit, function()
		vim.cmd("DiffviewOpen " .. commit .. "^.." .. commit)
		vim.notify("Showing changes in commit " .. commit:sub(1, 7), vim.log.levels.INFO)
	end)
end

function M.reset_minidiff(buf)
	local has_minidiff, minidiff = pcall(require, "mini.diff")
	if not has_minidiff then
		return false
	end

	-- Disable any existing mini.diff on this buffer
	minidiff.disable(buf)

	-- Clear any existing overlays
	if minidiff.get_buf_data and minidiff.get_buf_data(buf) then
		-- Force clear the overlay
		vim.schedule(function()
			minidiff.toggle_overlay(buf) -- Turn off if on
			minidiff.toggle_overlay(buf) -- Turn back on
		end)
	end

	return true
end

function M.setup()
	vim.keymap.set("n", "<leader>g2", M.git_compare_commits, { desc = "Git Compare" })
	vim.keymap.set("n", "<leader>g3", M.compare_with_minidiff, { desc = "Git Mini Diff" })
	vim.keymap.set("v", "<leader>g3", M.compare_selected_with_minidiff, { desc = "Git Mini Diff Selection" })
end

return M
