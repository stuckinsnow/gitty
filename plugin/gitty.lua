if vim.g.loaded_gitty == 1 then
	return
end
vim.g.loaded_gitty = 1

-- Create user commands
vim.api.nvim_create_user_command("GittySetup", function(opts)
	require("gitty").setup(opts.args and vim.fn.json_decode(opts.args) or {})
end, { nargs = "?" })

-- Optional: Auto-setup with default config
-- require("gitty").setup()
