# ✨ Gitty — Beautiful GitHub & Git UI for Neovim

**Gitty** brings a modern, interactive, and beautiful GitHub and Git workflow to Neovim. It provides fuzzy pickers, previews, and side buffers for PRs, issues, branches, workflows, and more — all with color, async loading, and keyboard-driven UX.

https://github.com/user-attachments/assets/d6e57846-59a2-4038-8ad0-8c97ad6f5274

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

For AI features (commit messages, PR descriptions, commit analysis), you need [opencode](https://github.com/opencode-ai/opencode) installed with Copilot configured.

---

## ⚙️ Configuration

Gitty can be configured with various options:

```lua
require("gitty").setup({
  spinner_enabled = true,               -- Enable loading spinners
  preview_width = 0.6,                  -- Width of preview windows (0.0-1.0)
  preview_height = 0.4,                 -- Height of preview windows (0.0-1.0)
  split_diff_treesitter_left = true,    -- Enable syntax highlighting in left split diff window (current version)
  split_diff_treesitter_right = false,  -- Enable syntax highlighting in right split diff window (commit version)
  -- Commit preview options
  show_commit_files_in_preview = true,  -- Show files changed in commit preview
  enhanced_commit_preview = true,       -- Use enhanced styling (delta + line numbers) in commit preview
})
```

### Configuration Options

- **`spinner_enabled`** (boolean, default: `true`): Show loading spinners during async operations
- **`preview_width`** (number, default: `0.6`): Width ratio for preview windows (0.0 to 1.0)
- **`preview_height`** (number, default: `0.4`): Height ratio for preview windows (0.0 to 1.0)
- **`split_diff_treesitter_left`** (boolean, default: `true`): Enable tree-sitter syntax highlighting in the left split diff window (current version). When disabled, shows plain text for better performance and focus on differences.
- **`split_diff_treesitter_right`** (boolean, default: `false`): Enable tree-sitter syntax highlighting in the right split diff window (commit version). When disabled, shows plain text for better performance and focus on differences.

#### Commit Preview Options

- **`show_commit_files_in_preview`** (boolean, default: `true`): Show files changed at the top of commit previews. When enabled, commit pickers will display a list of changed files followed by the git diff. When disabled, shows only the standard git commit details.
- **`enhanced_commit_preview`** (boolean, default: `true`): Use enhanced styling with delta and line numbers in commit previews. When enabled, uses delta for beautiful syntax-highlighted diffs with line numbers. When disabled, uses standard git colored output.

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
| `<leader>g4` | n    | File History & Browse                  |
| `<leader>g6` | n    | AI Tools (commit, analyse)             |

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

**In comparison pickers:**

- `<CR>`: Open diffview / minidiff comparisons
- `<C-e>`: Show diff in side buffer
- `<C-v>`: View file at specific commit (3-pane layout)

**File History picker:**

- `<CR>`: Copy commit hash to clipboard
- `<C-v>`: View file at that commit

Suggested keymaps for your configuration:

```lua
local compare = require("gitty.providers.github-compare.init")

-- Menus
vim.keymap.set("n", "<leader>g2", compare.git_compare_commits, { desc = "Git Compare" })
vim.keymap.set("n", "<leader>g3", compare.compare_with_minidiff, { desc = "Git Mini Diff" })
vim.keymap.set("v", "<leader>g3", compare.compare_selected_with_minidiff, { desc = "Git Mini Diff Selection" })
vim.keymap.set("n", "<leader>g4", compare.git_file_history, { desc = "Git File History" })
vim.keymap.set("n", "<leader>g6", compare.git_ai_tools, { desc = "Git AI Tools" })

-- GitHub
vim.keymap.set("n", "<leader>g1n", "<cmd>FzfGithubNotifications<CR>", { desc = "GitHub Notifications" })
vim.keymap.set("n", "<leader>g1p", "<cmd>FzfGithubPrs<CR>", { desc = "GitHub PRs" })
vim.keymap.set("n", "<leader>g1w", "<cmd>FzfGithubWorkflows<CR>", { desc = "Github Workflows" })
vim.keymap.set("n", "<leader>g1i", "<cmd>FzfGithubIssues<CR>", { desc = "GitHub Issues" })
vim.keymap.set("n", "<leader>g1c", "<cmd>FzfCreateIssue<CR>", { desc = "Create GitHub Issue" })
vim.keymap.set("n", "<leader>g1C", "<cmd>FzfCreatePr<CR>", { desc = "Create GitHub PR" })
vim.keymap.set("n", "<leader>g1B", "<cmd>FzfGithubBranches<CR>", { desc = "List Branch Information" })

-- Utils
vim.keymap.set("n", "<leader>c0j", compare.compare_json_files, { desc = "Compare JSON Files" })
```

---

## 🧑‍💻 Commands

| Command                   | Description                              |
| ------------------------- | ---------------------------------------- |
| `:FzfGithubPrs`           | List and preview GitHub Pull Requests    |
| `:FzfGithubNotifications` | List Github Notifications                |
| `:FzfGithubIssues`        | List and preview GitHub Issues           |
| `:FzfGithubBranches`      | List and preview GitHub Branches         |
| `:FzfGithubWorkflows`     | List and preview GitHub Workflows & runs |
| `:FzfCreatePr`            | Create a new Pull Request                |
| `:FzfCreateIssue`         | Create a new Issue                       |
| `:GittySetup`             | (Re)initialize gitty                     |
| `:GittyCommit`            | AI-generated commit message              |

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

### 📋 Copy Filenames Utility

Gitty provides a reusable utility for copying filenames to clipboard with smart path shortening. This is useful for adding context to AI prompts or documentation.

**For FZF buffer pickers** (extracts buffer numbers):

```lua
require("fzf-lua").buffers({
  actions = {
    ["ctrl-y"] = {
      fn = function(selection)
        require("gitty.utilities.file-utils").copy_buffer_filenames_to_clipboard(selection)
      end,
    },
  },
})
```

**For regular file pickers** (direct file paths):

```lua
require("fzf-lua").files({
  actions = {
    ["ctrl-y"] = {
      fn = function(selection)
        require("gitty.utilities.file-utils").copy_filenames_to_clipboard(selection)
      end,
    },
  },
})
```

**Customization options**:

```lua
-- Custom header, prefix, and exclude current buffer
require("gitty.utilities.file-utils").copy_filenames_to_clipboard(selection, {
  header = "Context: ",
  prefix = "* ",
  include_current = false
})
```

**Output format**:

```
Context:
- providers/github-compare/picker-utils.lua
- utilities/file-utils.lua
- init.lua
```

Path shortening shows the last 3 directory levels for better readability while maintaining context.

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
- GittySplitLeft: Highlights for the left split window.
- GittySplitRight: Highlights for the right split window.
- GittySplitLeftTitle: Highlights for the left split title.
- GittySplitRightTitle: Highlights for the right split title.
```

---

### 🤖 AI Features

Gitty uses [opencode](https://github.com/opencode-ai/opencode) with `github-copilot/gpt-4.1` for:

- **AI Commit** (`<leader>g6`) — Generate commit messages from staged changes
- **Diff Analyse** (`<leader>g6`) — Analyze diffs between commits for bugs/regressions
- **AI PR descriptions** (`<leader>g1C`) — Auto-generate PR descriptions when creating PRs

Requires `opencode` installed with Copilot configured.
