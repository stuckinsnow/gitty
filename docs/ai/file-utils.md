# `gitty.utilities.file-utils` Notes

## Purpose & Usage
- `lua/gitty/utilities/file-utils.lua` formats paths (last 3 segments via `create_short_path`), deduplicates entries, and copies them to the `+` register.
- Used internally by `lua/gitty/providers/github-compare/picker-utils.lua` and externally by `fzf-lua` user configs (`buffers`, `git.status`, `files`).

## `fzf-lua` Buffers Copy Behavior
- In `fzf`, `{+}` falls back to the item under the cursor when 0 items are marked with `<Tab>`.
- To copy **only the active buffer** when nothing is tabbed, and **active + tabbed buffers** when items are tabbed:
  - Use `exec_silent = true`, `postfix = "abort"`, and `field_index = "$FZF_SELECT_COUNT {+}"`.
  - Check `tonumber(table.remove(selection, 1)) or 0`: if `0`, pass `{}` instead of `selection`.
  - Pass `fzf_opts = opts` so `include_current = true` resolves `opts.__CTX.bufnr` (the real active buffer while `fzf`'s terminal window is still focused).
  - Keep `require("gitty.utilities.file-utils")` inside `fn` so eager `fzf-lua` configs don't force-load `gitty` before `VeryLazy`.

## `fzf-lua` `git.status` & `files` Copy Behavior
- Uses `include_current = false`: pressing `<ctrl-y>` copies the highlighted file under the cursor when 0 items are tabbed, or **only** the tabbed items when 1+ items are marked with `<Tab>`.
- Pass `fzf_opts = opts` from `fn = function(selection, opts)` so `fzf-lua.path.entry_to_file` natively reverses `path.filename_first` / `path.dirname_first` (which separate filename and directory with `<Tab>`). `extract_path` also falls back to splitting on `\t` / en-space / NBSP when `fzf_opts` is omitted.

## Tests
```bash
nvim --headless -u NONE -l tests/file_utils_spec.lua
```
