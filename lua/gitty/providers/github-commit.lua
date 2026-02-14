local M = {}

local ai = require("gitty.utilities.ai")

function M.commit()
  vim.fn.system("git add .")
  local diff = vim.fn.system("git diff --cached"):gsub("\r", "")
  if diff == "" then
    vim.notify("Nothing staged to commit", vim.log.levels.WARN)
    return
  end

  local diff_stat = vim.fn.system("git diff --cached --stat"):gsub("\r", "")
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

  vim.notify("Generating commit message...", vim.log.levels.INFO)

  ai.run(prompt, function(result, err)
    if err then
      vim.notify("Failed: " .. err, vim.log.levels.ERROR)
      return
    end
    -- Strip markdown code fences if present
    result = result:gsub("^```[^\n]*\n", ""):gsub("\n```%s*$", "")

    vim.ui.select({ "Commit", "Edit", "Cancel" }, {
      prompt = result .. "\n\n",
    }, function(choice)
      if choice == "Commit" then
        vim.system({ "git", "commit", "-m", result }, { text = true }, vim.schedule_wrap(function(obj)
          if obj.code == 0 then
            vim.notify("✓ Committed", vim.log.levels.INFO)
          else
            vim.notify("✗ " .. (obj.stderr or "commit failed"), vim.log.levels.ERROR)
          end
        end))
      elseif choice == "Edit" then
        vim.ui.input({ prompt = "Edit message: ", default = result }, function(edited)
          if edited and edited ~= "" then
            vim.system({ "git", "commit", "-m", edited }, { text = true }, vim.schedule_wrap(function(obj)
              if obj.code == 0 then
                vim.notify("✓ Committed", vim.log.levels.INFO)
              else
                vim.notify("✗ " .. (obj.stderr or "commit failed"), vim.log.levels.ERROR)
              end
            end))
          end
        end)
      end
    end)
  end)
end

function M.setup()
  vim.api.nvim_create_user_command("GittyCommit", M.commit, {})
end

return M
