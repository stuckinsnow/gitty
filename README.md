# Under construction

Install with lazy.nvim:

```lua
    {
      dir = "/path/to//gitty",
      name = "gitty.nvim",
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

Non local, lazy:

```lua
{
  "stuckinsnow/gitty.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "ibhagwan/fzf-lua",
  },
  config = function()
    require("gitty").setup()
  end,
},
```
