local M = {}

-- Theme color presets for commit highlighting in fzf
M.theme_presets = {
	tokyonight = {
		hash = "#7aa2f7", -- blue
		date = "#9ece6a", -- green
		author = "#f7768e", -- red
		feat = "#e0af68", -- yellow
		fix = "#9ece6a", -- green
		chore = "#f7768e", -- red
		add = "#bb9af7", -- purple
	},
	catppuccin = {
		hash = "#89b4fa", -- blue
		date = "#a6e3a1", -- green
		author = "#f38ba8", -- red
		feat = "#f9e2af", -- yellow
		fix = "#a6e3a1", -- green
		chore = "#f38ba8", -- red
		add = "#cba6f7", -- mauve
	},
	monokai = {
		hash = "#7493d6", -- accent5 blue
		date = "#b3ca8c", -- accent4 green
		author = "#d67e9c", -- accent1 red/pink
		feat = "#d6cd8e", -- accent3 yellow
		fix = "#b3ca8c", -- accent4 green
		chore = "#d67e9c", -- accent1 red/pink
		add = "#ae90d7", -- accent6 purple
	},
}

local defaults = {
	-- Add any configuration options here
	spinner_enabled = true,
	preview_width = 0.6,
	preview_height = 0.4,
	split_diff_treesitter_left = true,
	split_diff_treesitter_right = false,
	-- Commit preview options
	show_commit_files_in_preview = true, -- Show files changed in commit preview
	enhanced_commit_preview = true, -- Use enhanced styling (delta + line numbers) in commit preview
	-- Theme for commit type colors (feat, fix, chore, add)
	-- Options: "tokyonight", "catppuccin", "monokai", or a custom table with {feat, fix, chore, add} hex colors
	commit_type_theme = "catppuccin",
}

M.options = {}

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", defaults, opts or {})
end

-- Convert hex color to RGB ANSI escape code (escaped for sed)
local function hex_to_ansi(hex)
	local r = tonumber(hex:sub(2, 3), 16)
	local g = tonumber(hex:sub(4, 5), 16)
	local b = tonumber(hex:sub(6, 7), 16)
	return string.format("\\x1b[38;2;%d;%d;%dm", r, g, b)
end

-- Convert hex color to RGB ANSI escape code (raw for Lua strings)
local function hex_to_ansi_raw(hex)
	local r = tonumber(hex:sub(2, 3), 16)
	local g = tonumber(hex:sub(4, 5), 16)
	local b = tonumber(hex:sub(6, 7), 16)
	return string.format("\x1b[38;2;%d;%d;%dm", r, g, b)
end

-- Get the current theme colors (resolves preset name or custom table)
function M.get_commit_type_colors()
	local theme = M.options.commit_type_theme or defaults.commit_type_theme
	if type(theme) == "string" then
		return M.theme_presets[theme] or M.theme_presets.catppuccin
	elseif type(theme) == "table" then
		return theme
	end
	return M.theme_presets.catppuccin
end

-- Build the sed colorization string for commit types
function M.get_commit_type_sed_pattern()
	local colors = M.get_commit_type_colors()
	local reset = "\\x1b[0m"
	local feat_ansi = hex_to_ansi(colors.feat)
	local fix_ansi = hex_to_ansi(colors.fix)
	local chore_ansi = hex_to_ansi(colors.chore)
	local add_ansi = hex_to_ansi(colors.add)

	return string.format(
		" | sed -E 's/^(.*) (feat[^[:space:]]*)/\\1 %s\\2%s/I; s/^(.*) (fix[^[:space:]]*)/\\1 %s\\2%s/I; s/^(.*) (chore[^[:space:]]*)/\\1 %s\\2%s/I; s/^(.*) (add[^[:space:]]*)/\\1 %s\\2%s/I'",
		feat_ansi,
		reset,
		fix_ansi,
		reset,
		chore_ansi,
		reset,
		add_ansi,
		reset
	)
end

