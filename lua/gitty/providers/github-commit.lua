local M = {}

local ai = require("gitty.utilities.ai")

function M.commit()
  vim.fn.system("git add .")
  local exclude = ":(exclude)**/pnpm-lock.yaml (exclude)**/package-lock.json (exclude)**/yarn.lock"
  local diff = vim.fn.system("git diff --cached -- . " .. exclude):gsub("\r", "")
  if diff == "" then
    vim.notify("Nothing staged to commit", vim.log.levels.WARN)
    return
  end

  local diff_stat = vim.fn.system("git diff --cached --stat -- . " .. exclude):gsub("\r", "")
  local recent = vim.fn.system("git log --oneline -n 5 --no-merges"):gsub("\r", "")

  local prompt = string.format([[Generate a git commit message for these changes. Rules:
- Imperative form, conventional commit format
- No parentheses after type (e.g. "feat:" not "feat(x):")
- Single title line + bullet points for key changes
- Be concise, no fluff

Recent commits for style reference:
%s

Diff summary:
%s

Full diff:
%s

Reply with ONLY the commit message, nothing else.]], recent, diff_stat, diff)

  ai.run(prompt, function(result, err)
    if err then
      vim.notify("Failed: " .. err, vim.log.levels.ERROR)
      return
    end
    -- Strip markdown code fences if present
    result = result:gsub("^```[^\n]*\n", ""):gsub("\n```%s*$", "")

    -- Show in editable floating buffer
    local lines = vim.split(result, "\n")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = "markdown"
    vim.bo[buf].bufhidden = "wipe"
    vim.diagnostic.enable(false, { bufnr = buf })

    local width = math.min(80, vim.o.columns - 4)
    local height = math.min(#lines + 2, 20)
    local win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = width,
      height = height,
      row = math.floor((vim.o.lines - height) / 2),
      col = math.floor((vim.o.columns - width) / 2),
      style = "minimal",
      border = "rounded",
      title = " Commit (Enter=commit, e=edit, q=cancel) ",
      title_pos = "center",
    })

    local function do_commit()
      local msg = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      vim.api.nvim_win_close(win, true)
      vim.system({ "git", "commit", "-m", msg }, { text = true }, vim.schedule_wrap(function(obj)
        if obj.code == 0 then
          vim.notify("✓ Committed", vim.log.levels.INFO)
        else
          vim.notify("✗ " .. (obj.stderr or "commit failed"), vim.log.levels.ERROR)
        end
      end))
    end

    -- In normal mode: Enter commits as-is, e enters insert to edit, q cancels
    vim.keymap.set("n", "<CR>", do_commit, { buffer = buf })
    vim.keymap.set("n", "e", function()
      vim.cmd("startinsert")
    end, { buffer = buf })
    vim.keymap.set("n", "q", function()
      vim.api.nvim_win_close(win, true)
    end, { buffer = buf })
    -- After editing: Ctrl-s commits
    vim.keymap.set("i", "<C-s>", function()
      vim.cmd("stopinsert")
      do_commit()
    end, { buffer = buf })
  end)
end

function M.setup()
  vim.api.nvim_create_user_command("GittyCommit", M.commit, {})
end

return M
