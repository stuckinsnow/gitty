local M = {}
local github_utils = require("gitty.utilities.github-utils")

function M.create_new_issue()
	local title = vim.fn.input("Issue title: ")
	if not title or title:match("^%s*$") then
		vim.notify("Issue creation cancelled - no title provided", vim.log.levels.INFO)
		return
	end

	title = vim.trim(title)

	-- Now open the side window for body editing
	local prefix = "new_issue"
	-- Use the utility function instead of local duplicate
	github_utils.close_existing_buffer(prefix)

	-- Create right-aligned vertical split
	vim.cmd("rightbelow vertical split")
	local win = vim.api.nvim_get_current_win()

	-- Set window width to 40% of screen
	local width = math.floor(vim.o.columns * 0.4)
	vim.api.nvim_win_set_width(win, width)

	-- Create and setup buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, prefix)
	vim.bo[buf].filetype = "markdown"

	-- Set initial content with the provided title
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
		"# " .. title,
		"",
		"## Description",
		"",
		"Write your issue description here",
		"",
		"## Steps to Reproduce",
		"",
		"1. ",
		"",
		"## Expected Behavior",
		"",
		"",
		"",
		"## Actual Behavior",
		"",
		"",
	})

	vim.bo[buf].modifiable = true
	vim.api.nvim_win_set_buf(win, buf)

	-- Set window options
	vim.wo[win].signcolumn = "no"
	vim.wo[win].wrap = true

	-- Position cursor at the description section (line 5)
	vim.api.nvim_win_set_cursor(win, { 5, 0 })

	-- Enter insert mode
	vim.cmd("startinsert")

	local function submit_issue()
		vim.ui.select({ "Yes", "No" }, {
			prompt = "Create this issue?",
			format_item = function(item)
				return item
			end,
		}, function(choice)
			if not choice or choice == "No" then
				print("Issue submission cancelled")
				return
			end

			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			-- Extract body content (everything after the title line)
			local body_lines = {}
			for i = 2, #lines do
				table.insert(body_lines, lines[i])
			end
			local body = table.concat(body_lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")

			vim.api.nvim_win_close(win, true)
			print("Creating issue...")

			local cmd = { "gh", "issue", "create", "--title", title }
			if body and body:match("%S") then
				table.insert(cmd, "--body")
				table.insert(cmd, body)
			end

			vim.system(cmd, { text = true }, function(result)
				vim.schedule(function()
					if result.code == 0 then
						print("✓ Issue created successfully: " .. title)
						vim.cmd("FzfGithubIssues")
					else
						print("✗ Failed to create issue:")
						print(result.stderr or "Unknown error")
					end
				end)
			end)
		end)
	end

	local function cancel_issue()
		vim.ui.select({ "Yes", "No" }, {
			prompt = "Quit without creating issue?",
			format_item = function(item)
				return item
			end,
		}, function(choice)
			if not choice or choice == "No" then
				print("Continuing with issue creation")
				return
			end
			print("Issue creation cancelled")
			vim.api.nvim_win_close(win, true)
		end)
	end

	-- Set up keybindings
	vim.keymap.set("n", "<CR>", submit_issue, { buffer = buf, nowait = true, desc = "Submit issue" })
	vim.keymap.set("n", "<leader>q", cancel_issue, { buffer = buf, nowait = true, desc = "Cancel issue" })
	vim.keymap.set("i", "<C-s>", function()
		vim.cmd("stopinsert")
		submit_issue()
	end, { buffer = buf, nowait = true, desc = "Submit issue" })
end

-- Function to register the command
function M.fzf_create_issue()
	vim.api.nvim_create_user_command("FzfCreateIssue", function()
		M.create_new_issue()
	end, {})
end

function M.setup()
	M.fzf_create_issue()
end

return M
