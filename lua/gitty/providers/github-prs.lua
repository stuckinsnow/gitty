local M = {}
local markdown_utils = require("gitty.utilities.markdown-utils")
local github_utils = require("gitty.utilities.github-utils")

function M.fzf_github_prs()
	-- Registers the :FzfGithubPrs command to list and preview GitHub pull requests.
	vim.api.nvim_create_user_command("FzfGithubPrs", function()
		local spinner_utils = require("gitty.utilities.spinner-utils")
		-- Helper to run a shell command asynchronously and collect output
		local function get_lines_async(cmd, callback)
			vim.system(vim.split(cmd, " "), {
				text = true,
			}, function(result)
				if result.code == 0 then
					local lines = vim.split(result.stdout or "", "\n")
					-- Remove empty last line if present
					if lines[#lines] == "" then
						table.remove(lines, #lines)
					end
					callback(lines)
				else
					callback({})
				end
			end)
		end

		-- Helper to parse JSON with fallback
		local function parse_json(json_str)
			local ok, result
			if vim.json and vim.json.decode then
				ok, result = pcall(vim.json.decode, json_str)
			else
				ok, result = pcall(vim.fn.json_decode, json_str)
			end
			return ok, result
		end

		-- Helper to extract PR number and find matching item
		local function get_pr_info(selected, items)
			local selected_display = selected[1]
			local selected_label =
				selected_display:gsub("\27%[%d+m", ""):gsub("\27%[%d+;%d+m", ""):gsub("\27%[0m", ""):gsub("\27", "")

			for _, item in ipairs(items) do
				local item_label =
					item.display:gsub("\27%[%d+m", ""):gsub("\27%[%d+;%d+m", ""):gsub("\27%[0m", ""):gsub("\27", "")
				if item_label == selected_label then
					local pr_number = item.label:match("^#(%d+):")
					return pr_number, item
				end
			end
			return nil, nil
		end

		-- Helper to open terminal with gh pr diff
		local function open_terminal_diff(pr_number)
			-- Calculate dimensions upfront to avoid accessing vim.o in callbacks
			local width = math.floor(vim.o.columns * 0.9)
			local height = math.floor(vim.o.lines * 0.9)
			local row = math.floor((vim.o.lines - height) / 2)
			local col = math.floor((vim.o.columns - width) / 2)

			-- First check if we can get the PR branch name and if it exists locally
			vim.schedule(function()
				spinner_utils.show_loading("Fetching PR diff...")
			end)

			vim.system({ "gh", "pr", "view", pr_number, "--json", "headRefName" }, {
				text = true,
			}, function(result)
				vim.schedule(function()
					spinner_utils.hide_loading()
				end)
				local cmd
				if result.code == 0 then
					local pr_ok, pr_data = parse_json(result.stdout)
					if pr_ok and pr_data and pr_data.headRefName then
						local remote_branch = "origin/" .. pr_data.headRefName
						-- Check if the remote branch exists locally (async)
						vim.system(
							{ "git", "rev-parse", "--verify", remote_branch },
							{ text = true },
							function(check_result)
								if check_result.code == 0 then
									vim.schedule(function()
										vim.notify("Using local git diff for PR #" .. pr_number, vim.log.levels.INFO)
									end)
									-- Use local git diff if branch exists
									cmd = string.format(
										"git diff HEAD..%s | delta --paging=never --width=%d\n",
										remote_branch,
										width
									)
								else
									vim.schedule(function()
										vim.notify("Using gh pr diff for PR #" .. pr_number, vim.log.levels.WARN)
									end)
									-- Fallback to gh pr diff
									cmd = string.format(
										"gh pr diff %s | delta --paging=never --width=%d\n",
										pr_number,
										width
									)
								end

								vim.schedule(function()
									local buf = vim.api.nvim_create_buf(false, true)
									local win = vim.api.nvim_open_win(buf, true, {
										style = "minimal",
										relative = "editor",
										width = width,
										height = height,
										row = row,
										col = col,
										border = "rounded",
									})

									-- Create a persistent shell that stays open after command completes
									vim.fn.jobstart("sh", {
										term = true,
										on_exit = function()
											if vim.api.nvim_win_is_valid(win) then
												vim.api.nvim_win_close(win, true)
											end
										end,
									})

									vim.api.nvim_chan_send(vim.bo[buf].channel, cmd)
									vim.cmd("stopinsert")

									vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
										noremap = true,
										silent = true,
										callback = function()
											vim.api.nvim_win_close(win, true)
										end,
									})
								end)
							end
						)
					else
						-- Fallback to gh pr diff
						cmd = string.format("gh pr diff %s | delta --paging=never --width=%d\n", pr_number, width)

						vim.schedule(function()
							local buf = vim.api.nvim_create_buf(false, true)
							local win = vim.api.nvim_open_win(buf, true, {
								style = "minimal",
								relative = "editor",
								width = width,
								height = height,
								row = row,
								col = col,
								border = "rounded",
							})

							vim.fn.jobstart("sh", {
								term = true,
								on_exit = function()
									if vim.api.nvim_win_is_valid(win) then
										vim.api.nvim_win_close(win, true)
									end
								end,
							})

							vim.api.nvim_chan_send(vim.bo[buf].channel, cmd)
							vim.cmd("startinsert")

							vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
								noremap = true,
								silent = true,
								callback = function()
									vim.api.nvim_win_close(win, true)
								end,
							})
						end)
					end
				else
					-- Fallback to gh pr diff
					cmd = string.format("gh pr diff %s | delta --paging=never --width=%d\n", pr_number, width)

					vim.schedule(function()
						local buf = vim.api.nvim_create_buf(false, true)
						local win = vim.api.nvim_open_win(buf, true, {
							style = "minimal",
							relative = "editor",
							width = width,
							height = height,
							row = row,
							col = col,
							border = "rounded",
						})

						vim.fn.jobstart("sh", {
							term = true,
							on_exit = function()
								if vim.api.nvim_win_is_valid(win) then
									vim.api.nvim_win_close(win, true)
								end
							end,
						})

						vim.api.nvim_chan_send(vim.bo[buf].channel, cmd)
						vim.cmd("startinsert")

						vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
							noremap = true,
							silent = true,
							callback = function()
								vim.api.nvim_win_close(win, true)
							end,
						})
					end)
				end
			end)
		end

		-- Helper to get PR diff and copy to system clipboard
		local function copy_pr_commands(pr_number)
			vim.schedule(function()
				spinner_utils.show_loading("Fetching PR details...")
			end)

			vim.system({ "gh", "pr", "view", pr_number, "--json", "headRefName,baseRefName,url,id" }, {
				text = true,
			}, function(result)
				vim.schedule(function()
					spinner_utils.hide_loading()
				end)
				if result.code ~= 0 then
					vim.schedule(function()
						print("Failed to get PR info. Error code:", result.code)
						print("Error output:", result.stderr or "No error output")
					end)
					return
				end

				local pr_ok, pr_data = parse_json(result.stdout)
				if not pr_ok or not pr_data then
					vim.schedule(function()
						print("Failed to parse PR info")
						print("JSON parse error:", pr_data)
					end)
					return
				end

				local head_branch = pr_data.headRefName or "unknown"
				local base_branch = pr_data.baseRefName or "main"
				local pr_url = pr_data.url or ""
				local pr_id = pr_data.id or pr_number -- fallback to number if id not available

				vim.schedule(function()
					-- Create useful git commands
					local commands = {
						"# PR #" .. pr_number .. " (ID: " .. pr_id .. ") commands:",
						"gh pr checkout " .. pr_number,
						"git diff " .. base_branch .. ".." .. head_branch,
						"git log " .. base_branch .. ".." .. head_branch .. " --oneline",
						"git diff HEAD~$(git rev-list --count " .. base_branch .. ".." .. head_branch .. ")",
						"gh pr diff " .. pr_number,
						"gh pr view " .. pr_number,
						"# Branch: " .. head_branch,
						"# Base: " .. base_branch,
						"# PR URL: " .. pr_url,
					}

					local commands_text = table.concat(commands, "\n")

					-- Copy to system clipboard (+ register)
					vim.fn.setreg("+", commands_text)
					print("PR #" .. pr_number .. " commands copied to system clipboard")
				end)
			end)
		end

		-- Helper to handle diffview workflow
		local function handle_diffview(pr_number)
			-- Get PR branch info asynchronously
			vim.schedule(function()
				spinner_utils.show_loading("Fetching PR branch info...")
			end)

			vim.system({ "gh", "pr", "view", pr_number, "--json", "headRefName" }, {
				text = true,
			}, function(result)
				vim.schedule(function()
					spinner_utils.hide_loading()
				end)
				if result.code ~= 0 then
					vim.schedule(function()
						print("Failed to get PR branch info. Error code:", result.code)
						print("Error output:", result.stderr or "No error output")
					end)
					return
				end

				local pr_ok, pr_data = parse_json(result.stdout)
				if not pr_ok or not pr_data then
					vim.schedule(function()
						print("Failed to parse PR branch info")
						print("JSON parse error:", pr_data)
						print("Raw output:", result.stdout)
					end)
					return
				end

				local pr_branch = pr_data.headRefName
				if not pr_branch then
					vim.schedule(function()
						print("No headRefName found in PR data")
					end)
					return
				end

				local remote_pr_branch = string.format("origin/%s", pr_branch)

				-- Check if the remote branch exists locally
				vim.system({ "git", "rev-parse", "--verify", remote_pr_branch }, {
					text = true,
				}, function(branch_result)
					if branch_result.code == 0 then
						-- Use diffview if branch exists locally
						vim.system({ "gh", "pr", "view", pr_number, "--json", "files" }, {
							text = true,
						}, function(files_result)
							if files_result.code ~= 0 or not files_result.stdout then
								vim.schedule(function()
									print("Failed to fetch PR files")
									print("Error:", files_result.stderr or "No error output")
								end)
								return
							end

							local files_ok, files_data = parse_json(files_result.stdout)
							if not files_ok or not files_data or not files_data.files then
								vim.schedule(function()
									print("Failed to parse PR files JSON")
									print("Parse error:", files_data)
								end)
								return
							end

							local file_choices = {}
							for _, file in ipairs(files_data.files) do
								if file.path and file.path ~= "" then
									table.insert(file_choices, file.path)
								end
							end

							if #file_choices == 0 then
								vim.schedule(function()
									print("No files found in PR")
								end)
								return
							end

							vim.schedule(function()
								local branch_ref = remote_pr_branch
								require("fzf-lua").fzf_exec(file_choices, {
									prompt = "Select file to diff> ",
									winopts = {
										width = 0.6,
										height = 0.4,
									},
									preview = function(selected)
										local file_path = selected[1]
										if not file_path then
											return "No file selected"
										end

										-- Debug output
										local debug_info =
											string.format("Branch: %s\nFile: %s\n\n", branch_ref, file_path)

										-- Use git diff to show the file changes
										local cmd =
											{ "git", "diff", "--color=always", "HEAD.." .. branch_ref, "--", file_path }
										local handle = io.popen(table.concat(vim.tbl_map(vim.fn.shellescape, cmd), " "))

										if not handle then
											return debug_info .. "Failed to run git diff command"
										end

										local output = handle:read("*a")
										handle:close()

										if output and output ~= "" then
											return debug_info .. output
										else
											return debug_info .. "No diff available for " .. file_path
										end
									end,
									actions = {
										["default"] = function(action_selected)
											local choice = action_selected[1]
											if not choice then
												return
											end
											-- Open Diffview for the specific file
											vim.cmd(
												"DiffviewFileHistory "
													.. vim.fn.fnameescape(choice)
													.. " --range=HEAD.."
													.. remote_pr_branch
											)
										end,
									},
								})
							end)
						end)
					else
						vim.schedule(function()
							print(
								"Branch "
									.. remote_pr_branch
									.. " not found locally. Use default action to view diff in terminal."
							)
						end)
					end
				end)
			end)
		end

		-- Fetch PRs as JSON and decode asynchronously
		spinner_utils.show_loading("Loading GitHub PRs...") -- Show spinner
		get_lines_async(
			"gh pr list --limit 10 --json number,title,url,body,headRefName,createdAt,author,files,reviews",
			function(lines)
				local prs_json = table.concat(lines, "\n")

				-- Handle empty or whitespace-only response
				if not prs_json or prs_json:match("^%s*$") then
					spinner_utils.hide_loading() -- Hide spinner
					vim.schedule(function()
						print("No GitHub CLI output received")
					end)
					return
				end

				local ok, prs_tbl = parse_json(prs_json)
				if not ok then
					spinner_utils.hide_loading() -- Hide spinner
					vim.schedule(function()
						print("Failed to parse GitHub PRs JSON")
						print("Parse error:", prs_tbl)
					end)
					return
				end

				spinner_utils.hide_loading() -- Hide spinner after successful fetch
				if type(prs_tbl) ~= "table" then
					vim.schedule(function()
						print("GitHub CLI returned unexpected data type:", type(prs_tbl))
					end)
					return
				end

				-- Handle empty PR list
				if #prs_tbl == 0 then
					vim.schedule(function()
						print("No pull requests found in this repository")
					end)
					return
				end

				-- Sort PRs by number in descending order
				table.sort(prs_tbl, function(a, b)
					return tonumber(a.number or 0) > tonumber(b.number or 0)
				end)

				-- Format PRs for picker and preview.
				local items = vim.tbl_map(function(pr)
					local title = pr.title or "No title"

					-- Title width constraints
					local max_title_width = 51

					if #title > max_title_width then
						title = title:sub(1, max_title_width)
					end

					local created_date = "?"
					if pr.createdAt then
						local year, month, day = pr.createdAt:match("(%d%d%d%d)-(%d%d)-(%d%d)")
						if year and month and day then
							created_date = string.format("%02d/%02d", tonumber(day), tonumber(month), year:sub(3, 4))
						end
					end

					-- Handle comments count - count reviews as activity
					local comment_count = 0
					if pr.comments and type(pr.comments) == "table" then
						comment_count = comment_count + #pr.comments
					end
					if pr.reviews and type(pr.reviews) == "table" then
						comment_count = comment_count + #pr.reviews
					end

					-- Add safety checks for title formatting
					if title:match("^[Ff][Ee][Aa][Tt]") then
						title = title:gsub("^([Ff][Ee][Aa][Tt])", "\27[33m%1\27[0m")
					elseif title:match("^[Ff][Ii][Xx]") then
						title = title:gsub("^([Ff][Ii][Xx])", "\27[32m%1\27[0m")
					elseif title:match("^[Cc][Hh][Oo][Rr][Ee]") then
						title = title:gsub("^([Cc][Hh][Oo][Rr][Ee])", "\27[31m%1\27[0m")
					elseif title:match("^[Aa][Dd][Dd]") then
						title = title:gsub("^([Aa][Dd][Dd])", "\27[35m%1\27[0m")
					elseif title:match("^[Dd][Oo][Cc][Ss]") then
						title = title:gsub("^([Dd][Oo][Cc][Ss])", "\27[36m%1\27[0m")
					elseif title:match("^[Rr][Ee][Ff][Aa][Cc][Tt][Oo][Rr]") then
						title = title:gsub("^([Rr][Ee][Ff][Aa][Cc][Tt][Oo][Rr])", "\27[95m%1\27[0m")
					elseif title:match("^[Tt][Ee][Ss][Tt]") then
						title = title:gsub("^([Tt][Ee][Ss][Tt])", "\27[94m%1\27[0m")
					elseif title:match("^[Ss][Tt][Yy][Ll][Ee]") then
						title = title:gsub("^([Ss][Tt][Yy][Ll][Ee])", "\27[96m%1\27[0m")
					elseif title:match("^[Pp][Ee][Rr][Ff]") then
						title = title:gsub("^([Pp][Ee][Rr][Ff])", "\27[92m%1\27[0m")
					elseif title:match("^[Cc][Ii]") then
						title = title:gsub("^([Cc][Ii])", "\27[93m%1\27[0m")
					elseif title:match("^[Bb][Uu][Ii][Ll][Dd]") then
						title = title:gsub("^([Bb][Uu][Ii][Ll][Dd])", "\27[90m%1\27[0m")
					elseif title:match("^[Rr][Ee][Vv][Ee][Rr][Tt]") then
						title = title:gsub("^([Rr][Ee][Vv][Ee][Rr][Tt])", "\27[91m%1\27[0m")
					end

					return {
						label = string.format("#%s: %s", pr.number or "?", pr.title or "No title"),
						display = string.format(
							"\27[34m#%5s\27[0m %s \27[32m%5s\27[0m \27[31m#%d\27[0m",
							pr.number or "?",
							title,
							created_date,
							comment_count
						),
						url = pr.url or "",
						body = pr.body or "",
						createdAt = pr.createdAt or "",
						author = (pr.author and pr.author.login) or "Unknown",
						branch = pr.headRefName or "unknown",
						files = pr.files or {},
						comments = comment_count,
					}
				end, prs_tbl)

				local picker_entries = vim.tbl_map(function(item)
					return item.display
				end, items)

				-- Schedule the fzf-lua call to run in the main event loop
				vim.schedule(function()
					require("fzf-lua").fzf_exec(picker_entries, {
						prompt = "GitHub PRs> ",
						fzf_opts = {
							["--header"] = "    PR Title",
						},
						winopts = {
							width = 0.6,
							height = 0.4,
						},
						-- Preview callback: show PR details and formatted body.
						preview = function(selected, _, _)
							local selected_display = selected[1]
							local selected_label = selected_display
								:gsub("\27%[%d+m", "")
								:gsub("\27%[%d+;%d+m", "")
								:gsub("\27%[0m", "")
								:gsub("\27", "")
							for _, item in ipairs(items) do
								local item_label = item.display
									:gsub("\27%[%d+m", "")
									:gsub("\27%[%d+;%d+m", "")
									:gsub("\27%[0m", "")
									:gsub("\27", "")
								if item_label == selected_label then
									local created = item.createdAt
											and os.date(
												"%Y-%m-%d %H:%M",
												vim.fn.strptime("%Y-%m-%dT%H:%M:%SZ", item.createdAt)
											)
										or "?"
									local author = item.author or "?"
									local branch = item.branch or "?"
									-- Format changed files
									local files_section = ""
									if item.files and #item.files > 0 then
										local file_list = {}
										for _, file in ipairs(item.files) do
											local status_color = file.status == "added" and "\27[32m"
												or file.status == "removed" and "\27[31m"
												or file.status == "modified" and "\27[33m"
												or "\27[36m"
											local reset_color = "\27[0m"
											table.insert(
												file_list,
												string.format(
													"%s%s%s",
													status_color,
													file.filename or file.path or "unknown",
													reset_color
												)
											)
										end
										files_section = string.format(
											"\27[36mFiles changed (%d):\27[0m\n%s\n\n",
											#item.files,
											table.concat(file_list, "\n")
										)
									end

									local header = string.format(
										"\27[32mCreated: %s\27[35m \nAuthor: %s \nBranch: %s\27[0m\n\n%s",
										created,
										author,
										branch,
										files_section
									)
									local body = markdown_utils.markdown_to_ansi(item.body)
									return header .. body
								end
							end
							return "No preview available"
						end,
						-- Actions
						actions = {
							-- Default action: open gh pr diff in terminal
							["default"] = function(selected)
								local pr_number, _ = get_pr_info(selected, items)
								if pr_number then
									open_terminal_diff(pr_number)
								else
									print("Could not extract PR number from selection")
								end
							end,
							["ctrl-v"] = function(selected)
								github_utils.create_open_action(items, "github_pr")(selected)
								-- Automatically show reviews if any exist
								vim.schedule(function()
									local item = github_utils.find_item_by_display(selected[1], items)
									if item then
										local pr_number = item.label:match("^#(%d+):")
										if pr_number and item.comments > 0 then
											github_utils.show_reviews_window_async(pr_number)
										end
									end
								end)
							end,
							["ctrl-e"] = github_utils.create_buffer_action(items),
							["ctrl-d"] = function(selected)
								local pr_number, _ = get_pr_info(selected, items)
								if pr_number then
									handle_diffview(pr_number)
								else
									print("Could not extract PR number from selection")
								end
							end,
							["ctrl-x"] = function(selected)
								local _, item = get_pr_info(selected, items)
								if item then
									if item.url and item.url:match("^https?://") then
										vim.system({ "xdg-open", item.url }, { detach = true })
									else
										print("No URL found in selection")
									end
								else
									print("Could not find selected item")
								end
							end,
							["ctrl-p"] = function(selected)
								local pr_number, _ = get_pr_info(selected, items)
								if pr_number then
									copy_pr_commands(pr_number)
								else
									print("Could not extract PR number from selection")
								end
							end,
						},
					})
				end)
			end
		)
	end, {})
end

function M.setup()
	M.fzf_github_prs()
end

return M
