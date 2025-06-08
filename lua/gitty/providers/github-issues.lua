local M = {}
local markdown_utils = require("gitty.utilities.markdown-utils")
local github_utils = require("gitty.utilities.github-utils")

-- Registers the :FzfGithubIssues command to list and preview GitHub issues.
function M.fzf_github_issues()
	vim.api.nvim_create_user_command("FzfGithubIssues", function()
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

		-- Helper to render markdown with glow
		local function render_markdown(markdown_text)
			return markdown_utils.markdown_to_ansi(markdown_text)
		end

		-- Fetch issues as JSON and decode asynchronously
		spinner_utils.show_loading("Loading GitHub issues...") -- Show spinner
		get_lines_async(
			"gh issue list --limit 20 --json number,title,url,body,createdAt,author,comments",
			function(lines)
				local issues_json = table.concat(lines, "\n")

				-- Handle empty or whitespace-only response
				if not issues_json or issues_json:match("^%s*$") then
					spinner_utils.hide_loading() -- Hide spinner
					vim.schedule(function()
						print("No GitHub CLI output received")
					end)
					return
				end

				local ok, issues = parse_json(issues_json)
				if not ok then
					spinner_utils.hide_loading() -- Hide spinner
					vim.schedule(function()
						print("Failed to parse GitHub issues JSON")
						print("Parse error:", issues)
					end)
					return
				end

				spinner_utils.hide_loading() -- Hide spinner after successful fetch
				if type(issues) ~= "table" then
					vim.schedule(function()
						print("GitHub CLI returned unexpected data type:", type(issues))
					end)
					return
				end

				-- Handle empty issues list
				if #issues == 0 then
					vim.schedule(function()
						print("No issues found in this repository")
					end)
					return
				end

				-- Sort issues by number in descending order
				table.sort(issues, function(a, b)
					return tonumber(a.number or 0) > tonumber(b.number or 0)
				end)

				-- Format issues for picker and preview.
				local items = vim.tbl_map(function(issue)
					local title = issue.title or "No title"
					local max_title_width = 51

					if #title > max_title_width then
						title = title:sub(1, max_title_width)
					end

					local created_date = "?"
					if issue.createdAt then
						-- Use string parsing instead of strptime to avoid fast event context issues
						local year, month, day = issue.createdAt:match("(%d%d%d%d)-(%d%d)-(%d%d)")
						if year and month and day then
							created_date = string.format("%02d/%02d", tonumber(day), tonumber(month))
						end
					end

					-- Handle comments count - it might be a table or number
					local comment_count = 0
					if issue.comments then
						if type(issue.comments) == "table" then
							comment_count = #issue.comments
						elseif type(issue.comments) == "number" then
							comment_count = issue.comments
						end
					end

					return {
						display = string.format(
							"\27[34m#%5s\27[0m %s \27[32m%s\27[0m \27[31m#%d\27[0m",
							issue.number or "?",
							title,
							created_date,
							comment_count
						),
						number = issue.number,
						title = issue.title,
						url = issue.url,
						body = issue.body or "",
						createdAt = issue.createdAt,
						author = (issue.author and issue.author.login) or "Unknown",
						comments = comment_count,
					}
				end, issues)

				local picker_entries = vim.tbl_map(function(item)
					return item.display
				end, items)

				-- Schedule the fzf-lua call to run in the main event loop
				vim.schedule(function()
					require("fzf-lua").fzf_exec(picker_entries, {
						prompt = "GitHub Issues> ",
						fzf_opts = {
							["--header"] = " Issue Title",
						},
						winopts = {
							width = 0.6,
							height = 0.4,
						},
						preview = function(selected, _, _)
							local selected_display = selected[1]
							local selected_label = github_utils.strip_ansi(selected_display)
							for _, item in ipairs(items) do
								local item_label = github_utils.strip_ansi(item.display)
								if item_label == selected_label then
									local created = item.createdAt
											and os.date(
												"%Y-%m-%d %H:%M",
												vim.fn.strptime("%Y-%m-%dT%H:%M:%SZ", item.createdAt)
											)
										or "?"
									local author = item.author or "?"
									local header = string.format(
										"\27[32mCreated: %s\27[35m \nAuthor: %s\27[0m\n\n",
										created,
										author
									)
									local body = render_markdown(item.body)
									return header .. body
								end
							end
							return "No preview available"
						end,
						actions = {
							["default"] = function(selected)
								local item = github_utils.find_item_by_display(selected[1], items)
								if item and item.url and item.url:match("^https?://") then
									vim.system({ "xdg-open", item.url }, { detach = true })
								else
									print("No URL found in selection")
								end
							end,
							["ctrl-v"] = function(selected)
								github_utils.create_open_action(items, "github_issue")(selected)
								-- Automatically show comments if any exist
								vim.schedule(function()
									local item = github_utils.find_item_by_display(selected[1], items)
									if item and item.number and item.comments > 0 then
										github_utils.show_comments_window_async(item.number)
									end
								end)
							end,
							["ctrl-e"] = github_utils.create_buffer_action(items),
						},
					})
				end)
			end
		)
	end, {})
end

function M.setup()
	M.fzf_github_issues()
end

return M
