local M = {}
local markdown_utils = require("gitty.utilities.markdown-utils")
local github_utils = require("gitty.utilities.github-utils")

function M.fzf_github_branches()
	vim.api.nvim_create_user_command("FzfGithubBranches", function()
		local spinner_utils = require("gitty.utilities.spinner-utils")

		-- Helper to run shell command asynchronously
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

		-- Helper to enrich branch with detailed commit data
		local function enrich_branch_with_commit_data(branch, callback)
			if not branch.commit or not branch.commit.sha then
				callback(branch)
				return
			end

			get_lines_async("gh api repos/:owner/:repo/commits/" .. branch.commit.sha, function(lines)
				local commit_json = table.concat(lines, "\n")
				local ok, detailed_commit = parse_json(commit_json)

				if ok and detailed_commit and detailed_commit.commit then
					branch.commit = detailed_commit -- Replace with detailed commit info
				end
				callback(branch)
			end)
		end

		-- Helper to format date safely (avoiding fast event context issues)
		local function format_date_safe(date_str, format_str)
			if not date_str then
				return "?"
			end

			-- Parse ISO 8601 date manually to avoid strptime in fast event context
			local year, month, day, hour, min, sec = date_str:match("(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d):(%d%d)")
			if not year then
				return "?"
			end

			-- Ensure all values are numbers, not nil
			local timestamp = os.time({
				year = tonumber(year) or 1970,
				month = tonumber(month) or 1,
				day = tonumber(day) or 1,
				hour = tonumber(hour) or 0,
				min = tonumber(min) or 0,
				sec = tonumber(sec) or 0,
			})

			if not timestamp then
				return "?"
			end

			local formatted = os.date(format_str, timestamp)
			return formatted or "?"
		end

		-- Helper to get relative time (avoiding fast event context issues)
		local function get_relative_time_safe(date_str)
			if not date_str then
				return "?"
			end

			-- Parse ISO 8601 date manually
			local year, month, day, hour, min, sec = date_str:match("(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d):(%d%d)")
			if not year then
				return "?"
			end

			-- Ensure all values are numbers, not nil
			local timestamp = os.time({
				year = tonumber(year) or 1970,
				month = tonumber(month) or 1,
				day = tonumber(day) or 1,
				hour = tonumber(hour) or 0,
				min = tonumber(min) or 0,
				sec = tonumber(sec) or 0,
			})

			if not timestamp then
				return "?"
			end

			local now = os.time()
			local diff = now - timestamp
			local days = math.floor(diff / 86400)
			local hours = math.floor(diff / 3600)
			local minutes = math.floor(diff / 60)

			if days >= 1 then
				return string.format("%dd", days)
			elseif hours >= 1 then
				return string.format("%dh", hours)
			elseif minutes >= 1 then
				return string.format("%dm", minutes)
			else
				return "now"
			end
		end

		-- Helper to format commit for display
		local function format_commit(commit)
			local short_sha = commit.sha and commit.sha:sub(1, 7) or "?"
			local message = commit.commit and commit.commit.message or "No message"
			local title = message:match("^([^\n\r]*)")
			if #title > 45 then
				title = title:sub(1, 45)
			end

			local author = "Unknown"
			if commit.commit and commit.commit.author then
				author = commit.commit.author.name or "Unknown"
			end
			if #author > 8 then
				author = author:sub(1, 8)
			end

			local date = nil
			if commit.commit and commit.commit.author and commit.commit.author.date then
				date = format_date_safe(commit.commit.author.date, "%m/%d")
			end

			return {
				display = string.format(
					"\27[33m%s\27[0m %s \27[32m%s\27[0m \27[36m%s\27[0m",
					short_sha,
					title,
					author,
					date
				),
				sha = commit.sha,
				message = message,
				author = author,
				date = commit.commit and commit.commit.author and commit.commit.author.date,
				url = commit.html_url,
			}
		end

		-- Helper to show commits for selected branch
		local function show_branch_commits(branch_name)
			spinner_utils.show_loading("Loading commits for " .. branch_name .. "...")

			get_lines_async("gh api repos/:owner/:repo/commits?sha=" .. branch_name .. "&per_page=20", function(lines)
				local commits_json = table.concat(lines, "\n")

				if not commits_json or commits_json:match("^%s*$") then
					spinner_utils.hide_loading()
					vim.schedule(function()
						print("No commits found for branch: " .. branch_name)
					end)
					return
				end

				local ok, commits = parse_json(commits_json)
				if not ok or type(commits) ~= "table" then
					spinner_utils.hide_loading()
					vim.schedule(function()
						print("Failed to parse commits for branch: " .. branch_name)
					end)
					return
				end

				spinner_utils.hide_loading()

				-- Format commits for display
				local commit_items = vim.tbl_map(format_commit, commits)
				local commit_entries = vim.tbl_map(function(item)
					return item.display
				end, commit_items)

				vim.schedule(function()
					require("fzf-lua").fzf_exec(commit_entries, {
						prompt = "Commits (" .. branch_name .. ")> ",
						fzf_opts = {
							["--header"] = "SHA     Commit Message",
						},
						winopts = {
							width = 0.6,
							height = 0.6,
						},
						preview = function(selected, _, _)
							local selected_display = selected[1]
							local selected_label = github_utils.strip_ansi(selected_display)

							for _, item in ipairs(commit_items) do
								local item_label = github_utils.strip_ansi(item.display)
								if item_label == selected_label then
									local formatted_date = item.date
											and os.date(
												"%Y-%m-%d %H:%M",
												vim.fn.strptime("%Y-%m-%dT%H:%M:%SZ", item.date)
											)
										or "?"

									local header = string.format(
										"\27[32mBranch: %s\27[0m\n\27[33mSHA: %s\27[0m\n\27[36mAuthor: %s\27[0m\n\27[35mDate: %s\27[0m\n\n",
										branch_name,
										item.sha or "?",
										item.author or "Unknown",
										formatted_date
									)
									local body = markdown_utils.markdown_to_ansi(item.message or "No commit message")
									return header .. body
								end
							end
							return "No preview available"
						end,
						actions = {
							["default"] = function(selected)
								local item = github_utils.find_item_by_display(selected[1], commit_items)
								if item and item.url and item.url:match("^https?://") then
									vim.system({ "xdg-open", item.url }, { detach = true })
								else
									print("No URL found for commit")
								end
							end,
							["ctrl-v"] = function(selected)
								local item = github_utils.find_item_by_display(selected[1], commit_items)
								if item then
									github_utils.open_in_right_buffer(item.message, "commit_message")
								end
							end,
						},
					})
				end)
			end)
		end

		-- Fetch branches using GitHub API
		spinner_utils.show_loading("Loading GitHub branches...")
		get_lines_async("gh api repos/:owner/:repo/branches?per_page=100", function(lines)
			local branches_json = table.concat(lines, "\n")

			if not branches_json or branches_json:match("^%s*$") then
				spinner_utils.hide_loading()
				vim.schedule(function()
					print("No GitHub CLI output received")
				end)
				return
			end

			local ok, branches = parse_json(branches_json)
			if not ok or type(branches) ~= "table" then
				spinner_utils.hide_loading()
				vim.schedule(function()
					print("Failed to parse GitHub branches JSON")
				end)
				return
			end

			-- Enrich branches with detailed commit data
			local enriched_branches = {}
			local pending_count = #branches
			local completed_count = 0

			if pending_count == 0 then
				spinner_utils.hide_loading()
				vim.schedule(function()
					print("No branches found")
				end)
				return
			end

			for _, branch in ipairs(branches) do
				enrich_branch_with_commit_data(branch, function(enriched_branch)
					table.insert(enriched_branches, enriched_branch)
					completed_count = completed_count + 1

					if completed_count == pending_count then
						spinner_utils.hide_loading()

						-- Format branches for display
						local branch_items = vim.tbl_map(function(b)
							local name = b.name or "unknown"
							-- Truncate branch name to 18 characters for alignment
							if #name > 16 then
								name = name:sub(1, 16)
							end

							local is_protected = b.protected and "🔒" or "  "
							local commit_sha = b.commit and b.commit.sha and b.commit.sha:sub(1, 7) or "?"
							local commit_message = "No message"
							local commit_time = "?"

							if b.commit and b.commit.commit then
								if b.commit.commit.message then
									commit_message = b.commit.commit.message:match("^([^\n\r]*)")
								end

								-- Get relative time for latest commit
								if b.commit.commit.author and b.commit.commit.author.date then
									commit_time = get_relative_time_safe(b.commit.commit.author.date)
								end
							end

							return {
								display = string.format(
									"%s \27[34m%-18s\27[0m \27[33m%s\27[0m \27[35m%-6s\27[0m %s",
									is_protected,
									name,
									commit_sha,
									commit_time,
									commit_message
								),
								name = b.name or "unknown", -- Keep original name for actions
								protected = b.protected or false,
								commit = b.commit,
							}
						end, enriched_branches)

						-- Sort branches: default branch first, then by most recent commit
						table.sort(branch_items, function(a, b)
							if a.name == "main" or a.name == "master" then
								return true
							elseif b.name == "main" or b.name == "master" then
								return false
							else
								-- Sort by commit date (most recent first) - using manual parsing
								local a_date = a.commit
									and a.commit.commit
									and a.commit.commit.author
									and a.commit.commit.author.date
								local b_date = b.commit
									and b.commit.commit
									and b.commit.commit.author
									and b.commit.commit.author.date

								if a_date and b_date then
									local a_year, a_month, a_day, a_hour, a_min, a_sec =
										a_date:match("(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d):(%d%d)")
									local b_year, b_month, b_day, b_hour, b_min, b_sec =
										b_date:match("(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d):(%d%d)")

									if a_year and b_year then
										local a_timestamp = os.time({
											year = tonumber(a_year) or 1970,
											month = tonumber(a_month) or 1,
											day = tonumber(a_day) or 1,
											hour = tonumber(a_hour) or 0,
											min = tonumber(a_min) or 0,
											sec = tonumber(a_sec) or 0,
										})
										local b_timestamp = os.time({
											year = tonumber(b_year) or 1970,
											month = tonumber(b_month) or 1,
											day = tonumber(b_day) or 1,
											hour = tonumber(b_hour) or 0,
											min = tonumber(b_min) or 0,
											sec = tonumber(b_sec) or 0,
										})

										if a_timestamp and b_timestamp then
											return a_timestamp > b_timestamp
										end
									end
								end

								return a.name < b.name
							end
						end)

						local branch_entries = vim.tbl_map(function(item)
							return item.display
						end, branch_items)

						vim.schedule(function()
							require("fzf-lua").fzf_exec(branch_entries, {
								prompt = "GitHub Branches> ",
								fzf_opts = {
									["--header"] = " P Branch             SHA     Age    Latest Commit Message",
								},
								winopts = {
									width = 0.6,
									height = 0.4,
								},
								preview = function(selected, _, _)
									local selected_display = selected[1]
									local selected_label = github_utils.strip_ansi(selected_display)

									for _, item in ipairs(branch_items) do
										local item_label = github_utils.strip_ansi(item.display)
										if item_label == selected_label then
											local protected_status = item.protected and "🔒 Protected"
												or "🔓 Not Protected"
											local commit_info = "No commit info"

											if item.commit and item.commit.commit then
												local commit = item.commit.commit
												local author = (commit.author and commit.author.name) or "Unknown"
												local date_str = commit.author and commit.author.date or "Unknown"
												local formatted_date = date_str
														and os.date(
															"%Y-%m-%d %H:%M",
															vim.fn.strptime("%Y-%m-%dT%H:%M:%SZ", date_str)
														)
													or "Unknown"

												commit_info = string.format(
													"\27[33mSHA:\27[0m %s\n\27[32mAuthor:\27[0m %s\n\27[36mDate:\27[0m %s\n\n\27[35mMessage:\27[0m\n%s",
													item.commit.sha or "?",
													author,
													formatted_date,
													commit.message or "No message"
												)
											end

											return string.format(
												"\27[34mBranch:\27[0m %s\n\27[31mStatus:\27[0m %s\n\n%s",
												item.name,
												protected_status,
												commit_info
											)
										end
									end
									return "No preview available"
								end,
								actions = {
									["default"] = function(selected)
										local item = github_utils.find_item_by_display(selected[1], branch_items)
										if item then
											show_branch_commits(item.name)
										end
									end,
									["ctrl-x"] = function(selected)
										local item = github_utils.find_item_by_display(selected[1], branch_items)
										if item then
											local branch_url = string.format(
												"https://github.com/%s/tree/%s",
												vim.fn
													.system("gh repo view --json nameWithOwner -q .nameWithOwner")
													:gsub("%s+", ""),
												item.name
											)
											vim.system({ "xdg-open", branch_url }, { detach = true })
										end
									end,
								},
							})
						end)
					end
				end)
			end
		end)
	end, {})
end

function M.setup()
	M.fzf_github_branches()
end

return M
