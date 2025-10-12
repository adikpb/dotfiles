-- https://github.com/folke/lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  { import = "plugins" },
  { import = "plugins.debugging" },
  { import = "plugins.editing-support" },
  { import = "plugins.git" },
  { import = "plugins.lsp" },
  { import = "plugins.theming" },
  { import = "plugins.utility" },
}, {
  change_detection = { notify = false },
  defaults = { lazy = true },
  rocks = { enabled = false },
  dev = {
    path = "~/neovim-plugins",
    fallback = true,
  },
  install = { colorscheme = { "tokyonight" } },
})
