local M = {}

local validation_utils = require("gitty.providers.github-compare.validation-utils")
local file_utils = require("gitty.utilities.file-utils")

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

	fzf.git_commits({
		prompt = "Select commit to view file: ",
		cmd = M.create_colorized_git_log_cmd(
			"git log --color=always --pretty=format:'%C(blue)%h%C(reset) %C(green)%ad%C(reset) %s %C(red)%an%C(reset)' --date=format:'%d/%m/%Y' -n 100"
		),
		fzf_opts = {
			["--header"] = ":: Select commit to view file :: ENTER=view file at commit",
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

	fzf.git_commits({
		prompt = string.format("Select commit from %s: ", branch),
		cmd = M.create_colorized_git_log_cmd(
			string.format(
				"git log --color=always --pretty=format:'%%C(blue)%%h%%C(reset) %%C(green)%%ad%%C(reset) %%s %%C(red)%%an%%C(reset)' --date=format:'%%d/%%m/%%Y' %s -n 50",
				branch
			)
		),
		fzf_opts = {
			["--header"] = string.format(":: Select commit from %s", branch),
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
	fzf.git_commits({
		prompt = string.format("Select commit to view files from %s: ", current_branch),
		cmd = M.create_colorized_git_log_cmd(
			string.format(
				"git log --color=always --pretty=format:'%%C(blue)%%h%%C(reset) %%C(green)%%ad%%C(reset) %%s %%C(red)%%an%%C(reset)' --date=format:'%%d/%%m/%%Y' %s -n 50",
				current_branch
			)
		),
		fzf_opts = {
			["--header"] = string.format(
				":: Select commit from %s :: ENTER=view files :: CTRL-Y=copy hash",
				current_branch
			),
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

				local commit = selected[1]:match("^(%w+)")
				if not commit then
					vim.notify("Invalid commit", vim.log.levels.ERROR)
					return
				end

				-- Step 2: Show files from selected commit
				M.show_files_from_commit(commit)
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
			["--preview"] = string.format("git show %s:{} 2>/dev/null || echo 'File not found at %s'", commit, commit),
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

return M
