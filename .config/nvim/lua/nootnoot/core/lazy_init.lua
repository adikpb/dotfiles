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
	{ import = "nootnoot.plugins" },
	{ import = "nootnoot.plugins.lsp" },
	{ import = "nootnoot.plugins.editing-support" },
	{ import = "nootnoot.plugins.git" },
	{ import = "nootnoot.plugins.theming" },
	{ import = "nootnoot.plugins.utility" },
}, {
	change_detection = { notify = false },
	defaults = { lazy = true },
	dev = {
		path = "~/neovim-plugins",
		fallback = true,
	},
})
