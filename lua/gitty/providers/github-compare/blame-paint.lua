local M = {}

local ns = vim.api.nvim_create_namespace("gitty_blame_paint")

local function git_root_for_buf()
	local dir = vim.fn.expand("%:p:h")
	local out = vim.fn.system({ "git", "-C", dir, "rev-parse", "--show-toplevel" }):gsub("%s+", "")
	return out ~= "" and out or nil
end

local function blame_lines_for_commit(root, rel_path, commit_set)
	local out = vim.fn.system({ "git", "-C", root, "blame", "--porcelain", "--", rel_path })
	if vim.v.shell_error ~= 0 then return {} end

	local lines = {}
	for line in out:gmatch("[^\n]+") do
		local hash, lnum = line:match("^(%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x) %d+ (%d+)")
		if hash and commit_set[hash] then
			table.insert(lines, tonumber(lnum))
		end
	end
	table.sort(lines)
	return lines
end

local function collapse_ranges(sorted_lines)
	if #sorted_lines == 0 then return {} end
	local ranges = {}
	local s, e = sorted_lines[1], sorted_lines[1]
	for i = 2, #sorted_lines do
		if sorted_lines[i] == e + 1 then
			e = sorted_lines[i]
		else
			table.insert(ranges, { s, e })
			s, e = sorted_lines[i], sorted_lines[i]
		end
	end
	table.insert(ranges, { s, e })
	return ranges
end

local function paint_ranges(bufnr, ranges)
	local max = vim.api.nvim_buf_line_count(bufnr)
	for _, r in ipairs(ranges) do
		for row = r[1] - 1, math.min(r[2] - 1, max - 1) do
			local total = r[2] - r[1] + 1
			local sign = total == 1 and "│ "
				or row == r[1] - 1 and "┌ "
				or row == r[2] - 1 and "└ "
				or "│ "
			vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
				line_hl_group = "GittyBlamePaintLine", priority = 100,
			})
			vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
				sign_text = sign, sign_hl_group = "GittyBlamePaintSign", priority = 200,
			})
		end
	end
end

function M.highlight_commit(commits)
	local root = git_root_for_buf()
	if not root then
		vim.notify("Not in a git repo", vim.log.levels.ERROR)
		return
	end

	local commit_set = {}
	for _, short in ipairs(commits) do
		local full = vim.fn.system({ "git", "-C", root, "rev-parse", short }):gsub("%s+", "")
		if full ~= "" then commit_set[full] = true end
	end

	local file_list = {}
	for _, hash in ipairs(commits) do
		local out = vim.fn.system({ "git", "-C", root, "diff-tree", "--no-commit-id", "-r", "--name-only", hash })
		for f in out:gmatch("[^\n]+") do
			if not vim.tbl_contains(file_list, f) and vim.fn.filereadable(root .. "/" .. f) == 1 then
				table.insert(file_list, f)
			end
		end
	end

	if #file_list == 0 then
		vim.notify("No files found for selected commits", vim.log.levels.WARN)
		return
	end

	table.sort(file_list)

	require("fzf-lua").fzf_exec(file_list, {
		cwd = root,
		prompt = "Highlight files> ",
		fzf_args = "--multi",
		fzf_opts = {
			["--header"] = ":: ENTER=highlight selected :: TAB=multi-select ::",
			["--preview"] = "bat --style=numbers --color=always {}"
		},
		actions = {
			["default"] = function(selected)
				if not selected or #selected == 0 then return end
				local chosen = {}
				for _, s in ipairs(selected) do chosen[s] = true end
				M._paint_files(root, chosen, commit_set)
			end,
		},
	})
end

function M._paint_files(root, files, commit_set)
	M.clear()
	local total_lines, file_count = 0, 0
	local to_paint = {}

	for rel_path in pairs(files) do
		local full_path = root .. "/" .. rel_path
		local lines = blame_lines_for_commit(root, rel_path, commit_set)
		to_paint[#to_paint + 1] = { path = full_path, lines = lines }
	end

	-- Open all files first so edit doesn't wipe extmarks
	for _, f in ipairs(to_paint) do
		local bufnr = vim.fn.bufnr(f.path)
		if bufnr == -1 then
			bufnr = vim.fn.bufadd(f.path)
			vim.fn.bufload(bufnr)
		end
		vim.bo[bufnr].buflisted = true
		f.bufnr = bufnr
	end

	-- Now paint after all buffers are loaded
	for _, f in ipairs(to_paint) do
		if #f.lines > 0 then
			paint_ranges(f.bufnr, collapse_ranges(f.lines))
			total_lines = total_lines + #f.lines
			file_count = file_count + 1
		end
		-- Ensure sign column is visible in all windows showing this buffer
		for _, win in ipairs(vim.fn.win_findbuf(f.bufnr)) do
			vim.wo[win].signcolumn = "yes"
		end
	end

	-- Open files in current window without reloading
	for _, f in ipairs(to_paint) do
		vim.cmd("buffer " .. f.bufnr)
	end
	if #to_paint > 0 then
		vim.cmd("buffer " .. to_paint[1].bufnr)
		if #to_paint[1].lines > 0 then
			vim.api.nvim_win_set_cursor(0, { to_paint[1].lines[1], 0 })
		end
	end

	vim.notify(string.format("Highlighted %d lines across %d file(s)", total_lines, file_count), vim.log.levels.INFO)
end

function M.clear()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
		end
	end
end

function M.pick()
	local fzf = require("fzf-lua")
	local picker_utils = require("gitty.providers.github-compare.picker-utils")

	local root = git_root_for_buf()
	if not root then
		vim.notify("Not in a git repo", vim.log.levels.ERROR)
		return
	end

	local branch = vim.fn.system({ "git", "-C", root, "branch", "--show-current" }):gsub("%s+", "")
	local git_log_cmd = picker_utils.create_themed_git_log_cmd(branch, 50)

	fzf.fzf_exec(git_log_cmd, {
		cwd = root,
		prompt = "Highlight commit> ",
		fzf_args = "--multi",
		fzf_opts = {
			["--header"] = ":: ENTER=highlight :: TAB=multi-select :: CTRL-X=clear ::",
			["--preview"] = picker_utils.create_commit_preview_command(),
		},
		actions = {
			["default"] = function(selected)
				if not selected or #selected == 0 then return end
				local commits = {}
				for _, sel in ipairs(selected) do
					local hash = sel:match("^(%w+)")
					if hash then table.insert(commits, hash) end
				end
				if #commits > 0 then M.highlight_commit(commits) end
			end,
			["ctrl-x"] = function()
				M.clear()
				vim.notify("Blame paint cleared", vim.log.levels.INFO)
			end,
		},
	})
end

return M
