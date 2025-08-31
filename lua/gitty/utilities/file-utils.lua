local M = {}

-- Creates a shortened path from full path (shows last 3 parts or less)
function M.create_short_path(full_path)
	local relative_path = vim.fn.fnamemodify(full_path, ":.")
	local path_parts = {}
	for part in relative_path:gmatch("[^/]+") do
		table.insert(path_parts, part)
	end

	local short_path
	if #path_parts >= 3 then
		short_path = path_parts[#path_parts - 2] .. "/" .. path_parts[#path_parts - 1] .. "/" .. path_parts[#path_parts]
	elseif #path_parts == 2 then
		short_path = path_parts[#path_parts - 1] .. "/" .. path_parts[#path_parts]
	else
		short_path = path_parts[#path_parts] or relative_path
	end

	return short_path
end

-- Copies filenames to clipboard with smart path shortening
-- For files with display formatting, extracts just the filename
function M.copy_filenames_to_clipboard(selection, options)
	options = options or {}
	local include_current = options.include_current ~= false -- default true
	local prefix = options.prefix or "- "
	local header = options.header or "Context: "

	if not selection or #selection == 0 then
		if not include_current then
			vim.notify("No files selected.", vim.log.levels.WARN)
			return
		end
	end

	local filenames = {}

	-- Add current buffer if requested
	if include_current then
		local current_bufnr = vim.api.nvim_get_current_buf()
		local current_bufname = vim.api.nvim_buf_get_name(current_bufnr)
		if current_bufname and current_bufname ~= "" then
			local short_path = M.create_short_path(current_bufname)
			table.insert(filenames, prefix .. short_path)
		end
	end

	-- Add selected files
	if selection then
		for _, file_path in ipairs(selection) do
			if file_path and file_path ~= "" then
				-- Simple approach: extract filename with dots (like .json, .lua)
				-- This should match actual filenames regardless of git status/icons
				local filename = file_path:match("([%w%-_]+%.[%w]+)")
				
				-- If no extension found, look for the last word that's a valid filename
				if not filename then
					filename = file_path:match("([%w%-_.]+)%s*$")
				end
				
				-- Clean up any remaining whitespace
				if filename then
					filename = filename:gsub("^%s+", ""):gsub("%s+$", "")
					
					if filename ~= "" then
						local entry = prefix .. filename
						-- Avoid duplicates
						if not vim.tbl_contains(filenames, entry) then
							table.insert(filenames, entry)
						end
					end
				end
			end
		end
	end

	if #filenames == 0 then
		vim.notify("No files to copy", vim.log.levels.WARN)
		return
	end

	local result = header .. "\n" .. table.concat(filenames, "\n")
	vim.fn.setreg("+", result)
	vim.notify("Copied " .. #filenames .. " filename(s) to clipboard", vim.log.levels.INFO)
end

-- Specialized version for buffer selection (extracts buffer numbers)
-- This is for compatibility with fzf buffer pickers that return buffer info
function M.copy_buffer_filenames_to_clipboard(selection, options)
	if not selection or #selection == 0 then
		M.copy_filenames_to_clipboard(nil, options)
		return
	end

	local file_paths = {}
	for _, selected in ipairs(selection) do
		local bufnr = selected:match("(%d+)%]")
		if bufnr then
			bufnr = tonumber(bufnr)
			local bufname = vim.api.nvim_buf_get_name(bufnr)
			if bufname and bufname ~= "" then
				table.insert(file_paths, bufname)
			end
		end
	end

	M.copy_filenames_to_clipboard(file_paths, options)
end


return M

