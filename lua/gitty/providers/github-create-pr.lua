local M = {}
local github_utils = require("gitty.utilities.github-utils")

function M.create_new_pr()
	local current_branch = vim.fn.system("git rev-parse --abbrev-ref HEAD"):gsub("%s+", "")

	-- Fetch remote branches for selection
	local branches = {}
	local branch_output = vim.fn.system("git branch -r"):gsub("\r", "")
	for branch in branch_output:gmatch("[^\n]+") do
		branch = branch:gsub("^%s+", ""):gsub("%s+$", ""):gsub("origin/", "")
		if branch ~= "" then
			table.insert(branches, branch)
		end
	end

	vim.ui.select(branches, {
		prompt = "Select target branch:",
		format_item = function(branch)
			return branch
		end,
	}, function(target_branch)
		if not target_branch or target_branch:match("^%s*$") then
			vim.notify("PR creation cancelled - no target branch selected", vim.log.levels.INFO)
			return
		end

		target_branch = vim.trim(target_branch)

		-- Get PR title first
		local title = vim.fn.input("PR title: ")
		if not title or title == "" then
			vim.notify("PR creation cancelled - no title provided", vim.log.levels.ERROR)
			return
		end

		-- Ask for description type
		vim.ui.select({ "AI-generated", "Manual" }, {
			prompt = "Description type:",
			format_item = function(item)
				return item
			end,
		}, function(desc_type)
			if not desc_type then
				vim.notify("PR creation cancelled", vim.log.levels.INFO)
				return
			end

			-- Always create the PR window first
			local win = M.create_pr_window(current_branch, target_branch, title)

			if desc_type == "AI-generated" then
				-- Position cursor in description area and run CodeCompanion
				vim.defer_fn(function()
					vim.api.nvim_win_set_cursor(win, { 13, 0 }) -- Line with "Write your PR description here"
					vim.cmd("normal! V") -- Select the line
					vim.notify("Generating AI description...", vim.log.levels.INFO)
					vim.cmd("CodeCompanion /pr")
				end, 100)
			end
		end)
	end)
end

function M.create_pr_window(current_branch, target_branch, title, initial_description)
	-- Fetch commit messages for pre-filled description
	local commit_msgs = vim.fn.system("git log --oneline -n 5"):gsub("\r", "")
	local commit_lines = {}
	for line in commit_msgs:gmatch("[^\n]+") do
		table.insert(commit_lines, "- " .. line)
	end

	-- Open side window for PR description
	local prefix = "new_pr"
	github_utils.close_existing_buffer(prefix)

	vim.cmd("rightbelow vertical split")
	local win = vim.api.nvim_get_current_win()

	local width = math.floor(vim.o.columns * 0.4)
	vim.api.nvim_win_set_width(win, width)

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, prefix)
	vim.bo[buf].filetype = "markdown"

	local description_text = initial_description or "Write your PR description here"

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
		"# Pull Request",
		"",
		"## Title",
		title,
		"",
		"## Source Branch",
		current_branch,
		"",
		"## Target Branch",
		target_branch,
		"",
		"## Description",
		"",
		description_text,
		"",
		"## Commits",
		"",
		unpack(commit_lines),
	})

	vim.bo[buf].modifiable = true
	vim.api.nvim_win_set_buf(win, buf)

	vim.wo[win].signcolumn = "no"
	vim.wo[win].wrap = true

	vim.api.nvim_win_set_cursor(win, { 12, 0 })
	vim.cmd("startinsert")

	local function submit_pr()
		vim.ui.select({ "Web", "CLI" }, {
			prompt = "Create PR using Web or CLI?",
			format_item = function(item)
				return item
			end,
		}, function(option)
			if not option then
				print("PR submission cancelled")
				return
			end

			vim.ui.select({ "Yes", "No" }, {
				prompt = "Create this PR?",
				format_item = function(item)
					return item
				end,
			}, function(choice)
				if not choice or choice == "No" then
					print("PR submission cancelled")
					return
				end

				local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
				local body_lines = {}
				for i = 12, #lines do
					table.insert(body_lines, lines[i])
				end
				local body = table.concat(body_lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")

				vim.api.nvim_win_close(win, true)
				print("Creating PR...")

				local cmd =
					{ "gh", "pr", "create", "--base", target_branch, "--head", current_branch, "--title", title }
				if body and body:match("%S") then
					table.insert(cmd, "--body")
					table.insert(cmd, body)
				end

				if option == "Web" then
					table.insert(cmd, "--web")
				end

				vim.system(cmd, { text = true }, function(result)
					vim.schedule(function()
						if result.code == 0 then
							if option == "Web" then
								print("✓ PR creation initiated in browser")
							else
								print("✓ PR created successfully")
								vim.cmd("FzfGithubPrs")
							end
						else
							print("✗ Failed to create PR:")
							print(result.stderr or "Unknown error")
						end
					end)
				end)
			end)
		end)
	end

	local function cancel_pr()
		vim.ui.select({ "Yes", "No" }, {
			prompt = "Quit without creating PR?",
			format_item = function(item)
				return item
			end,
		}, function(choice)
			if not choice or choice == "No" then
				print("Continuing with PR creation")
				return
			end
			print("PR creation cancelled")
			vim.api.nvim_win_close(win, true)
		end)
	end

	-- Keybindings
	vim.keymap.set("n", "<CR>", submit_pr, { buffer = buf, nowait = true, desc = "Submit PR" })
	vim.keymap.set("n", "<leader>q", cancel_pr, { buffer = buf, nowait = true, desc = "Cancel PR" })
	vim.keymap.set("i", "<C-s>", function()
		vim.cmd("stopinsert")
		submit_pr()
	end, { buffer = buf, nowait = true, desc = "Submit PR" })

	return win, buf
end

function M.fzf_create_pr()
	vim.api.nvim_create_user_command("FzfCreatePr", function()
		M.create_new_pr()
	end, {})
end

function M.setup()
	M.fzf_create_pr()
end

return M
