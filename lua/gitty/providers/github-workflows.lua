local M = {}
function M.fzf_github_workflows()
	-- Registers the :FzfGithubWorkflows command to list and preview GitHub workflows and runs.
	vim.api.nvim_create_user_command("FzfGithubWorkflows", function()
		-- Async command execution helper
		local spinner_utils = require("gitty.utilities.spinner-utils")
		local function run_cmd_async(cmd, callback)
			local output = {}
			local job_id = vim.fn.jobstart(cmd, {
				on_stdout = function(_, data, _)
					if data then
						for _, line in ipairs(data) do
							if line ~= "" then
								table.insert(output, line)
							end
						end
					end
				end,
				on_exit = function(_, _, _)
					callback(table.concat(output, "\n"))
				end,
				stdout_buffered = true,
			})
			return job_id
		end

		spinner_utils.show_loading("Loading GitHub workflows...")

		-- Step 1: Fetch workflows
		run_cmd_async("gh workflow list --json name,id,path", function(workflows_json)
			spinner_utils.hide_loading()

			local ok, workflows = pcall(vim.fn.json_decode, workflows_json)
			if not ok or type(workflows) ~= "table" then
				vim.notify("Failed to fetch GitHub workflows", vim.log.levels.ERROR)
				return
			end

			local workflow_items = vim.tbl_map(function(workflow)
				return {
					display = string.format("%s (%s)", workflow.name, workflow.path),
					id = workflow.id,
					name = workflow.name,
					path = workflow.path,
				}
			end, workflows)

			local workflow_entries = vim.tbl_map(function(item)
				return item.display
			end, workflow_items)

			require("fzf-lua").fzf_exec(workflow_entries, {
				prompt = "GitHub Workflows> ",
				fzf_opts = {
					["--header"] = "Select a workflow to view its runs",
				},
				winopts = {
					width = 0.3,
					height = 0.2,
				},
				actions = {
					["default"] = function(selected)
						local selected_display = selected[1]
						for _, workflow in ipairs(workflow_items) do
							if workflow.display == selected_display then
								local workflow_path = workflow.path

								-- Show loading indicator for runs
								spinner_utils.show_loading("Loading GitHub workflows...")

								-- Step 2: Fetch workflow runs asynchronously
								run_cmd_async(
									string.format(
										"gh run list --workflow=%s --limit 20 --json databaseId,number,displayTitle,status,conclusion,workflowName,headBranch,event,startedAt,updatedAt,createdAt",
										workflow_path
									),
									function(runs_json)
										spinner_utils.hide_loading()

										local runs_ok, runs = pcall(vim.fn.json_decode, runs_json)
										if not runs_ok or type(runs) ~= "table" then
											vim.notify("Failed to fetch workflow runs", vim.log.levels.ERROR)
											return
										end

										local run_items = vim.tbl_map(function(run)
											local title = run.displayTitle or run.name or "No title"
											if #title > 25 then
												title = title:sub(1, 22) .. "..."
											end

											local workflow_name = run.workflowName or "Unknown Workflow"
											if #workflow_name > 20 then
												workflow_name = workflow_name:sub(1, 17) .. "..."
											end

											local branch = run.headBranch or "unknown"
											if #branch > 8 then
												branch = branch:sub(1, 6) .. ".."
											end

											local status_icon = "?"
											if run.status == "completed" then
												if run.conclusion == "success" then
													status_icon = "\27[32m✓\27[0m" -- Green for success
												elseif run.conclusion == "failure" then
													status_icon = "\27[31m✗\27[0m" -- Red for failure
												elseif run.conclusion == "cancelled" then
													status_icon = "\27[33m⊘\27[0m" -- Yellow for cancelled
												else
													status_icon = "\27[34m•\27[0m" -- Blue for other completed
												end
											elseif run.status == "in_progress" then
												status_icon = "\27[36m◐\27[0m" -- Cyan for in progress
											elseif run.status == "queued" then
												status_icon = "\27[35m⊙\27[0m" -- Magenta for queued
											end

											-- Calculate elapsed time
											local elapsed = "?"
											if run.startedAt and run.updatedAt then
												local start_time = vim.fn.strptime("%Y-%m-%dT%H:%M:%SZ", run.startedAt)
												local end_time = vim.fn.strptime("%Y-%m-%dT%H:%M:%SZ", run.updatedAt)
												if start_time and end_time then
													local duration = end_time - start_time
													local minutes = math.floor(duration / 60)
													local seconds = duration % 60
													elapsed = string.format("%dm%ds", minutes, seconds)
												end
											end

											-- Calculate age
											local age = "?"
											if run.createdAt then
												local created_time =
													vim.fn.strptime("%Y-%m-%dT%H:%M:%SZ", run.createdAt)
												if created_time then
													local now = os.time()
													local diff = now - created_time
													local days = math.floor(diff / 86400)
													if days >= 1 then
														age = string.format("about %d days ago", days)
													else
														local hours = math.floor(diff / 3600)
														age = string.format("about %d hours ago", hours)
													end
												end
											end

											return string.format(
												"%s \27[36m%-25s\27[0m \27[34m%-20s\27[0m \27[33m%-8s\27[0m \27[35m%-12s\27[0m \27[32m%-11s\27[0m \27[31m%-8s\27[0m \27[37m%-18s\27[0m",
												status_icon,
												title,
												workflow_name,
												branch,
												string.format("%-12.12s", run.event or "push"),
												tostring(run.databaseId or "?"),
												elapsed,
												age
											)
										end, runs)

										local function open_workflow_logs(run_id, use_terminal)
											if use_terminal then
												vim.schedule(function()
													spinner_utils.show_loading("Opening workflow logs...")
												end)

												vim.schedule(function()
													spinner_utils.hide_loading()

													-- Create a vertical split on the right side
													vim.cmd("vsplit")
													vim.cmd("wincmd l") -- Move to the right window

													-- Resize the split to take up about 75% of the screen
													local total_width = vim.o.columns
													local split_width = math.floor(total_width * 0.4)
													vim.cmd("vertical resize " .. split_width)

													-- Create a new buffer for the terminal
													local buf = vim.api.nvim_create_buf(false, true)
													vim.api.nvim_win_set_buf(0, buf)

													-- Create a persistent shell that stays open after command completes
													vim.fn.jobstart("sh", {
														term = true,
														on_exit = function()
															-- Don't auto-close the window, let user close it manually
														end,
													})

													local cmd = string.format(
														"gh run view %s --log | sed 's/\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\)T\\([0-9]\\{2\\}\\):\\([0-9]\\{2\\}\\):\\([0-9]\\{2\\}\\)\\.[0-9]*Z/\\1-\\2-\\3 \\4:\\5:\\6/g' | awk -F'\\t' '{if(NF>=3) print substr($0, index($0,$3)); else print}' | bat --color=always --style=plain --language=log --paging=never\n",
														run_id
													)
													vim.api.nvim_chan_send(vim.bo[buf].channel, cmd)
													vim.cmd("stopinsert")

													-- Set buffer options
													vim.bo[buf].buftype = "terminal"
													vim.bo[buf].bufhidden = "wipe"

													vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
														noremap = true,
														silent = true,
														callback = function()
															vim.cmd("close") -- Close the split window
														end,
													})

													vim.api.nvim_buf_set_keymap(buf, "t", "<C-q>", "", {
														noremap = true,
														silent = true,
														callback = function()
															vim.cmd("close") -- Close the split window from terminal mode
														end,
													})
												end)
											else
												-- Show loading indicator for log
												spinner_utils.show_loading("Loading run logs...")

												-- Step 3: Fetch run logs asynchronously
												run_cmd_async(
													string.format("gh run view %s --log | head -n 200", run_id),
													function(log_output)
														spinner_utils.hide_loading()

														-- Format the log output to highlight specific elements
														local formatted_output = {}
														for line in log_output:gmatch("[^\r\n]+") do
															-- Parse the log line format: job_name<tab>step_name<tab>timestamp message
															local parts = {}
															for part in line:gmatch("[^\t]+") do
																table.insert(parts, part)
															end

															if #parts >= 3 then
																local job_name = parts[1] or ""
																local step_name = parts[2] or ""
																local rest = table.concat(parts, "\t", 3)

																-- Truncate/pad job name to exactly 20 characters
																if #job_name > 20 then
																	job_name = job_name:sub(1, 17) .. "..."
																else
																	job_name = string.format("%-20s", job_name)
																end

																-- Truncate/pad step name to exactly 25 characters
																if #step_name > 25 then
																	step_name = step_name:sub(1, 22) .. "..."
																else
																	step_name = string.format("%-25s", step_name)
																end

																line = string.format(
																	"%s\t%s\t%s",
																	job_name,
																	step_name,
																	rest
																)
															end

															-- Format and highlight dates in the log
															line = line:gsub(
																"(%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d%.%d+Z)",
																function(date)
																	local year = tonumber(date:sub(1, 4)) or 0
																	local month = tonumber(date:sub(6, 7)) or 1
																	local day = tonumber(date:sub(9, 10)) or 1
																	local hour = tonumber(date:sub(12, 13)) or 0
																	local min = tonumber(date:sub(15, 16)) or 0
																	local sec = tonumber(date:sub(18, 19)) or 0

																	local formatted_date = os.date(
																		"%Y-%m-%d %H:%M:%S",
																		os.time({
																			year = year,
																			month = month,
																			day = day,
																			hour = hour,
																			min = min,
																			sec = sec,
																		})
																	)
																	return formatted_date
																end
															)

															-- Highlight step numbers
															line = line:gsub("#(%d+)", function(step)
																return string.format("#%s", step)
															end)

															table.insert(formatted_output, line)
														end

														-- Use a floating window to display the formatted log output
														local buf = vim.api.nvim_create_buf(false, true) -- Create a new buffer
														vim.api.nvim_buf_set_lines(buf, 0, -1, false, formatted_output)

														-- Configure floating window dimensions and position
														local width = math.floor(vim.o.columns * 0.8)
														local height = math.floor(vim.o.lines * 0.8)
														local row = math.floor((vim.o.lines - height) / 2)
														local col = math.floor((vim.o.columns - width) / 2)

														local opts = {
															style = "minimal",
															relative = "editor",
															width = width,
															height = height,
															row = row,
															col = col,
															border = "rounded",
														}

														-- Create the floating window
														local win = vim.api.nvim_open_win(buf, true, opts)

														-- Set options for better readability
														vim.bo[buf].filetype = "plaintext" -- Set filetype to 'plaintext' to disable Treesitter highlighting
														vim.bo[buf].modifiable = false -- Make the buffer read-only

														-- Add color highlighting using extmarks
														local ns_id = vim.api.nvim_create_namespace("log_highlight")
														for i, line in ipairs(formatted_output) do
															-- Highlight dates
															local start_idx, end_idx =
																line:find("%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d")
															if start_idx and end_idx then
																vim.highlight.range(
																	buf,
																	ns_id,
																	"Keyword",
																	{ i - 1, start_idx - 1 },
																	{ i - 1, end_idx }
																)
															end

															-- Highlight step numbers
															start_idx, end_idx = line:find("#%d+")
															if start_idx and end_idx then
																vim.highlight.range(
																	buf,
																	ns_id,
																	"Identifier",
																	{ i - 1, start_idx - 1 },
																	{ i - 1, end_idx }
																)
															end
														end

														vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
															noremap = true,
															silent = true,
															callback = function()
																vim.api.nvim_win_close(win, true) -- Close the floating window
																vim.api.nvim_buf_delete(buf, { force = true }) -- Delete the buffer
															end,
														})
													end
												)
											end
										end

										require("fzf-lua").fzf_exec(run_items, {
											prompt = "Workflow Runs> ",
											fzf_opts = {
												["--header"] = "S Title                     Workflow             Branch   Event        ID          Elapsed  Age",
											},
											winopts = {
												width = 0.4,
												height = 0.2,
											},
											-- Helper function to open logs in different formats
											actions = {
												["default"] = function(selected_run)
													local run_id = selected_run[1]:match("(%d%d%d%d%d%d%d%d%d+)")
													if run_id then
														open_workflow_logs(run_id, false)
													end
												end,
												["ctrl-v"] = function(selected_run)
													local run_id = selected_run[1]:match("(%d%d%d%d%d%d%d%d%d+)")
													if run_id then
														open_workflow_logs(run_id, true)
													end
												end,
											},
										})
									end
								)
								break
							end
						end
					end,
				},
			})
		end)
	end, {})
end

function M.setup()
	M.fzf_github_workflows()
end

return M
