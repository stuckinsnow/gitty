local M = {}

local config = require("gitty.config")

function M.setup(opts)
	opts = opts or {}
	config.setup(opts)

	if not M.check_dependencies() then
		return
	end

	-- Setup all providers
	require("gitty.providers.github-notifications").setup()
	require("gitty.providers.github-prs").setup()
	require("gitty.providers.github-issues").setup()
	require("gitty.providers.github-workflows").setup()
	require("gitty.providers.github-create-pr").setup()
	require("gitty.providers.github-create-issue").setup()
	require("gitty.providers.github-get-log").setup()
	require("gitty.providers.github-compare").setup()
end

-- Direct access functions
M.notifications = function()
	require("gitty.providers.github-notifications").fzf_github_notifications()
end

M.prs = function()
	require("gitty.providers.github-prs").fzf_github_prs()
end

M.issues = function()
	require("gitty.providers.github-issues").fzf_github_issues()
end

M.workflows = function()
	require("gitty.providers.github-workflows").fzf_github_workflows()
end

M.branches = function()
	require("gitty.providers.github-get-log").fzf_github_branches()
end

M.create_pr = function()
	require("gitty.providers.github-create-pr").create_new_pr()
end

M.create_issue = function()
	require("gitty.providers.github-create-issue").create_new_issue()
end

M.compare = function()
	require("gitty.providers.github-compare").git_compare_commits()
end

function M.check_dependencies()
	local dependencies = {
		{ cmd = "gh", name = "GitHub CLI" },
		{ cmd = "fzf", name = "fzf" },
		{ cmd = "git", name = "Git" },
	}

	for _, dep in ipairs(dependencies) do
		if vim.fn.executable(dep.cmd) == 0 then
			vim.notify(dep.name .. " is not installed or not in PATH", vim.log.levels.ERROR)
			return false
		end
	end
	return true
end

return M
