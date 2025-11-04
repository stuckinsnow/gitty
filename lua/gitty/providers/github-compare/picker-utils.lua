local M = {}

local validation_utils = require("gitty.providers.github-compare.validation-utils")
local file_utils = require("gitty.utilities.file-utils")
local config = require("gitty.config")

function M.create_commit_preview_command()
	local show_files = config.options.show_commit_files_in_preview
	local enhanced_style = config.options.enhanced_commit_preview

	if not show_files then
		-- Original behavior: just show git commit details
		if enhanced_style then
			return "HASH=$(echo {} | awk '{print $1}' | sed 's/[^a-f0-9]//g') && git show $HASH 2>/dev/null | delta --width $((FZF_PREVIEW_COLUMNS-2)) --line-numbers"
		else
			return "HASH=$(echo {} | awk '{print $1}' | sed 's/[^a-f0-9]//g') && git show --color=always $HASH 2>/dev/null"
		end
	else
		-- Enhanced behavior: show files + diff
		local base_cmd =
			"HASH=$(echo {} | awk '{print $1}' | sed 's/[^a-f0-9]//g') && echo -e '\\033[1;36mFiles changed in this commit:\\033[0m' && echo '' && git show --name-only --format= $HASH 2>/dev/null | head -10 && echo '' && echo -e '\\033[1;33m--- Git diff ---\\033[0m'"

		if enhanced_style then
			return base_cmd
				.. " && git show $HASH 2>/dev/null | delta --width $((FZF_PREVIEW_COLUMNS-2)) --line-numbers"
		else
			return base_cmd .. " && git show --color=always $HASH 2>/dev/null | head -50"
		end
	end
end

function M.copy_commit_hash(selected)
	if not selected or #selected == 0 then
		vim.notify("No commit selected to copy", vim.log.levels.WARN)
		return
	end
	local hash = selected[1]:match("^(%w+)")
	if not hash then
		vim.notify("Failed to extract commit hash", vim.log.levels.ERROR)
		return
	end
	vim.fn.setreg("+", hash)
	vim.notify("Copied commit hash: " .. hash, vim.log.levels.INFO)
end