-- Build complete sed pattern to colorize hash, date, author, and commit types
-- Input format expected: "HASH DATE MESSAGE AUTHOR" with | delimiters
function M.get_full_color_sed_pattern()
	local colors = M.get_commit_type_colors()
	local reset = "\\x1b[0m"
	local hash_ansi = hex_to_ansi(colors.hash)
	local date_ansi = hex_to_ansi(colors.date)
	local author_ansi = hex_to_ansi(colors.author)
	local feat_ansi = hex_to_ansi(colors.feat)
	local fix_ansi = hex_to_ansi(colors.fix)
	local chore_ansi = hex_to_ansi(colors.chore)
	local add_ansi = hex_to_ansi(colors.add)

	-- First colorize hash|date|message|author format, then commit types
	return string.format(
		" | sed -E 's/^([a-f0-9]+)\\|([^|]+)\\|(.*)\\|([^|]+)$/%s\\1%s %s\\2%s \\3 %s\\4%s/; s/(feat[^[:space:]]*)/%s\\1%s/I; s/(fix[^[:space:]]*)/%s\\1%s/I; s/(chore[^[:space:]]*)/%s\\1%s/I; s/(add[^[:space:]]*)/%s\\1%s/I'",
		hash_ansi,
		reset,
		date_ansi,
		reset,
		author_ansi,
		reset,
		feat_ansi,
		reset,
		fix_ansi,
		reset,
		chore_ansi,
		reset,
		add_ansi,
		reset
	)
end

-- Get git log format string (no colors - colors applied via sed)
function M.get_git_log_format()
	return "%h|%ad|%s|%an"
end

-- Get git log format with timestamp prefix for sorting (hash|timestamp|display_format)
function M.get_git_log_format_with_timestamp()
	return "%h|%ct|%h|%ad|%s|%an"
end

-- Build sed pattern for timestamp format (5 fields: hash|ts|hash|date|msg|author)
function M.get_timestamp_color_sed_pattern()
	local colors = M.get_commit_type_colors()
	local reset = "\\x1b[0m"
	local hash_ansi = hex_to_ansi(colors.hash)
	local date_ansi = hex_to_ansi(colors.date)
	local author_ansi = hex_to_ansi(colors.author)
	local feat_ansi = hex_to_ansi(colors.feat)
	local fix_ansi = hex_to_ansi(colors.fix)
	local chore_ansi = hex_to_ansi(colors.chore)
	local add_ansi = hex_to_ansi(colors.add)

	-- Format: hash|ts|hash|date|msg|author -> hash|ts|colored_display
	return string.format(
		" | sed -E 's/^([a-f0-9]+)\\|([0-9]+)\\|([a-f0-9]+)\\|([^|]+)\\|(.*)\\|([^|]+)$/\\1|\\2|%s\\3%s %s\\4%s \\5 %s\\6%s/; s/(feat[^[:space:]]*)/%s\\1%s/I; s/(fix[^[:space:]]*)/%s\\1%s/I; s/(chore[^[:space:]]*)/%s\\1%s/I; s/(add[^[:space:]]*)/%s\\1%s/I'",
		hash_ansi,
		reset,
		date_ansi,
		reset,
		author_ansi,
		reset,
		feat_ansi,
		reset,
		fix_ansi,
		reset,
		chore_ansi,
		reset,
		add_ansi,
		reset
	)
end

-- Get git log format for reflog (no date)
function M.get_git_reflog_format()
	return "%h|%s|%an"
end

-- Build sed pattern for reflog (no date field)
function M.get_reflog_color_sed_pattern()
	local colors = M.get_commit_type_colors()
	local reset = "\\x1b[0m"
	local hash_ansi = hex_to_ansi(colors.hash)
	local author_ansi = hex_to_ansi(colors.author)
	local feat_ansi = hex_to_ansi(colors.feat)
	local fix_ansi = hex_to_ansi(colors.fix)
	local chore_ansi = hex_to_ansi(colors.chore)
	local add_ansi = hex_to_ansi(colors.add)

	return string.format(
		" | sed -E 's/^([a-f0-9]+)\\|(.*)\\|([^|]+)$/%s\\1%s \\2 %s\\3%s/; s/(feat[^[:space:]]*)/%s\\1%s/I; s/(fix[^[:space:]]*)/%s\\1%s/I; s/(chore[^[:space:]]*)/%s\\1%s/I; s/(add[^[:space:]]*)/%s\\1%s/I'",
		hash_ansi,
		reset,
		author_ansi,
		reset,
		feat_ansi,
		reset,
		fix_ansi,
		reset,
		chore_ansi,
		reset,
		add_ansi,
		reset
	)
end

-- Get raw ANSI codes for use in Lua strings (not sed)
function M.get_ansi_codes()
	local colors = M.get_commit_type_colors()
	return {
		hash = hex_to_ansi_raw(colors.hash),
		date = hex_to_ansi_raw(colors.date),
		author = hex_to_ansi_raw(colors.author),
		feat = hex_to_ansi_raw(colors.feat),
		fix = hex_to_ansi_raw(colors.fix),
		chore = hex_to_ansi_raw(colors.chore),
		add = hex_to_ansi_raw(colors.add),
		reset = "\x1b[0m",
	}
end

return M
