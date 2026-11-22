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

-- Strip ANSI escape sequences
local function strip_ansi(str)
	return (str:gsub("\27%[[%d;]*m", ""))
end

-- Extract a clean file path from a plain path or fzf-lua formatted entry
local function extract_path(raw_entry, fzf_opts)
	if not raw_entry or raw_entry == "" then
		return nil
	end

	-- Fast path: already a valid filesystem path (e.g. from buffer list or plain paths)
	if vim.uv.fs_stat(raw_entry) then
		return raw_entry
	end

	-- Use fzf-lua's parser when available (handles icons, git status, formatters with fzf_opts)
	local ok, fzf_path = pcall(require, "fzf-lua.path")
	if ok then
		local file = fzf_path.entry_to_file(raw_entry, fzf_opts)
		if file then
			if file.bufnr and vim.api.nvim_buf_is_valid(file.bufnr) then
				local bufname = vim.api.nvim_buf_get_name(file.bufnr)
				if bufname ~= "" then
					return bufname
				end
			end
			if file.path and file.path ~= "" and file.path ~= "<none>" then
				if vim.uv.fs_stat(file.path) or fzf_opts then
					return file.path
				end
			end
		end
	end

	-- Handle fzf-lua path.filename_first / path.dirname_first without fzf_opts
	-- These formatters separate filename and directory with <Tab>, en-space (U+2002), or NBSP (U+00A0)
	local cleaned = vim.trim(strip_ansi(raw_entry))
	for _, sep in ipairs({ "\t", "\226\128\130", "\194\160" }) do
		local first, rest = cleaned:match("^(.-)" .. sep .. "+(.+)$")
		if first and rest then
			-- Strip leading git status / devicon prefix from the first segment
			local clean_first = vim.trim(first):match("([^%s]+)$") or vim.trim(first)
			local clean_rest = vim.trim(rest):gsub("/+$", "")
			if clean_first ~= "" and clean_rest ~= "" then
				-- path.filename_first: "<file> <dir>"
				local as_filename_first = clean_rest .. "/" .. clean_first
				if vim.uv.fs_stat(as_filename_first) then
					return as_filename_first
				end
				-- path.dirname_first: "<dir> <file>"
				local as_dirname_first = clean_first:gsub("/+$", "") .. "/" .. clean_rest
				if vim.uv.fs_stat(as_dirname_first) then
					return as_dirname_first
				end
				return as_filename_first
			end
		end
	end

	-- Fallback: take the last whitespace-delimited token (strips git status / icon prefixes)
	local token = cleaned:match("([^%s]+)%s*$")
	return token ~= "" and token or nil
end

-- Copies filenames to clipboard with smart path shortening
function M.copy_filenames_to_clipboard(selection, options)
	options = options or {}
	local include_current = options.include_current ~= false -- default true
	local prefix = options.prefix or "- "
	local header = options.header ~= nil and options.header or "Context: "
	local fzf_opts = options.fzf_opts

	if not selection or #selection == 0 then
		if not include_current then
			vim.notify("No files selected.", vim.log.levels.WARN)
			return
		end
	end

	local filenames = {}
	local seen = {}

	local function add_path(path)
		if not path or path == "" then
			return
		end
		local entry = prefix .. M.create_short_path(path)
		if not seen[entry] then
			seen[entry] = true
			table.insert(filenames, entry)
		end
	end

	-- Add current buffer if requested
	if include_current then
		local current_bufnr = (fzf_opts and fzf_opts.__CTX and fzf_opts.__CTX.bufnr) or vim.api.nvim_get_current_buf()
		local current_bufname = vim.api.nvim_buf_get_name(current_bufnr)
		add_path(current_bufname)
	end

	-- Add selected files
	if selection then
		for _, raw_entry in ipairs(selection) do
			add_path(extract_path(raw_entry, fzf_opts))
		end
	end

	if #filenames == 0 then
		vim.notify("No files to copy", vim.log.levels.WARN)
		return
	end

	local body = table.concat(filenames, "\n")
	local result = header ~= "" and (header .. "\n" .. body) or body
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
		local bufnr = tonumber(selected:match("(%d+)%]"))
		if bufnr then
			local bufname = vim.api.nvim_buf_get_name(bufnr)
			if bufname and bufname ~= "" then
				table.insert(file_paths, bufname)
			end
		end
	end

	M.copy_filenames_to_clipboard(file_paths, options)
end

return M
