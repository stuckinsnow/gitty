# ✨ Gitty — Beautiful GitHub & Git UI for Neovim

**Gitty** brings a modern, interactive, and beautiful GitHub and Git workflow to Neovim. It provides fuzzy pickers, previews, and side buffers for PRs, issues, branches, workflows, and more — all with color, async loading, and keyboard-driven UX.

https://github.com/user-attachments/assets/d6e57846-59a2-4038-8ad0-8c97ad6f5274

Note, 75% of this project was coded using AI assistance, and I am new to Lua. This is not representative of my code quality, so please do not judge the quality of my code based on this project.

---

## 🚀 Features

- **Fuzzy pickers** for GitHub Pull Requests, Issues, Branches, Commits, and Workflows.
- **Rich previews**: Markdown rendered with color, commit diffs, PR/issue details, and more.
- **Create PRs and Issues** in a side buffer with templates and AI-assisted descriptions.
- **View and review** PR comments, issue comments, and workflow logs in split/floating windows.
- **Inline mini diff**: Compare current buffer or selection with any commit, accept/reject hunks.
- **Compare commits**: Diffview, inline, or file-at-commit with 3-pane layout.
- **Open on GitHub**: Open PRs, issues, commits, and branches in your browser.
- **Async loading** with spinners for a smooth experience.
- **Keymaps** for quick access to all features.

---

## 📦 Installation

### With [lazy.nvim](https://github.com/folke/lazy.nvim)

**Local/dev:**

```lua
{
  dir = "/path/to/gitty",
  name = "gitty",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "ibhagwan/fzf-lua",
  },
  config = function()
    require("gitty").setup()
  end,
  dev = true,
},
```

**Remote:**

```lua
{
  "stuckinsnow/gitty",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "ibhagwan/fzf-lua",
  },
  config = function()
    require("gitty").setup()
  end,
},
```

For AI assistance to work, you will need to create a new prompt in codecompanion, you can find that at the bottom of this README.

---

## ⚡️ Requirements

