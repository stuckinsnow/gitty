# ✨ gitty — Beautiful GitHub & Git UI for Neovim

**gitty** brings a modern, interactive, and beautiful GitHub and Git workflow to Neovim. It provides fuzzy pickers, previews, and side buffers for PRs, issues, branches, workflows, and more — all with color, async loading, and keyboard-driven UX.

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

## 💡 Tips

- Use `:GittySetup` to reload the plugin after updating.
- Use `<C-v>` in pickers to open details in a side buffer and see comments/reviews.
- Use mini.diff keymaps (`ga`, `gr`, `gq`) for inline editing and review.
- Please ensure you have all dependencies installed.

---

Enjoy a beautiful, modern GitHub workflow in Neovim!  
Questions or suggestions? [Open an issue](https://github.com/stuckinsnow/gitty/issues).
