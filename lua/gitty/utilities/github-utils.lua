local M = {}

-- Strip ANSI escape codes from text
function M.strip_ansi(text)
	return text:gsub("\27%[%d+m", ""):gsub("\27%[%d+;%d+m", ""):gsub("\27%[0m", ""):gsub("\27", "")
end

-- Find item by matching stripped display text
function M.find_item_by_display(selected_display, items)
	local selected_label = M.strip_ansi(selected_display)
	for _, item in ipairs(items) do
		local item_label = M.strip_ansi(item.display)
		if item_label == selected_label then
			return item
		end
	end
	return nil
end

-- Helper function to safely close existing buffer by name
function M.close_existing_buffer(name_pattern)
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) then
			local buf_name = vim.api.nvim_buf_get_name(buf)
			if buf_name:find(name_pattern, 1, true) then -- Use plain text search
				-- Close any windows showing this buffer first
				for _, win in ipairs(vim.api.nvim_list_wins()) do
					if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
						vim.api.nvim_win_close(win, true)
					end
				end
				-- Delete the buffer
				vim.api.nvim_buf_delete(buf, { force = true })
			end
		end
	end
end

-- Open markdown content in right-aligned window
function M.open_in_right_terminal(content, prefix)
	prefix = prefix or "github_content"

	-- Create a temporary file for the markdown content
	local tmpfile = "/dev/shm/nvim_glow_" .. tostring(math.random(100000, 999999)) .. ".md"
	local f = io.open(tmpfile, "w")
	if not f then
		print("Failed to create temporary file")
		return
	end

	-- Clean up carriage returns and other problematic characters
	local cleaned_content = (content or ""):gsub("\r", "")
	f:write(cleaned_content)
	f:close()

	-- Create a vertical split on the right side
	vim.cmd("rightbelow vertical split")
	local win = vim.api.nvim_get_current_win()

	-- Set window width to 40% of screen
	local width = math.floor(vim.o.columns * 0.4)
	vim.api.nvim_win_set_width(win, width)

	-- Create a new buffer for the terminal
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(win, buf)

	-- Use the exact same command as markdown_utils.lua but with --paging=never
	local cmd = string.format(
		"glow -s dark -w %d %s | bat --color=always --paging=never --language=markdown --style=plain; rm %s\n",
		width - 4,
		tmpfile,
		tmpfile
	)

	-- Start terminal with the command
	vim.fn.jobstart("sh", {
		term = true,
		on_exit = function()
			os.remove(tmpfile)
		end,
	})

	-- Send the command to the terminal
	vim.api.nvim_chan_send(vim.bo[buf].channel, cmd)
	vim.cmd("stopinsert")

	-- Set buffer options
	vim.bo[buf].buftype = "terminal"
	vim.bo[buf].modifiable = false
	vim.bo[buf].bufhidden = "wipe"

	-- Set window options
	vim.wo[win].number = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].wrap = true

	-- Add keymap to close the window
	vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
		noremap = true,
		silent = true,
		callback = function()
			os.remove(tmpfile)
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end,
	})
end

function M.open_in_buffer(content, filename)
	filename = filename or "/dev/shm/preview_temp.mdx"
	local file = io.open(filename, "w")
	if file then
		file:write(content)
		file:close()
		vim.cmd("edit " .. filename)
	end
end

function M.create_open_action(items, prefix)
	return function(selected)
		local item = M.find_item_by_display(selected[1], items)
		if item then
			M.open_in_right_buffer(item.body, prefix)
		end
	end
end

-- Enhanced function to add spacing around markdown elements
-- This makes sure headers, blockquotes, and horizontal rules have consistent spacing
-- Even if the user's content doesn't have it

