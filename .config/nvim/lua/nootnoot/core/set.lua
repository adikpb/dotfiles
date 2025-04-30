vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true
vim.opt.wrap = false
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undofile = true
vim.opt.undodir = os.getenv("HOME") .. "/.vim/undodir"
vim.opt.hlsearch = false
vim.opt.incsearch = true
vim.opt.termguicolors = true
vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
vim.opt.isfname:append("@-@")
vim.opt.updatetime = 50
vim.opt.colorcolumn = "80"
vim.opt.mousemoveevent = true
vim.g.is_transparent = true
vim.o.winborder = "rounded"

-- python nvim virtaulenv
vim.g.python3_host_prog = os.getenv("HOME") .. ".local/venvs/pynvim/bin/python"
vim.g.loaded_node_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0

-- if vim.g.neovide then
-- 	-- keymaps
-- 	vim.keymap.set("v", "<D-c>", '"+y') -- Copy
-- 	vim.keymap.set("n", "<D-v>", '"+P') -- Paste normal mode
-- 	vim.keymap.set("v", "<D-v>", '"+P') -- Paste visual mode
-- 	vim.keymap.set("c", "<D-v>", "<C-R>+") -- Paste command mode
-- 	vim.keymap.set("i", "<D-v>", '<ESC>l"+Pli') -- Paste insert mode
-- end
