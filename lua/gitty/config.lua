local M = {}

local defaults = {
	-- Add any configuration options here
	spinner_enabled = true,
	preview_width = 0.6,
	preview_height = 0.4,
	split_diff_treesitter_left = true,
	split_diff_treesitter_right = false,
	-- Commit preview options
	show_commit_files_in_preview = true, -- Show files changed in commit preview
	enhanced_commit_preview = true, -- Use enhanced styling (delta + line numbers) in commit preview
}

M.options = {}

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", defaults, opts or {})
end

return M
