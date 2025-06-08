local M = {}

local defaults = {
	-- Add any configuration options here
	spinner_enabled = true,
	preview_width = 0.6,
	preview_height = 0.4,
}

M.options = {}

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", defaults, opts or {})
end

return M