local function add_spacing_to_markdown(content)
	local all_lines = {}

	-- First, split content into all lines including empty ones
	for line in (content .. "\n"):gmatch("([^\r\n]*)\r?\n") do
		table.insert(all_lines, line)
	end
	-- Remove the extra empty line added by the concatenation
	if #all_lines > 0 and all_lines[#all_lines] == "" then
		table.remove(all_lines)
	end

	local lines = {}
	local prev_line = ""

	for i, line in ipairs(all_lines) do
		local current_line_empty = line == ""
		local prev_line_empty = prev_line == ""
		local next_line = all_lines[i + 1]
		local next_line_empty = next_line == "" or next_line == nil

		-- Add blank line before headers (only if previous line has content and isn't already empty)
		if line:match("^#+%s") then
			if #lines > 0 and not prev_line_empty and prev_line:match("%S") then
				table.insert(lines, "")
			end
			table.insert(lines, line)
			-- Preserve existing spacing after headers, or add if missing and next line has content
			if not next_line_empty then
				table.insert(lines, "")
			end
		-- Add spacing around horizontal rules
		elseif line:match("^%-%-%-+$") then
			if #lines > 0 and not prev_line_empty and prev_line:match("%S") then
				table.insert(lines, "")
			end
			table.insert(lines, line)
		-- Don't automatically add spacing after horizontal rules
		-- Add spacing around blockquotes
		elseif line:match("^>") then
			if #lines > 0 and not prev_line:match("^>") and not prev_line_empty and prev_line:match("%S") then
				table.insert(lines, "")
			end
			table.insert(lines, line)
		else
			-- Handle end of blockquote sections
			if
				#lines > 0
				and prev_line:match("^>")
				and not line:match("^>")
				and not current_line_empty
				and line:match("%S")
			then
				table.insert(lines, "")
			end
			-- Only add the line if it's not creating consecutive empty lines
			if not (current_line_empty and prev_line_empty) then
				table.insert(lines, line)
			end
		end

		prev_line = line
	end

	return lines
end

-- Updated open_in_right_buffer function
function M.open_in_right_buffer(content, prefix)
	prefix = prefix or "github_content"

	local win, buf = M.create_side_buffer(prefix, 0.4, "markdown")

	local lines = add_spacing_to_markdown(content)
	if #lines == 0 then
		lines = { "No content available" }
	end

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = true

	vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
		noremap = true,
		silent = true,
		callback = function()
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end,
	})
end

function M.create_buffer_action(items)
	return function(selected)
		local item = M.find_item_by_display(selected[1], items)
		if item then
			M.open_in_buffer(item.body)
		end
	end
end

-- Helper to run a shell command and collect output lines
function M.get_lines(cmd)
	local lines = {}
	local handle = io.popen(cmd)
	if handle then
		for line in handle:lines() do
			table.insert(lines, line)
		end
		handle:close()
	end
	return lines
end

-- Helper to get comments for a specific issue
function M.get_issue_comments(issue_number)
	local comments_json =
		table.concat(M.get_lines(string.format("gh issue view %s --json comments", issue_number)), "\n")
	local ok, issue_data = pcall(vim.fn.json_decode, comments_json)
	if ok and issue_data and issue_data.comments then
		return issue_data.comments
	end
	return {}
end

-- Function to show comments in a new window
function M.show_comments_window(issue_number)
	local comments = M.get_issue_comments(issue_number) -- Fixed missing `M.` prefix
	if #comments == 0 then
		print("No comments found for this issue")
		return
	end

	-- Build comments content
	local content = {}
	table.insert(content, string.format("# Comments for Issue #%s", issue_number))

	for _, comment in ipairs(comments) do
		local comment_author = (comment.author and comment.author.login) or "Unknown"
		local comment_created = comment.createdAt
				and os.date("%Y-%m-%d %H:%M", vim.fn.strptime("%Y-%m-%dT%H:%M:%SZ", comment.createdAt))
			or "?"

		table.insert(content, string.format("### %s (%s)", comment_author, comment_created))
		table.insert(content, "")

		if comment.body and comment.body ~= "" then
			for line in comment.body:gmatch("[^\r\n]+") do
				table.insert(content, line)
			end
		end

		table.insert(content, "")
		table.insert(content, "---")
	end

	-- Create vertical split below current window
	local win, buf = M.create_bottom_buffer(string.format("Comments #%s", issue_number), 0.4, "markdown")
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
	vim.bo[buf].modifiable = false

	vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
		noremap = true,
		silent = true,
		callback = function()
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end,
		desc = "Close comments window",
	})
end

