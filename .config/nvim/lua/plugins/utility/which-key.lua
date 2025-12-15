return {
  "folke/which-key.nvim",
  event = "VeryLazy",
  init = function()
    vim.o.timeout = true
    vim.o.timeoutlen = 500
  end,
  ---@module "which-key"
  ---@type wk.Opts
  opts = {
    preset = "helix",
    show_help = false,
  },
}
