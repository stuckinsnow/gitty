local M = {}

function M.validate_commit(commit, callback)
	vim.system({ "git", "rev-parse", "--verify", commit }, { text = true }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				vim.notify("Commit not found: " .. commit, vim.log.levels.ERROR)
			else
				callback()
			end
		end)
	end)
end

function M.validate_and_compare_hashes(commit1, commit2)
	M.validate_commit(commit1, function()
		M.validate_commit(commit2, function()
			vim.cmd("DiffviewOpen " .. commit1 .. ".." .. commit2)
			vim.notify(string.format("Comparing %s..%s", commit1:sub(1, 7), commit2:sub(1, 7)), vim.log.levels.INFO)
		end)
	end)
end

function M.validate_and_setup_minidiff(commit)
	M.validate_commit(commit, function()
		require("gitty.providers.github-compare.minidiff-utils").setup_minidiff(commit)
	end)
end

return M