-- Helper to get reviews for a specific PR
function M.get_pr_reviews(pr_number)
	local reviews_json = table.concat(M.get_lines(string.format("gh pr view %s --json reviews", pr_number)), "\n")
	local ok, pr_data = pcall(vim.fn.json_decode, reviews_json)
	if ok and pr_data and pr_data.reviews then
		return pr_data.reviews
	end
	return {}
end

-- Function to show reviews in a new window
function M.show_reviews_window(pr_number)
	local reviews = M.get_pr_reviews(pr_number)
	if #reviews == 0 then
		print("No reviews found for this PR")
		return
	end

	-- Build reviews content
	local content = {}
	table.insert(content, string.format("# Reviews for PR #%s", pr_number))

	for _, review in ipairs(reviews) do
		local reviewer = (review.author and review.author.login) or "Unknown"
		local review_date = review.submittedAt
				and os.date("%Y-%m-%d %H:%M", vim.fn.strptime("%Y-%m-%dT%H:%M:%SZ", review.submittedAt))
			or "?"

		local state_emoji = review.state == "APPROVED" and "✅"
			or review.state == "CHANGES_REQUESTED" and "❌"
			or review.state == "COMMENTED" and "💬"
			or "📝"

		table.insert(content, string.format("### %s %s (%s)", state_emoji, reviewer, review_date))
		table.insert(content, string.format("**State:** %s", review.state or "UNKNOWN"))
		table.insert(content, "")

		if review.body and review.body ~= "" then
			for line in review.body:gmatch("[^\r\n]+") do
				table.insert(content, line)
			end
		else
			table.insert(content, "*No review comment*")
		end

		table.insert(content, "")
		table.insert(content, "---")
	end

	-- Create vertical split below current window
	vim.cmd("split")
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, string.format("Reviews #%s", pr_number))
	vim.bo[buf].filetype = "markdown"
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
	vim.bo[buf].modifiable = false
	vim.api.nvim_win_set_buf(0, buf)

	-- Add q keymap to close the buffer
	vim.api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>q<cr>", {
		noremap = true,
		silent = true,
		desc = "Close reviews window",
	})
end

-- Async function to get issue comments
local function get_issue_comments_async(issue_number, callback)
	vim.system({ "gh", "issue", "view", issue_number, "--json", "comments" }, {
		text = true,
	}, function(result)
		if result.code == 0 then
			local ok, issue_data
			if vim.json and vim.json.decode then
				ok, issue_data = pcall(vim.json.decode, result.stdout)
			else
				ok, issue_data = pcall(vim.fn.json_decode, result.stdout)
			end
			if ok and issue_data and issue_data.comments then
				callback(issue_data.comments)
			else
				callback({})
			end
		else
			callback({})
		end
	end)
end

-- Function to show comments in a new window asynchronously
function M.show_comments_window_async(issue_number)
	get_issue_comments_async(issue_number, function(comments)
		vim.schedule(function()
			if #comments == 0 then
				return
			end

			local content_lines = {}
			table.insert(content_lines, string.format("# Comments for Issue #%s", issue_number))
			table.insert(content_lines, "")

			for i, comment in ipairs(comments) do
				local comment_author = (comment.author and comment.author.login) or "Unknown"
				local comment_created = comment.createdAt
						and os.date("%Y-%m-%d %H:%M", vim.fn.strptime("%Y-%m-%dT%H:%M:%SZ", comment.createdAt))
					or "?"

				table.insert(content_lines, string.format("### %s (%s)", comment_author, comment_created))
				table.insert(content_lines, "")

				if comment.body and comment.body ~= "" then
					-- Split comment body into lines and add them
					for line in comment.body:gmatch("[^\r\n]+") do
						table.insert(content_lines, line)
					end
				end

				-- Add separator between comments (except for last comment)
				if i < #comments then
					table.insert(content_lines, "")
					table.insert(content_lines, "---")
					table.insert(content_lines, "") -- Add blank line after separator too
				end
			end

			local content = table.concat(content_lines, "\n")
			local formatted_lines = add_spacing_to_markdown(content)

			M.open_in_bottom_buffer(formatted_lines, "Comments #" .. issue_number)
		end)
	end)
end

