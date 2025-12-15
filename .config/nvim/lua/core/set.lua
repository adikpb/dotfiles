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
vim.opt.incsearch = true
vim.opt.termguicolors = true
vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
-- vim.opt.isfname:append("@-@")
vim.opt.updatetime = 50
vim.opt.colorcolumn = "80"
vim.opt.mousemoveevent = true
vim.o.winborder = "rounded"

vim.g.loaded_node_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0

-- https://github.com/Wansmer/nvim-config/blob/9f1bc81e32eb32000bad80f9912238 f
-- 9e36a903a/lua/modules/key_listener.lua
local listener_ls = vim.api.nvim_create_namespace("key_listener")

---Deleting hlsearch when it already no needed
local function toggle_hlsearch(char)
  local keys = { "<CR>", "n", "N", "*", "#", "?", "/" }
  local new_hlsearch = vim.tbl_contains(keys, char) and 1 or 0

  if vim.api.nvim_get_vvar("hlsearch") ~= new_hlsearch then
    vim.api.nvim_set_vvar("hlsearch", new_hlsearch)
  end
end

---@param char string
local function key_listener(char)
  local key = vim.fn.keytrans(char)
  local mode = vim.fn.mode()
  if mode == "n" then
    toggle_hlsearch(key)
  end
end

vim.on_key(key_listener, listener_ls)

-- if vim.g.neovide then
-- 	-- keymaps
-- 	vim.keymap.set("v", "<D-c>", '"+y') -- Copy
-- 	vim.keymap.set("n", "<D-v>", '"+P') -- Paste normal mode
-- 	vim.keymap.set("v", "<D-v>", '"+P') -- Paste visual mode
-- 	vim.keymap.set("c", "<D-v>", "<C-R>+") -- Paste command mode
-- 	vim.keymap.set("i", "<D-v>", '<ESC>l"+Pli') -- Paste insert mode
-- end
