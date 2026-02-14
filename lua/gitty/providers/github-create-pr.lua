local M = {}
local github_utils = require("gitty.utilities.github-utils")
local fzf = require("fzf-lua")

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

	fzf.fzf_exec(branches, {
		prompt = "Select target branch> ",
		winopts = {
			width = 0.6,
			height = 0.4,
		},
		actions = {
			["default"] = function(selected)
				local target_branch = selected[1]
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
				fzf.fzf_exec({ "AI-generated", "Manual" }, {
					prompt = "Description type> ",
					winopts = {
						width = 0.3,
						height = 0.2,
					},
					actions = {
						["default"] = function(desc_selected)
							local desc_type = desc_selected[1]
							if not desc_type then
								vim.notify("PR creation cancelled", vim.log.levels.INFO)
								return
							end

							-- Always create the PR window first
							local win = M.create_pr_window(current_branch, target_branch, title)

							if desc_type == "AI-generated" then
								-- Generate PR description via opencode
								vim.notify("Generating AI description...", vim.log.levels.INFO)
								local diff_summary = vim.fn.system("git diff --stat HEAD~5..HEAD"):gsub("\r", "")
								local commit_msgs = vim.fn.system("git log --oneline -n 10 --no-merges"):gsub("\r", "")
								local prompt = string.format(
									"Generate a concise PR description (markdown) for branch %s -> %s.\n\nRecent commits:\n%s\n\nDiff summary:\n%s",
									current_branch, target_branch, commit_msgs, diff_summary
								)
								local ai = require("gitty.utilities.ai")
								ai.run(prompt, function(result, err)
									if err then
										vim.notify("AI description failed: " .. err, vim.log.levels.ERROR)
										return
									end
									if vim.api.nvim_buf_is_valid(buf) then
										-- Find line 13 (description area) and replace
										local lines = vim.split(result, "\n")
										vim.api.nvim_buf_set_lines(buf, 13, 14, false, lines)
									end
								end)
							end
						end
					}
				})
			end
		}
	})
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
	local win, buf = github_utils.create_side_buffer(prefix, 0.4, "markdown")

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

	vim.api.nvim_win_set_cursor(win, { 12, 0 })
	vim.cmd("startinsert")

	local function submit_pr()
		fzf.fzf_exec({ "Web", "CLI" }, {
			prompt = "Create PR using Web or CLI> ",
			winopts = {
				width = 0.35,
				height = 0.2,
			},
			actions = {
				["default"] = function(method_selected)
					local option = method_selected[1]
					if not option then
						print("PR submission cancelled")
						return
					end

					fzf.fzf_exec({ "Yes", "No" }, {
						prompt = "Create this PR> ",
						winopts = {
							width = 0.25,
							height = 0.15,
						},
						actions = {
							["default"] = function(confirm_selected)
								local choice = confirm_selected[1]
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
							end
						}
					})
				end
			}
		})
	end

	local function cancel_pr()
		fzf.fzf_exec({ "Yes", "No" }, {
			prompt = "Quit without creating PR> ",
			winopts = {
				width = 0.3,
				height = 0.15,
			},
			actions = {
				["default"] = function(selected)
					local choice = selected[1]
					if not choice or choice == "No" then
						print("Continuing with PR creation")
						return
					end
					print("PR creation cancelled")
					vim.api.nvim_win_close(win, true)
				end
			}
		})
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