-- Async function to get PR reviews
local function get_pr_reviews_async(pr_number, callback)
	vim.system({ "gh", "pr", "view", pr_number, "--json", "reviews" }, {
		text = true,
	}, function(result)
		if result.code == 0 then
			local ok, pr_data
			if vim.json and vim.json.decode then
				ok, pr_data = pcall(vim.json.decode, result.stdout)
			else
				ok, pr_data = pcall(vim.fn.json_decode, result.stdout)
			end
			if ok and pr_data and pr_data.reviews then
				callback(pr_data.reviews)
			else
				callback({})
			end
		else
			callback({})
		end
	end)
end

-- Function to show reviews in a new window asynchronously
function M.show_reviews_window_async(pr_number)
	get_pr_reviews_async(pr_number, function(reviews)
		vim.schedule(function()
			if #reviews == 0 then
				return
			end

			local content_lines = {}
			table.insert(content_lines, string.format("# Reviews for PR #%s", pr_number))
			table.insert(content_lines, "")

			for i, review in ipairs(reviews) do
				local reviewer = (review.author and review.author.login) or "Unknown"
				local review_date = review.submittedAt
						and os.date("%Y-%m-%d %H:%M", vim.fn.strptime("%Y-%m-%dT%H:%M:%SZ", review.submittedAt))
					or "?"

				local state_emoji = review.state == "APPROVED" and "✅"
					or review.state == "CHANGES_REQUESTED" and "❌"
					or review.state == "COMMENTED" and "💬"
					or "📝"

				table.insert(content_lines, string.format("### %s %s (%s)", state_emoji, reviewer, review_date))
				table.insert(content_lines, string.format("**State:** %s", review.state or "UNKNOWN"))
				table.insert(content_lines, "")

				if review.body and review.body ~= "" then
					for line in review.body:gmatch("[^\r\n]+") do
						table.insert(content_lines, line)
					end
				else
					table.insert(content_lines, "*No review comment*")
				end

				-- Add separator between reviews (except for last review)
				if i < #reviews then
					table.insert(content_lines, "")
					table.insert(content_lines, "---")
				end
			end

			local content = table.concat(content_lines, "\n")
			local formatted_lines = add_spacing_to_markdown(content)

			M.open_in_bottom_buffer(formatted_lines, "Reviews #" .. pr_number)
		end)
	end)
end

-- Oen content in a buffer below (horizontal split) for comments/reviews
function M.open_in_bottom_buffer(lines, prefix)
	prefix = prefix or "github_content"

	local win, buf = M.create_bottom_buffer(prefix, 0.4, "markdown")

	if #lines == 0 then
		lines = { "No content available" }
	end

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = true

	vim.wo[win].winhighlight = "Normal:CommentsBuffer,LineNr:CommentsBufferLine"

	vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
		noremap = true,
		silent = true,
		callback = function()
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end,
	})
end

-- Helper to create side buffer with common setup
function M.create_side_buffer(prefix, width_percent, filetype)
	width_percent = width_percent or 0.4
	filetype = filetype or "markdown"

	M.close_existing_buffer(prefix)

	vim.cmd("rightbelow vertical split")
	local win = vim.api.nvim_get_current_win()
	local width = math.floor(vim.o.columns * width_percent)
	vim.api.nvim_win_set_width(win, width)

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, prefix)
	vim.bo[buf].filetype = filetype
	vim.api.nvim_win_set_buf(win, buf)

	vim.wo[win].signcolumn = "no"
	vim.wo[win].wrap = true

	return win, buf
end

-- Helper to create bottom buffer with common setup (horizontal split)
function M.create_bottom_buffer(prefix, height_percent, filetype)
	height_percent = height_percent or 0.4
	filetype = filetype or "markdown"

	M.close_existing_buffer(prefix)

	vim.cmd("split")
	local win = vim.api.nvim_get_current_win()
	local height = math.floor(vim.o.lines * height_percent)
	vim.api.nvim_win_set_height(win, height)

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, prefix)
	vim.bo[buf].filetype = filetype
	vim.api.nvim_win_set_buf(win, buf)

	vim.wo[win].signcolumn = "no"
	vim.wo[win].wrap = true

	return win, buf
end

return M
