vim.g.mapleader = " "
vim.g.maplocaleader = " "
vim.keymap.set("n", "<leader>pv", vim.cmd.Ex, { desc = "Project View" })

-- Move lines in Visual mode along with proper indentation
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move Lines Up" })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move Lines Down" })

-- Page up and down with cursor in middle in Normal Mode
vim.keymap.set("n", "<C-u>", "<C-u>zz", { desc = "Move Page Up" })
vim.keymap.set("n", "<C-d>", "<C-d>zz", { desc = "Move Page Down" })

-- Cursor stays in middle during search
vim.keymap.set("n", "n", "nzzzv", { desc = "Next: Cursor in Middle During Search" })
vim.keymap.set("n", "N", "Nzzzv", { desc = "Previous: Cursor in Middle During Search" })

-- System clipboard
vim.keymap.set({ "n", "v" }, "<leader>y", [["+y]], { desc = "Copy to Clipboard" })

-- Delete to void in either Visual or Normal mode
-- vim.keymap.set({ "n", "v" }, "<leader>d", [["_d]], { desc = "Delete to Void" })

-- Prevent `Q` presses in Normal mode
vim.keymap.set("n", "Q", "<nop>")

-- -- Navigate Quick Fix in Normal Mode
-- vim.keymap.set("n", "<C-k>", "<cmd>cnext<CR>zz", { desc = "QuickFix: Next" })
-- vim.keymap.set("n", "<C-j>", "<cmd>cprev<CR>zz", { desc = "QuickFix: Previous" })
-- vim.keymap.set("n", "<leader>k", "<cmd>lnext<CR>zz", { desc = "Location: Next" })
-- vim.keymap.set("n", "<leader>j", "<cmd>lprev<CR>zz", { desc = "Location: Previous" })

-- Replace current word you are on
vim.keymap.set(
  { "n", "v" },
  "<leader>rw",
  [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]],
  { desc = "[R]eplace Current [W]ord You Are On" }
)
