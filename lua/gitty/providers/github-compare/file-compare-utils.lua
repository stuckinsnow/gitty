local M = {}

local fzf = require("fzf-lua")

function M.compare_json_files()
	-- Get list of open buffers
	local buffers = vim.api.nvim_list_bufs()
	local file_buffers = {}

	for _, buf in ipairs(buffers) do
		if vim.api.nvim_buf_is_loaded(buf) then
			local name = vim.api.nvim_buf_get_name(buf)
			local buftype = vim.bo[buf].buftype
			-- Accept only real files (not scratch buffers, terminals, etc.)
			if name ~= "" and buftype == "" then
				table.insert(file_buffers, {
					bufnr = buf,
					name = name,
					display = vim.fn.fnamemodify(name, ":~:."),
				})
			end
		end
	end

	if #file_buffers == 0 then
		vim.notify("No files are currently open", vim.log.levels.WARN)
		return
	end

	if #file_buffers == 1 then
		vim.notify("Only one file is open. Please open another file to compare.", vim.log.levels.WARN)
		return
	end

	-- Select two files with multi-select
	local buffer_list = {}
	for _, buf_info in ipairs(file_buffers) do
		table.insert(buffer_list, buf_info.display)
	end

	fzf.fzf_exec(buffer_list, {
		prompt = "Select two files to compare: ",
		fzf_args = "--multi",
		file_icons = false,
		fzf_opts = {
			["--header"] = ":: Use TAB to select two files, then ENTER ::",
		},
		actions = {
			["default"] = function(selected)
				if not selected or #selected ~= 2 then
					vim.notify("Please select exactly two files (use TAB to multi-select)", vim.log.levels.WARN)
					return
				end

				local file1_info = nil
				local file2_info = nil

				for _, buf_info in ipairs(file_buffers) do
					if buf_info.display == selected[1] then
						file1_info = buf_info
					elseif buf_info.display == selected[2] then
						file2_info = buf_info
					end
				end

				if not file1_info or not file2_info then
					vim.notify("Failed to find selected buffers", vim.log.levels.ERROR)
					return
				end

				M.open_json_diff(file1_info.name, file2_info.name)
			end,
		},
	})
end

function M.open_json_diff(file1, file2)
	-- Expand to absolute paths if needed
	file1 = vim.fn.fnamemodify(file1, ":p")
	file2 = vim.fn.fnamemodify(file2, ":p")

	-- Check if files exist
	if vim.fn.filereadable(file1) == 0 then
		vim.notify(string.format("File not found: %s", file1), vim.log.levels.ERROR)
		return
	end
	if vim.fn.filereadable(file2) == 0 then
		vim.notify(string.format("File not found: %s", file2), vim.log.levels.ERROR)
		return
	end

	-- Create new tab for clean diff view
	vim.cmd("tabnew")

	-- Load first file in current window
	vim.cmd("edit " .. vim.fn.fnameescape(file1))
	local buf1 = vim.api.nvim_get_current_buf()
	local win1 = vim.api.nvim_get_current_win()

	-- Create vertical split and load second file
	vim.cmd("vsplit " .. vim.fn.fnameescape(file2))
	local buf2 = vim.api.nvim_get_current_buf()
	local win2 = vim.api.nvim_get_current_win()

	-- Enable diff mode for both windows
	vim.wo[win1].diff = true
	vim.wo[win2].diff = true

	-- Set better diff options for JSON
	vim.opt_local.diffopt:append("algorithm:patience")
	vim.opt_local.diffopt:append("indent-heuristic")

	-- Lock scrolling together (scrollbind)
	vim.wo[win1].scrollbind = true
	vim.wo[win2].scrollbind = true

	-- Sync cursor movement between windows
	vim.wo[win1].cursorbind = true
	vim.wo[win2].cursorbind = true

	-- Set window titles
	vim.wo[win1].winbar = "%#GittyCurrentTitle#" .. vim.fn.fnamemodify(file1, ":t")
	vim.wo[win2].winbar = "%#GittyBranchTitle#" .. vim.fn.fnamemodify(file2, ":t")

	-- Set up keymaps
	local function close_diff()
		-- Turn off diff mode
		vim.wo[win1].diff = false
		vim.wo[win2].diff = false

		-- Clear window titles
		vim.wo[win1].winbar = ""
		vim.wo[win2].winbar = ""

		-- Close the tab
		vim.cmd("tabclose")
	end

	-- Add keymaps to both buffers
	vim.keymap.set("n", "<leader>q", close_diff, { buffer = buf1, desc = "Close diff" })
	vim.keymap.set("n", "<leader>q", close_diff, { buffer = buf2, desc = "Close diff" })

	-- Add keymap to navigate diffs
	vim.keymap.set("n", "]c", "]c", { buffer = buf1, desc = "Next diff" })
	vim.keymap.set("n", "[c", "[c", { buffer = buf1, desc = "Previous diff" })
	vim.keymap.set("n", "]c", "]c", { buffer = buf2, desc = "Next diff" })
	vim.keymap.set("n", "[c", "[c", { buffer = buf2, desc = "Previous diff" })

	vim.notify(
		string.format(
			"Comparing files | ]c=next diff | [c=prev diff | <leader>q=close\n%s vs %s",
			vim.fn.fnamemodify(file1, ":t"),
			vim.fn.fnamemodify(file2, ":t")
		),
		vim.log.levels.INFO
	)
end

return M
