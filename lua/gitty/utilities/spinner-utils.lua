local M = {}

local loading_win = nil

function M.show_loading(message)
	vim.schedule(function()
		local buf = vim.api.nvim_create_buf(false, true)
		local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { spinner_frames[1] .. " " .. message })
		loading_win = vim.api.nvim_open_win(buf, false, {
			relative = "editor",
			width = #message + 6,
			height = 1,
			row = vim.o.lines - 2,
			col = vim.o.columns - (#message + 6) - 2,
			style = "minimal",
			border = "none",
		})

		local function update_spinner()
			if vim.uv and vim.uv.hrtime then
				local spinner_index = math.floor(vim.uv.hrtime() / (1e6 * 100)) % #spinner_frames + 1
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, { spinner_frames[spinner_index] .. " " .. message })
			end
			if loading_win and vim.api.nvim_win_is_valid(loading_win) then
				vim.defer_fn(update_spinner, 100)
			end
		end

		update_spinner()
	end)
end

function M.hide_loading()
	vim.schedule(function()
		if loading_win and vim.api.nvim_win_is_valid(loading_win) then
			vim.api.nvim_win_close(loading_win, true)
			loading_win = nil
		end
	end)
end

return M