function M.view_file_at_commit_picker()
	local fzf = require("fzf-lua")

	-- Use fzf_exec instead of git_commits to get full control over preview
	local git_log_cmd = M.create_colorized_git_log_cmd(
		"git log --color=always --pretty=format:'%C(blue)%h%C(reset) %C(green)%ad%C(reset) %s %C(red)%an%C(reset)' --date=format:'%d/%m/%Y' -n 100"
	)

	fzf.fzf_exec(git_log_cmd, {
		prompt = "Select commit to view file: ",
		fzf_opts = {
			["--header"] = ":: Select commit to view file :: ENTER=view file at commit",
			["--preview"] = M.create_commit_preview_command(),
		},
		actions = {
			["ctrl-y"] = false,
			["default"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				local commit = selected[1]:match("^(%w+)")
				if not commit then
					vim.notify("Invalid commit", vim.log.levels.ERROR)
					return
				end

				require("gitty.providers.github-compare.file-view-utils").goto_file_at_commit(commit)
			end,
		},
	})
end

function M.pick_branch_and_commit(commit1)
	local fzf = require("fzf-lua")

	validation_utils.validate_commit(commit1, function()
		fzf.git_branches({
			prompt = "Select branch for second commit: ",
			fzf_opts = {
				["--header"] = ":: Select branch for second commit",
			},
			actions = {
				["ctrl-y"] = false,
				["default"] = function(selected)
					if not selected or #selected == 0 then
						return
					end

					local branch = selected[1]:match("([^%s]+)$")
					if not branch then
						vim.notify("Failed to extract branch name", vim.log.levels.ERROR)
						return
					end

					M.pick_commit_from_branch(commit1, branch)
				end,
			},
		})
	end)
end

function M.pick_commit_from_branch(commit1, branch)
	local fzf = require("fzf-lua")

	-- Use fzf_exec instead of git_commits to get full control over preview
	local git_log_cmd = M.create_colorized_git_log_cmd(
		string.format(
			"git log --color=always --pretty=format:'%%C(blue)%%h%%C(reset) %%C(green)%%ad%%C(reset) %%s %%C(red)%%an%%C(reset)' --date=format:'%%d/%%m/%%Y' %s -n 50",
			branch
		)
	)

	fzf.fzf_exec(git_log_cmd, {
		prompt = string.format("Select commit from %s: ", branch),
		fzf_opts = {
			["--header"] = string.format(":: Select commit from %s", branch),
			["--preview"] = M.create_commit_preview_command(),
		},
		actions = {
			["ctrl-y"] = false,
			["default"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				local commit2 = selected[1]:match("^(%w+)")
				if not commit2 then
					vim.notify("Failed to extract commit hash", vim.log.levels.ERROR)
					return
				end

				vim.cmd("DiffviewOpen " .. commit1 .. ".." .. commit2)
				vim.notify(
					string.format("Comparing %s..%s (from %s)", commit1:sub(1, 7), commit2:sub(1, 7), branch),
					vim.log.levels.INFO
				)
			end,
		},
	})
end

function M.create_colorized_git_log_cmd(base_cmd)
	return base_cmd
		.. " | sed -E 's/^(.*) (feat[^[:space:]]*)/\\1 \\x1b[33m\\2\\x1b[0m/I; s/^(.*) (fix[^[:space:]]*)/\\1 \\x1b[32m\\2\\x1b[0m/I; s/^(.*) (chore[^[:space:]]*)/\\1 \\x1b[31m\\2\\x1b[0m/I; s/^(.*) (add[^[:space:]]*)/\\1 \\x1b[35m\\2\\x1b[0m/I'"
end

function M.fzf_last_commit_files()
	local fzf = require("fzf-lua")
	local current_branch = vim.fn.system("git branch --show-current"):gsub("%s+", "")

	if current_branch == "" then
		vim.notify("Failed to get current branch or not on a branch", vim.log.levels.ERROR)
		return
	end

	-- Step 1: Select commit hash first
	-- Use fzf_exec instead of git_commits to get full control over preview
	local git_log_cmd = M.create_colorized_git_log_cmd(
		string.format(
			"git log --color=always --pretty=format:'%%C(blue)%%h%%C(reset) %%C(green)%%ad%%C(reset) %%s %%C(red)%%an%%C(reset)' --date=format:'%%d/%%m/%%Y' %s -n 50",
			current_branch
		)
	)

	fzf.fzf_exec(git_log_cmd, {
		prompt = string.format("Select commits to view files from %s: ", current_branch),
		fzf_args = "--multi",
		fzf_opts = {
			["--header"] = string.format(
				":: Select commits from %s :: ENTER=view files :: TAB=multi-select :: CTRL-Y=copy hash",
				current_branch
			),
			["--preview"] = M.create_commit_preview_command(),
		},
		actions = {
			["ctrl-y"] = function(selected)
				if not selected or #selected == 0 then
					return
				end
				M.copy_commit_hash(selected)
			end,
			["default"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				if #selected == 1 then
					-- Single commit selected
					local commit = selected[1]:match("^(%w+)")
					if not commit then
						vim.notify("Invalid commit", vim.log.levels.ERROR)
						return
					end
					-- Step 2: Show files from selected commit
					M.show_files_from_commit(commit)
				else
					-- Multiple commits selected
					local commits = {}
					for _, sel in ipairs(selected) do
						local commit = sel:match("^(%w+)")
						if commit then
							table.insert(commits, commit)
						end
					end

					if #commits == 0 then
						vim.notify("No valid commits found", vim.log.levels.ERROR)
						return
					end

					-- Step 2: Show files from multiple commits
					M.show_files_from_multiple_commits(commits)
				end
			end,
		},
	})
end

function M.show_files_from_multiple_commits(commits)
	local fzf = require("fzf-lua")
	local all_files = {}
	local file_commit_map = {}

	-- Collect files from all commits
	for _, commit in ipairs(commits) do
		local handle = io.popen(string.format("git show --name-only --format= %s 2>/dev/null", commit))
		if handle then
			for line in handle:lines() do
				if line ~= "" then
					if not all_files[line] then
						all_files[line] = true
						file_commit_map[line] = {}
					end
					table.insert(file_commit_map[line], commit:sub(1, 7))
				end
			end
			handle:close()
		end
	end

	-- Convert to list and add commit info
	local files_list = {}
	for file, _ in pairs(all_files) do
		local colored_commits = {}
		for _, commit in ipairs(file_commit_map[file]) do
			table.insert(colored_commits, string.format("\x1b[35m%s\x1b[0m", commit))
		end
		local commit_info = table.concat(colored_commits, ",")
		table.insert(files_list, string.format("%s [%s]", file, commit_info))
	end

	if #files_list == 0 then
		vim.notify("No files found in selected commits", vim.log.levels.WARN)
		return
	end

	-- Sort files alphabetically
	table.sort(files_list)

	local commit_hashes = {}
	for _, commit in ipairs(commits) do
		table.insert(commit_hashes, commit:sub(1, 7))
	end
	local commits_str = table.concat(commit_hashes, ", ")

	fzf.fzf_exec(files_list, {
		prompt = "Select files to open (TAB to multi-select): ",
		fzf_args = "--multi",
		fzf_opts = {
			["--header"] = ":: " .. commits_str .. " :: ENTER=open files :: TAB=multi-select :: CTRL-Y=copy filenames",
			["--preview"] = function(items)
				if not items or #items == 0 then
					return ""
				end
				local file = items[1]:match("^([^%[]+)")
				if file then
					file = vim.trim(file)
					-- Show preview from the first commit that contains this file
					for _, commit in ipairs(commits) do
						local preview_cmd = string.format(
							"git show %s:%s 2>/dev/null | bat --color=always --style=header,grid --line-range=:500 --file-name='%s'",
							commit,
							file,
							file
						)
						local handle = io.popen(preview_cmd)
						if handle then
							local content = handle:read("*a")
							handle:close()
							if content and content ~= "" then
								return content
							end
						end
					end
				end
				return "File not found in selected commits"
			end,
		},
		actions = {
			["ctrl-y"] = function(selected)
				if not selected or #selected == 0 then
					return
				end
				local filenames = {}
				for _, item in ipairs(selected) do
					local file = item:match("^([^%[]+)")
					if file then
						table.insert(filenames, vim.trim(file))
					end
				end
				file_utils.copy_filenames_to_clipboard(filenames, { include_current = false })
			end,
			["default"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				for _, item in ipairs(selected) do
					local file = item:match("^([^%[]+)")
					if file then
						file = vim.trim(file)
						if vim.fn.filereadable(file) == 1 then
							vim.cmd("edit " .. vim.fn.fnameescape(file))
						else
							vim.notify("File '" .. file .. "' no longer exists in working tree", vim.log.levels.WARN)
						end
					end
				end
			end,
			["ctrl-v"] = function(selected)
				if not selected or #selected == 0 then
					return
				end
				for _, item in ipairs(selected) do
					local file = item:match("^([^%[]+)")
					if file then
						file = vim.trim(file)
						if vim.fn.filereadable(file) == 1 then
							vim.cmd("split " .. vim.fn.fnameescape(file))
						else
							vim.notify("File '" .. file .. "' no longer exists in working tree", vim.log.levels.WARN)
						end
					end
				end
			end,
			["ctrl-s"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				for _, item in ipairs(selected) do
					local file = item:match("^([^%[]+)")
					if file then
						file = vim.trim(file)
						if vim.fn.filereadable(file) == 1 then
							vim.cmd("split " .. vim.fn.fnameescape(file))
						else
							vim.notify("File '" .. file .. "' no longer exists in working tree", vim.log.levels.WARN)
						end
					end
				end
			end,
		},
	})
end

function M.open_all_files_from_commit_in_new_tab(branch, commit)
	-- Get ALL files from the selected commit
	local handle = io.popen(string.format("git show --name-only --format= %s 2>/dev/null", commit))
	if not handle then
		vim.notify("Failed to get files from commit " .. commit, vim.log.levels.ERROR)
		return
	end

	local files = {}
	for line in handle:lines() do
		if line ~= "" then
			table.insert(files, line)
		end
	end
	handle:close()

	if #files == 0 then
		vim.notify("No files found in commit " .. commit, vim.log.levels.WARN)
		return
	end

	-- Create new tab
	vim.cmd("tabnew")

	-- Keep track of loaded files and their order for proper window management
	local loaded_files = {}
	local total_files = #files
	local first_buffer_set = false

	-- Load each file from the commit sequentially
	for _, file in ipairs(files) do
		vim.system({ "git", "show", string.format("%s:%s", commit, file) }, { text = true }, function(result)
			vim.schedule(function()
				if result.code ~= 0 then
					vim.notify(
						string.format("File '%s' not found in commit '%s'", file, commit:sub(1, 7)),
						vim.log.levels.WARN
					)
					-- Still count as "processed" to avoid hanging
					table.insert(loaded_files, { file = file, success = false })
					if #loaded_files == total_files then
						vim.notify(
							string.format(
								"Loaded %d files from %s@%s in new tab",
								vim.tbl_count(vim.tbl_filter(function(f)
									return f.success
								end, loaded_files)),
								branch,
								commit:sub(1, 7)
							),
							vim.log.levels.INFO
						)
					end
					return
				end

				-- Create buffer for the file from commit (historical content)
				local buf = vim.api.nvim_create_buf(false, true)
				local lines = vim.split(result.stdout or "", "\n")
				if lines[#lines] == "" then
					table.remove(lines)
				end

				-- Add header comment with commit info at the top
				local header_lines = {
					string.format(
						"# File: %s from commit %s (%s@%s)",
						file,
						commit:sub(1, 7),
						branch,
						commit:sub(1, 7)
					),
					"# This is historical content - not the current working tree version",
					"",
				}

				-- Combine header with file content
				local all_lines = {}
				vim.list_extend(all_lines, header_lines)
				vim.list_extend(all_lines, lines)

				vim.api.nvim_buf_set_lines(buf, 0, -1, false, all_lines)

				-- Set filetype based on file extension for syntax highlighting
				local filetype = vim.filetype.match({ filename = file })
				if filetype then
					vim.bo[buf].filetype = filetype
				end

				-- Set buffer name to include commit info
				local buf_name = string.format("[%s@%s] %s", branch, commit:sub(1, 7), file)
				vim.api.nvim_buf_set_name(buf, buf_name)

				-- Make buffer read-only since it's historical
				vim.bo[buf].readonly = true
				vim.bo[buf].modifiable = false

				-- Open in appropriate window
				if not first_buffer_set then
					-- Replace the empty buffer in the new tab
					vim.api.nvim_win_set_buf(0, buf)
					first_buffer_set = true
				else
					-- Split and open additional files
					vim.cmd("split")
					vim.api.nvim_win_set_buf(0, buf)
				end

				table.insert(loaded_files, { file = file, success = true })

				-- Notify when all files are loaded
				if #loaded_files == total_files then
					local success_count = vim.tbl_count(vim.tbl_filter(function(f)
						return f.success
					end, loaded_files))
					vim.notify(
						string.format(
							"Opened %d files from %s@%s in new tab (historical content)",
							success_count,
							branch,
							commit:sub(1, 7)
						),
						vim.log.levels.INFO
					)
				end
			end)
		end)
	end
end

function M.open_files_from_branch_commit_in_new_tab()
	local fzf = require("fzf-lua")

	-- Step 1: Select branch
	fzf.git_branches({
		prompt = "Select branch: ",
		fzf_opts = {
			["--header"] = ":: Select branch to view files from ::",
		},
		actions = {
			["ctrl-x"] = false,
			["ctrl-a"] = false,
			["default"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				local branch = selected[1]:match("([^%s]+)$")
				if not branch then
					vim.notify("Failed to extract branch name", vim.log.levels.ERROR)
					return
				end

				M.select_commit_from_branch_for_new_tab(branch)
			end,
		},
	})
end

function M.select_commit_from_branch_for_new_tab(branch)
	local fzf = require("fzf-lua")

	-- Step 2: Select commit from the chosen branch
	-- Use fzf_exec instead of git_commits to get full control over preview
	local git_log_cmd = M.create_colorized_git_log_cmd(
		string.format(
			"git log --color=always --pretty=format:'%%C(blue)%%h%%C(reset) %%C(green)%%ad%%C(reset) %%s %%C(red)%%an%%C(reset)' --date=format:'%%d/%%m/%%Y' %s -n 50",
			branch
		)
	)

	fzf.fzf_exec(git_log_cmd, {
		prompt = string.format("Select commit from %s: ", branch),
		fzf_opts = {
			["--header"] = string.format(":: Select commit from %s ::", branch),
			["--preview"] = M.create_commit_preview_command(),
		},
		actions = {
			["ctrl-x"] = false,
			["ctrl-a"] = false,
			["default"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				local commit = selected[1]:match("^(%w+)")
				if not commit then
					vim.notify("Failed to extract commit hash", vim.log.levels.ERROR)
					return
				end

				M.open_all_files_from_commit_in_new_tab(branch, commit)
			end,
		},
	})
end

function M.show_files_from_commit(commit)
	local fzf = require("fzf-lua")

	-- Get files from the selected commit
	local handle = io.popen(string.format("git show --name-only --format= %s 2>/dev/null", commit))
	if not handle then
		vim.notify("Failed to get files from commit " .. commit, vim.log.levels.ERROR)
		return
	end

	local files = {}
	for line in handle:lines() do
		if line ~= "" then
			table.insert(files, line)
		end
	end
	handle:close()

	if #files == 0 then
		vim.notify("No files found in commit " .. commit, vim.log.levels.WARN)
		return
	end

	-- Get commit hash for header
	local commit_hash = vim.fn.system(string.format("git log -1 --format='%%h' %s", commit)):gsub("\n", "")

	fzf.fzf_exec(files, {
		prompt = "Select files to open (TAB to multi-select): ",
		fzf_args = "--multi",
		fzf_opts = {
			["--header"] = ":: " .. commit_hash .. " :: ENTER=open files :: TAB=multi-select :: CTRL-Y=copy filenames",
			["--preview"] = string.format(
				"git show %s:{} 2>/dev/null | bat --color=always --style=header,grid --line-range=:500 --file-name={} || echo 'File not found at %s'",
				commit,
				commit
			),
		},
		actions = {
			["ctrl-y"] = function(selected)
				file_utils.copy_filenames_to_clipboard(selected, { include_current = false })
			end,
			["default"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				for _, file in ipairs(selected) do
					if vim.fn.filereadable(file) == 1 then
						vim.cmd("edit " .. vim.fn.fnameescape(file))
					else
						vim.notify("File '" .. file .. "' no longer exists in working tree", vim.log.levels.WARN)
					end
				end
			end,
			["ctrl-v"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				for _, file in ipairs(selected) do
					if vim.fn.filereadable(file) == 1 then
						vim.cmd("vsplit " .. vim.fn.fnameescape(file))
					else
						vim.notify("File '" .. file .. "' no longer exists in working tree", vim.log.levels.WARN)
					end
				end
			end,
			["ctrl-s"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				for _, file in ipairs(selected) do
					if vim.fn.filereadable(file) == 1 then
						vim.cmd("split " .. vim.fn.fnameescape(file))
					else
						vim.notify("File '" .. file .. "' no longer exists in working tree", vim.log.levels.WARN)
					end
				end
			end,
		},
	})
end

function M.browse_files_at_commit()
	local fzf = require("fzf-lua")

	-- Step 1: Select branch or use reflog
	fzf.git_branches({
		prompt = "Select branch to browse files: ",
		fzf_opts = {
			["--header"] = ":: Select branch to browse files at commit :: ENTER=branch :: CTRL-L=reflog ::",
		},
		actions = {
			["ctrl-x"] = false,
			["ctrl-a"] = false,
			["ctrl-l"] = function(selected)
				-- Use reflog instead of branch
				M.select_commit_for_file_browser_reflog()
			end,
			["default"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				local branch = selected[1]:match("([^%s]+)$")
				if not branch then
					vim.notify("Failed to extract branch name", vim.log.levels.ERROR)
					return
				end

				M.select_commit_for_file_browser(branch)
			end,
		},
	})
end

function M.select_commit_for_file_browser_reflog()
	local fzf = require("fzf-lua")

	-- Get current branch for reflog
	local current_branch = vim.fn.system("git branch --show-current"):gsub("%s+", "")
	if current_branch == "" then
		vim.notify("Failed to get current branch", vim.log.levels.ERROR)
		return
	end

	-- Get reflog entries - shows commits that were in the branch history but may now be squashed
	local reflog_base_cmd = string.format(
		"git reflog %s --color=always --pretty=format:'%%C(blue)%%h%%C(reset) %%s %%C(red)%%an%%C(reset)' | head -50",
		current_branch
	)

	-- Apply colorization for commit types (feat, fix, chore, add)
	local reflog_cmd = reflog_base_cmd
		.. " | sed -E 's/^(.*) (feat[^[:space:]]*)/\\1 \\x1b[33m\\2\\x1b[0m/I; s/^(.*) (fix[^[:space:]]*)/\\1 \\x1b[32m\\2\\x1b[0m/I; s/^(.*) (chore[^[:space:]]*)/\\1 \\x1b[31m\\2\\x1b[0m/I; s/^(.*) (add[^[:space:]]*)/\\1 \\x1b[35m\\2\\x1b[0m/I'"

	fzf.fzf_exec(reflog_cmd, {
		prompt = string.format("Select commit from %s reflog to browse files: ", current_branch),
		fzf_opts = {
			["--header"] = string.format(
				":: Reflog for %s (includes squashed commits) :: ENTER=file picker :: CTRL-V=mini.files",
				current_branch
			),
			["--preview"] = M.create_commit_preview_command(),
		},
		actions = {
			["ctrl-x"] = false,
			["ctrl-a"] = false,
			["default"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				local commit = selected[1]:match("^(%w+)")
				if not commit then
					vim.notify("Failed to extract commit hash", vim.log.levels.ERROR)
					return
				end

				M.show_file_picker_at_commit("reflog", commit)
			end,
			["ctrl-v"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				local commit = selected[1]:match("^(%w+)")
				if not commit then
					vim.notify("Failed to extract commit hash", vim.log.levels.ERROR)
					return
				end

				M.open_mini_files_at_commit("reflog", commit)
			end,
		},
	})
end

function M.select_commit_for_file_browser(branch)
	local fzf = require("fzf-lua")

	-- Step 2: Select commit from the chosen branch
	local git_log_cmd = M.create_colorized_git_log_cmd(
		string.format(
			"git log --color=always --pretty=format:'%%C(blue)%%h%%C(reset) %%C(green)%%ad%%C(reset) %%s %%C(red)%%an%%C(reset)' --date=format:'%%d/%%m/%%Y' %s -n 50",
			branch
		)
	)

	fzf.fzf_exec(git_log_cmd, {
		prompt = string.format("Select commit from %s to browse files: ", branch),
		fzf_opts = {
			["--header"] = string.format(":: Select commit from %s :: ENTER=file picker :: CTRL-V=mini.files", branch),
			["--preview"] = M.create_commit_preview_command(),
		},
		actions = {
			["ctrl-x"] = false,
			["ctrl-a"] = false,
			["default"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				local commit = selected[1]:match("^(%w+)")
				if not commit then
					vim.notify("Failed to extract commit hash", vim.log.levels.ERROR)
					return
				end

				M.show_file_picker_at_commit(branch, commit)
			end,
			["ctrl-v"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				local commit = selected[1]:match("^(%w+)")
				if not commit then
					vim.notify("Failed to extract commit hash", vim.log.levels.ERROR)
					return
				end

				M.open_mini_files_at_commit(branch, commit)
			end,
		},
	})
end

function M.show_file_picker_at_commit(branch, commit)
	local fzf = require("fzf-lua")

	-- Get all files from the commit
	local handle = io.popen(string.format("git ls-tree -r --name-only %s 2>/dev/null", commit))
	if not handle then
		vim.notify("Failed to get files from commit " .. commit, vim.log.levels.ERROR)
		return
	end

	local files = {}
	for line in handle:lines() do
		if line ~= "" then
			table.insert(files, line)
		end
	end
	handle:close()

	if #files == 0 then
		vim.notify("No files found in commit " .. commit, vim.log.levels.WARN)
		return
	end

	fzf.fzf_exec(files, {
		prompt = string.format("Browse files from %s@%s: ", branch, commit:sub(1, 7)),
		fzf_args = "--multi",
		fzf_opts = {
			["--header"] = string.format(
				":: %s@%s :: ENTER=open :: CTRL-V=vsplit :: CTRL-S=hsplit",
				branch,
				commit:sub(1, 7)
			),
			["--preview"] = string.format(
				"git show %s:{} 2>/dev/null | bat --color=always --style=header,grid --line-range=:500 --file-name={} || echo 'File not found at %s'",
				commit,
				commit
			),
		},
		actions = {
			["default"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				for _, file in ipairs(selected) do
					M.open_file_from_commit_with_winbar(branch, commit, file, "tabnew")
				end
			end,
			["ctrl-v"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				for _, file in ipairs(selected) do
					M.open_file_from_commit_with_winbar(branch, commit, file, "vsplit")
				end
			end,
			["ctrl-s"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				for _, file in ipairs(selected) do
					M.open_file_from_commit_with_winbar(branch, commit, file, "split")
				end
			end,
		},
	})
end

function M.open_file_from_commit_with_winbar(branch, commit, file, split_cmd)
	-- Get the file content from the specific commit
	vim.system({ "git", "show", string.format("%s:%s", commit, file) }, { text = true }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				vim.notify(
					string.format("File '%s' not found in commit '%s'", file, commit:sub(1, 7)),
					vim.log.levels.ERROR
				)
				return
			end

			-- Create buffer for the file from commit
			local buf = vim.api.nvim_create_buf(false, true)
			local lines = vim.split(result.stdout or "", "\n")
			if lines[#lines] == "" then
				table.remove(lines)
			end

			vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

			-- Set filetype for syntax highlighting
			local filetype = vim.filetype.match({ filename = file })
			if filetype then
				vim.bo[buf].filetype = filetype
			end

			-- Set buffer name
			local buf_name = string.format("[%s@%s] %s", branch, commit:sub(1, 7), file)
			vim.api.nvim_buf_set_name(buf, buf_name)

			-- Make buffer read-only
			vim.bo[buf].readonly = true
			vim.bo[buf].modifiable = false

			-- Open in appropriate window (same tab by default)
			if split_cmd == "tabnew" then
				-- Create new tab and set buffer
				vim.cmd("tabnew")
				local empty_buf = vim.api.nvim_get_current_buf()
				local new_win = vim.api.nvim_get_current_win()
				vim.api.nvim_win_set_buf(new_win, buf)
				-- Delete the empty buffer created by tabnew if it's empty and unnamed
				if vim.api.nvim_buf_is_valid(empty_buf) and vim.api.nvim_buf_get_name(empty_buf) == ""
				   and not vim.bo[empty_buf].modified then
					vim.api.nvim_buf_delete(empty_buf, { force = true })
				end
			elseif split_cmd then
				vim.cmd(split_cmd)
				vim.api.nvim_win_set_buf(0, buf)
			else
				-- Open in current window/tab
				local current_win = vim.api.nvim_get_current_win()
				vim.api.nvim_win_set_buf(current_win, buf)
			end

			local win = vim.api.nvim_get_current_win()

			-- Set winbar with commit info
			vim.wo[win].winbar = string.format("%%#GittySplitRightTitle#%s@%s: %s", branch, commit:sub(1, 7), file)

			vim.notify(string.format("Opened %s from %s@%s", file, branch, commit:sub(1, 7)), vim.log.levels.INFO)
		end)
	end)
end

function M.open_mini_files_at_commit(branch, commit)
	-- Check if mini.files is available
	local has_mini_files, mini_files = pcall(require, "mini.files")
	if not has_mini_files then
		vim.notify("mini.files is not available. Please install mini.files plugin.", vim.log.levels.ERROR)
		return
	end

	-- Create a temporary directory for the commit files
	local temp_dir = vim.fn.tempname() .. "_gitty_" .. commit:sub(1, 7)
	vim.fn.mkdir(temp_dir, "p")

	-- Get all files from the commit
	local handle = io.popen(string.format("git ls-tree -r --name-only %s 2>/dev/null", commit))
	if not handle then
		vim.notify("Failed to get files from commit " .. commit, vim.log.levels.ERROR)
		return
	end

	local files = {}
	for line in handle:lines() do
		if line ~= "" then
			table.insert(files, line)
		end
	end
	handle:close()

	if #files == 0 then
		vim.notify("No files found in commit " .. commit, vim.log.levels.WARN)
		return
	end

	-- Extract files to temp directory
	local files_extracted = 0
	local total_files = #files

	for _, file in ipairs(files) do
		vim.system({ "git", "show", string.format("%s:%s", commit, file) }, { text = true }, function(result)
			vim.schedule(function()
				if result.code == 0 then
					-- Create directory structure
					local file_path = temp_dir .. "/" .. file
					local dir_path = vim.fn.fnamemodify(file_path, ":h")
					vim.fn.mkdir(dir_path, "p")

					-- Write file content
					local f = io.open(file_path, "w")
					if f then
						f:write(result.stdout or "")
						f:close()
					end
				end

				files_extracted = files_extracted + 1

				-- When all files are extracted, open mini.files
				if files_extracted == total_files then
					-- Simple cleanup on mini.files close
					vim.api.nvim_create_autocmd("User", {
						pattern = "MiniFilesWindowClose",
						callback = function()
							vim.fn.delete(temp_dir, "rf")
						end,
						once = true,
					})

					-- Open mini.files at the temp directory
					mini_files.open(temp_dir)

					vim.notify(
						string.format("Mini Files opened at %s@%s (%d files)", branch, commit:sub(1, 7), total_files),
						vim.log.levels.INFO
					)
				end
			end)
		end)
	end
end

return M