- [fzf-lua](https://github.com/ibhagwan/fzf-lua)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [GitHub CLI (`gh`)](https://cli.github.com/)
- [fzf](https://github.com/junegunn/fzf)
- [git](https://git-scm.com/)
- [bat](https://github.com/sharkdp/bat) (for colored previews)
- [glow](https://github.com/charmbracelet/glow) (for markdown rendering)
- [delta](https://github.com/dandavison/delta) (for diffs)
- [mini.diff](https://github.com/echasnovski/mini.nvim) (for inline diff)

---

## 🗝️ Keymaps

| Keymap       | Mode | Action                                 |
| ------------ | ---- | -------------------------------------- |
| `<leader>g2` | n    | Git Compare (commits, branches, etc.)  |
| `<leader>g3` | n    | Mini Diff (inline diff with commit)    |
| `<leader>g3` | v    | Mini Diff (diff selection with commit) |

**In PR/Issue/Commit/Branch pickers:**

- `<CR>`: Default action (diff, open, etc.)
- `<C-v>`: Open details in right buffer (and show comments/reviews if available)
- `<C-e>`: Open details in a new buffer
- `<C-d>`: Diffview for PRs
- `<C-x>`: Open on GitHub in browser
- `<C-p>`: Copy PR commands to clipboard

**In PR/Issue creation buffers:**

- `<CR>`: Submit PR/Issue
- `<leader>q`: Cancel creation
- `<C-s>` (insert): Submit PR/Issue

**In mini diff:**

- `ga`: Accept current hunk/selection
- `gr`: Reject current hunk/selection
- `gq`: Close mini diff

---

## 🧑‍💻 Commands

| Command               | Description                              |
| --------------------- | ---------------------------------------- |
| `:FzfGithubPrs`       | List and preview GitHub Pull Requests    |
| `:FzfGithubIssues`    | List and preview GitHub Issues           |
| `:FzfGithubBranches`  | List and preview GitHub Branches         |
| `:FzfGithubWorkflows` | List and preview GitHub Workflows & runs |
| `:FzfCreatePr`        | Create a new Pull Request                |
| `:FzfCreateIssue`     | Create a new Issue                       |
| `:GittySetup`         | (Re)initialize gitty                     |

---

## 🛠️ Usage

### PRs

- `:FzfGithubPrs` — Fuzzy pick PRs, preview details, diff, open in browser, copy commands, or open reviews.
- `<C-v>` on a PR — Open PR details in a side buffer and show reviews.
- `<C-d>` — Diffview for PR branch/files.
- `<C-p>` — Copy useful PR commands to clipboard.

### Issues

- `:FzfGithubIssues` — Fuzzy pick issues, preview details, open in browser, or open comments.
- `<C-v>` — Open issue details in a side buffer and show comments.

### Branches & Commits

- `:FzfGithubBranches` — List branches, preview latest commit, open on GitHub, or show commits.
- Selecting a branch — Show recent commits, preview details, open commit on GitHub, or open commit message in buffer.

### Workflows

- `:FzfGithubWorkflows` — List workflows, select to view runs, preview run details, open logs in split/floating window.

### Creating PRs & Issues

- `:FzfCreatePr` — Guided PR creation in a side buffer, with commit summary and AI description (if available).
- `:FzfCreateIssue` — Guided issue creation in a side buffer with template.

### Comparing & Diffing

- `<leader>g2` — Compare commits/branches: Diffview, inline, or file-at-commit.
- `<leader>g3` — Mini diff: Inline diff of current buffer with any commit.
- Visual `<leader>g3` — Mini diff: Inline diff of selection with any commit.

---

## 🧩 Extensibility

- All picker actions are customizable via fzf-lua.
- Utility functions for opening buffers, rendering markdown, and more.
- Async helpers for smooth UX.

---

## ✨ Highlights

You will need to set up the following highlights in your Neovim configuration to ensure gitty looks great:

```markdown
- MiniDiffSign: All diff signs in the buffer.
- MiniDiffSignChange: Changed lines line numbers.
- MiniDiffSignAdd: Added lines line numbers.
- MiniDiffSignDelete: Deleted lines line numbers.
- MiniDiffOverAdd: Highlights added lines.
- MiniDiffOverChange: Highlights changed lines.
- MiniDiffOverDelete: Highlights deleted lines.
- MiniDiffOverContext: Highlights context lines in diffs.
- MiniDiffOverContextBuf: Highlights context buffer for added lines.
```

---

## 🤖 CODECOMPANION

CodeCompanion is your AI-powered assistant for coding, offering suggestions, explanations, and code generation to help you be more productive in your development workflow.

```
      ["PR Description"] = {
        strategy = "inline",
        description = "Generate a professional PR description from recent commits",
        opts = {
          short_name = "pr",
        },
        prompts = {
          {
            role = "system",
            content = "You are a senior developer with years of experience. Create professional, concise pull request descriptions that clearly explain what the PR does, and key changes made, list what an experienced developer would mention but do not try impress anyone. The point is to convey information. Format responses as markdown.",
          },
          {
            role = "user",
            content = function()
              -- Get current branch
              local current_branch = vim.fn.system("git rev-parse --abbrev-ref HEAD"):gsub("%s+", "")

              -- Get recent commits with full details
              local commit_details = vim.fn.system("git log --oneline -n 10 --no-merges"):gsub("\r", "")

              -- Get diff summary
              local diff_summary = vim.fn.system("git diff --stat HEAD~5..HEAD"):gsub("\r", "")

              -- Get list of changed files
              local changed_files = vim.fn.system("git diff --name-only HEAD~5..HEAD"):gsub("\r", "")

              return string.format(
                [[
Please create a professional PR description based on the following information:

**Current Branch:** %s

**Recent Commits:**
%s

**Files Changed:**
%s

**Diff Summary:**
%s

Please generate a well-structured PR description that includes:
- A brief summary of what this PR does
- Key changes made
- Any notable implementation details
- Keep it concise but informative

Format the response as markdown.
]],
                current_branch,
                commit_details,
                changed_files,
                diff_summary
              )
            end,
          },
        },
      },

```
