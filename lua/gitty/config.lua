local M = {}

local defaults = {
	-- Add any configuration options here
	spinner_enabled = true,
	preview_width = 0.6,
	preview_height = 0.4,
	-- Enable tree-sitter highlighting in split diff windows
	split_diff_treesitter = false,
}

M.options = {}

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", defaults, opts or {})
end

return M
