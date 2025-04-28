return {
  "saghen/blink.cmp",
  dependencies = {
    "rafamadriz/friendly-snippets",
    {
      "Kaiser-Yang/blink-cmp-git",
      dependencies = { "nvim-lua/plenary.nvim" },
    },
  },
  version = "1.*",
  event = { "VeryLazy" },
  ---@module "blink.cmp"
  ---@type blink.cmp.Config
  opts = {
    keymap = { preset = "enter" },
    completion = {
      documentation = { window = { border = "rounded" } },
      ghost_text = { enabled = true },
      menu = { auto_show = true, border = "rounded" },
    },
    cmdline = {
      completion = {
        ghost_text = { enabled = true },
        menu = { auto_show = true },
        list = { selection = { preselect = false } },
      },
    },
    sources = {
      default = { "lazydev", "lsp", "path", "snippets", "git", "buffer" },
      providers = {
        lazydev = {
          name = "LazyDev",
          module = "lazydev.integrations.blink",
          score_offset = 100,
        },
        git = {
          module = "blink-cmp-git",
          name = "Git",
        },
      },
    },
  },
}
