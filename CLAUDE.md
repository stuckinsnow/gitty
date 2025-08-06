# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Gitty is a Neovim plugin that provides a beautiful GitHub and Git UI with fuzzy pickers, previews, and interactive workflows. It's built in Lua and integrates with GitHub CLI (`gh`), fzf-lua, and other external tools to provide a seamless Git/GitHub experience within Neovim.

## Architecture

### Core Structure
- `lua/gitty/init.lua` - Main entry point with setup() function and direct access methods
- `lua/gitty/config.lua` - Configuration management with defaults
- `plugin/gitty.lua` - Plugin loading and user command registration

### Provider System
All major features are organized as providers in `lua/gitty/providers/`:
- `github-prs.lua` - Pull request management
- `github-issues.lua` - Issue management  
- `github-notifications.lua` - GitHub notifications
- `github-workflows.lua` - GitHub Actions workflows
- `github-create-pr.lua` - PR creation workflow
- `github-create-issue.lua` - Issue creation workflow
- `github-get-log.lua` - Branch and commit log management
- `github-compare/` - Advanced comparison and diff functionality (modular sub-system)

### GitHub Compare Sub-system
The compare functionality is split across multiple modules:
- `init.lua` - Main entry point with UI selection menu
- `comparison-utils.lua` - Core comparison logic
- `validation-utils.lua` - Input validation
- `picker-utils.lua` - FZF picker implementations
- `minidiff-utils.lua` - Mini.diff integration
- `file-view-utils.lua` - File viewing at specific commits
- `blame-utils.lua` - Git blame functionality
- `github-compare-ai.lua` - AI-powered diff analysis

### Utilities
- `lua/gitty/utilities/github-utils.lua` - GitHub API helpers
- `lua/gitty/utilities/markdown-utils.lua` - Markdown rendering
- `lua/gitty/utilities/spinner-utils.lua` - Loading spinners

## Dependencies

Required external tools (checked in `init.lua:57`):
- `gh` (GitHub CLI)
- `fzf` (fuzzy finder)
- `git`

Optional tools for enhanced features:
- `bat` (colored previews)
- `glow` (markdown rendering)
- `delta` (enhanced diffs)
- `mini.diff` (inline diffs)

Required Neovim plugins:
- `nvim-lua/plenary.nvim`
- `ibhagwan/fzf-lua`

## Key Commands

Development/testing commands:
- `:GittySetup` - Initialize or reinitialize the plugin
- `:lua require("gitty").setup()` - Setup with defaults

Main user commands:
- `:FzfGithubPrs` - List/preview Pull Requests
- `:FzfGithubIssues` - List/preview Issues  
- `:FzfGithubNotifications` - List notifications
- `:FzfGithubWorkflows` - List/preview workflows
- `:FzfGithubBranches` - List/preview branches
- `:FzfCreatePr` - Create new Pull Request
- `:FzfCreateIssue` - Create new Issue

## Default Keymaps

The plugin sets up these keymaps in `github-compare/init.lua:77-79`:
- `<leader>g2` - Git compare (commits, branches, etc.)
- `<leader>g3` - Mini diff (inline diff with commit)  
- `<leader>g3` (visual) - Mini diff for selection

## Development Patterns

### Provider Setup Pattern
Each provider follows this pattern:
1. Implement core functionality
2. Export a `setup()` function that registers commands/keymaps
3. Get called from main `init.lua` setup

### FZF Integration
- Uses fzf-lua for all pickers
- Implements custom actions for `<CR>`, `<C-v>`, `<C-e>`, `<C-d>`, `<C-x>`, `<C-p>`
- Provides async loading with spinners for better UX

### Error Handling
- Validates dependencies before setup
- Uses vim.notify for user feedback
- Gracefully handles missing tools

## Configuration

The plugin uses a simple configuration system:
- Defaults in `config.lua` 
- User options merged via `vim.tbl_deep_extend`
- Current options: `spinner_enabled`, `preview_width`, `preview_height`

## Testing/Development

No formal test framework is present. Development workflow:
1. Use `:GittySetup` to reinitialize after changes
2. Test individual providers via their exported functions
3. Check dependency validation with `require("gitty").check_dependencies()`