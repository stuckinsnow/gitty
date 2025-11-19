local M = {}

local fzf = require("fzf-lua")

function M.compare_json_files()
	-- Get list of open buffers
	local buffers = vim.api.nvim_list_bufs()
	local json_buffers = {}

	for _, buf in ipairs(buffers) do
		if vim.api.nvim_buf_is_loaded(buf) then
			local name = vim.api.nvim_buf_get_name(buf)
			if name ~= "" and name:match("%.json$") then
				table.insert(json_buffers, {
					bufnr = buf,
					name = name,
					display = vim.fn.fnamemodify(name, ":~:."),
				})
			end
		end
	end

	if #json_buffers == 0 then
		vim.notify("No JSON files are currently open", vim.log.levels.WARN)
		return
	end

	if #json_buffers == 1 then
		vim.notify("Only one JSON file is open. Please open another JSON file to compare.", vim.log.levels.WARN)
		return
	end

	-- Step 1: Select first JSON file from open buffers
	local buffer_list = {}
	for _, buf_info in ipairs(json_buffers) do
		table.insert(buffer_list, buf_info.display)
	end

	fzf.fzf_exec(buffer_list, {
		prompt = "Select first JSON file: ",
		fzf_opts = {
			["--header"] = ":: Select first JSON file from open buffers ::",
		},
		actions = {
			["default"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				local file1_display = selected[1]
				local file1_info = nil
				for _, buf_info in ipairs(json_buffers) do
					if buf_info.display == file1_display then
						file1_info = buf_info
						break
					end
				end

				if not file1_info then
					vim.notify("Failed to find selected buffer", vim.log.levels.ERROR)
					return
				end

				-- Step 2: Select second JSON file
				M.select_second_json_file(file1_info, json_buffers)
			end,
		},
	})
end

function M.select_second_json_file(file1_info, json_buffers)
	-- Filter out the first file from the list
	local buffer_list = {}
	for _, buf_info in ipairs(json_buffers) do
		if buf_info.bufnr ~= file1_info.bufnr then
			table.insert(buffer_list, buf_info.display)
		end
	end

	fzf.fzf_exec(buffer_list, {
		prompt = "Select second JSON file: ",
		fzf_opts = {
			["--header"] = string.format(
				":: First file: %s :: Select second JSON file ::",
				vim.fn.fnamemodify(file1_info.name, ":t")
			),
		},
		actions = {
			["default"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				local file2_display = selected[1]
				local file2_info = nil
				for _, buf_info in ipairs(json_buffers) do
					if buf_info.display == file2_display then
						file2_info = buf_info
						break
					end
				end

				if not file2_info then
					vim.notify("Failed to find selected buffer", vim.log.levels.ERROR)
					return
				end

				-- Step 3: Open files in diff view
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
	vim.wo[win1].winbar = "%#GittyCurrentTitle#" .. vim.fn.fnamemodify(file1, ":t") .. " (LEFT)"
	vim.wo[win2].winbar = "%#GittyBranchTitle#" .. vim.fn.fnamemodify(file2, ":t") .. " (RIGHT)"

	-- Set up keymaps
	local function close_json_diff()
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
	vim.keymap.set("n", "<leader>q", close_json_diff, { buffer = buf1, desc = "Close JSON diff" })
	vim.keymap.set("n", "<leader>q", close_json_diff, { buffer = buf2, desc = "Close JSON diff" })

	-- Add keymap to navigate diffs
	vim.keymap.set("n", "]c", "]c", { buffer = buf1, desc = "Next diff" })
	vim.keymap.set("n", "[c", "[c", { buffer = buf1, desc = "Previous diff" })
	vim.keymap.set("n", "]c", "]c", { buffer = buf2, desc = "Next diff" })
	vim.keymap.set("n", "[c", "[c", { buffer = buf2, desc = "Previous diff" })

	vim.notify(
		string.format(
			"Comparing JSON files | ]c=next diff | [c=prev diff | <leader>q=close\n%s vs %s",
			vim.fn.fnamemodify(file1, ":t"),
			vim.fn.fnamemodify(file2, ":t")
		),
		vim.log.levels.INFO
	)
end

return M
