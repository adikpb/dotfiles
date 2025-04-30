return {
  "folke/which-key.nvim",
  event = { "VeryLazy" },
  init = function()
    vim.o.timeout = true
    vim.o.timeoutlen = 500
  end,
  ---@module "which-key"
  ---@type wk.Opts
  opts = {
    preset = "helix",
    -- TODO: Workaround till https://github.com/folke/which-key.nvim/issues/967
    show_help = false,
  },
}
