local M = {}
function M.fzf_github_notifications()
	-- Registers the :FzfGithubNotifications command to list GitHub notifications.
	vim.api.nvim_create_user_command("FzfGithubNotifications", function()
		require("fzf-lua").fzf_exec("gh notify -s -a -n10", {
			prompt = "GitHub Notifications> ",
			winopts = {
				width = 0.6,
				height = 0.12,
			},
			fzf_opts = {
				["--header"] = "   Age           Repository               Type        #      Reason       Title",
			},
			actions = {
				["default"] = function(selected)
					print("Selected GitHub notification: " .. selected[1])
				end,
			},
		})
	end, {})
end

function M.setup()
	M.fzf_github_notifications()
end

return M
