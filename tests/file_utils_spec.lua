-- Run with: nvim --headless -u NONE -l tests/file_utils_spec.lua

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local file_utils = require("gitty.utilities.file-utils")

local passed, failed = 0, 0

local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
		io.write("  PASS  " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL  " .. name .. "\n        " .. tostring(err) .. "\n")
	end
end

local function assert_eq(actual, expected, msg)
	if actual ~= expected then
		error(
			string.format(
				"%s\n  expected: %s\n  actual:   %s",
				msg or "assertion failed",
				vim.inspect(expected),
				vim.inspect(actual)
			),
			2
		)
	end
end

-- Stub clipboard + notifications so tests run cleanly headless
local clipboard
local last_notify
---@diagnostic disable-next-line: duplicate-set-field
vim.fn.setreg = function(_, val)
	clipboard = val
end
---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function(msg)
	last_notify = msg
end

-- Create a temporary directory with real files for fs_stat / buffer tests
local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir .. "/src/components", "p")
vim.fn.mkdir(tmpdir .. "/lua/plugins", "p")

local file_a = tmpdir .. "/lua/plugins/fzf-lua.lua"
local file_b = tmpdir .. "/lua/plugins/mini-files.lua"
local file_c = tmpdir .. "/src/components/button.test.ts"
for _, p in ipairs({ file_a, file_b, file_c }) do
	vim.fn.writefile({ "-- test" }, p)
end

vim.cmd("cd " .. vim.fn.fnameescape(tmpdir))

-- Open buffers A and B
vim.cmd("edit " .. vim.fn.fnameescape(file_a))
local buf_a = vim.api.nvim_get_current_buf()
vim.cmd("badd " .. vim.fn.fnameescape(file_b))
local buf_b = vim.fn.bufnr(file_b)
-- Switch to a scratch buffer to simulate fzf terminal window being focused
vim.cmd("enew")

io.write("file-utils.lua\n")

test("create_short_path keeps up to last 3 segments", function()
	assert_eq(file_utils.create_short_path("a/b/c/d.lua"), "b/c/d.lua")
	assert_eq(file_utils.create_short_path("a/b.lua"), "a/b.lua")
	assert_eq(file_utils.create_short_path("foo.lua"), "foo.lua")
	assert_eq(file_utils.create_short_path("src/components/button.test.ts"), "src/components/button.test.ts")
end)

test("copy_buffer_filenames: 0 tabbed items copies only active buffer via __CTX", function()
	clipboard = nil
	file_utils.copy_buffer_filenames_to_clipboard({}, {
		header = "",
		prefix = "- ",
		include_current = true,
		fzf_opts = { __CTX = { bufnr = buf_a } },
	})
	assert_eq(clipboard, "- lua/plugins/fzf-lua.lua")
	assert_eq(last_notify, "Copied 1 filename(s) to clipboard")
end)

test("copy_buffer_filenames: 1 tabbed buffer copies active + tabbed buffer", function()
	clipboard = nil
	file_utils.copy_buffer_filenames_to_clipboard({ "[" .. buf_b .. "] mini-files.lua\226\128\130lua/plugins" }, {
		header = "",
		prefix = "- ",
		include_current = true,
		fzf_opts = { __CTX = { bufnr = buf_a } },
	})
	assert_eq(clipboard, "- lua/plugins/fzf-lua.lua\n- lua/plugins/mini-files.lua")
	assert_eq(last_notify, "Copied 2 filename(s) to clipboard")
end)

test("copy_buffer_filenames: tabbing active buffer deduplicates to 1 entry", function()
	clipboard = nil
	file_utils.copy_buffer_filenames_to_clipboard({ "[" .. buf_a .. "] fzf-lua.lua\226\128\130lua/plugins" }, {
		header = "",
		prefix = "- ",
		include_current = true,
		fzf_opts = { __CTX = { bufnr = buf_a } },
	})
	assert_eq(clipboard, "- lua/plugins/fzf-lua.lua")
	assert_eq(last_notify, "Copied 1 filename(s) to clipboard")
end)

test("copy_filenames: include_current=false copies only selected files", function()
	clipboard = nil
	file_utils.copy_filenames_to_clipboard({ file_b, file_c }, {
		header = "",
		prefix = "- ",
		include_current = false,
		fzf_opts = { __CTX = { bufnr = buf_a } },
	})
	assert_eq(clipboard, "- lua/plugins/mini-files.lua\n- src/components/button.test.ts")
end)

test("copy_filenames: handles path.filename_first formatted entries with multi-dot names", function()
	clipboard = nil
	file_utils.copy_filenames_to_clipboard({ " M  button.test.ts\226\128\130src/components" }, {
		header = "",
		prefix = "- ",
		include_current = false,
	})
	assert_eq(clipboard, "- src/components/button.test.ts")
end)

test("copy_filenames: non-empty header is prepended with newline", function()
	clipboard = nil
	file_utils.copy_filenames_to_clipboard({ file_a }, {
		header = "Context:",
		prefix = "- ",
		include_current = false,
	})
	assert_eq(clipboard, "Context:\n- lua/plugins/fzf-lua.lua")
end)

vim.fn.delete(tmpdir, "rf")

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
if failed > 0 then
	os.exit(1)
end
