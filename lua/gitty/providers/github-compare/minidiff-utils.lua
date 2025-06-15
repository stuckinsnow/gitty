local M = {}

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

return M
