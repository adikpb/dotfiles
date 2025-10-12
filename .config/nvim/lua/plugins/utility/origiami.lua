return {
  "chrisgrieser/nvim-origami",
  event = "VeryLazy",
  opts = {},
  init = function()
    vim.opt.foldlevel = 80
    vim.opt.foldlevelstart = 80
  end,
}
