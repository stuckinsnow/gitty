local M = {}

function M.copy_blame_commit_hash_for_current_line()
	local file = vim.api.nvim_buf_get_name(0)
	if file == "" then
		vim.notify("No file in current buffer", vim.log.levels.ERROR)
		return
	end

	-- Check if file is in a git repository
	local git_dir = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("%s+", "")
	if git_dir == "" then
		vim.notify("Not in a git repository", vim.log.levels.ERROR)
		return
	end

	local line = vim.api.nvim_win_get_cursor(0)[1]
	local relative_path = vim.fn.fnamemodify(file, ":~:.")
	local cmd =
		string.format("git blame -L %d,%d --porcelain --abbrev=7 %s", line, line, vim.fn.shellescape(relative_path))

	local handle = io.popen(cmd)
	local result = handle and handle:read("*a") or ""
	if handle then
		handle:close()
	end

	if result == "" then
		vim.notify("No blame information found for line " .. line, vim.log.levels.ERROR)
		return
	end

	-- Parse the blame output to get the commit hash
	local hash = result:match("^(%w+)")
	if hash then
		vim.fn.setreg("+", hash)
		vim.notify("Blame commit hash for line " .. line .. ": " .. hash, vim.log.levels.INFO)
	else
		vim.notify("Failed to extract commit hash from blame output", vim.log.levels.ERROR)
	end
end

return M
