-- load after rtp's has been setup
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function(_)
    -- nvim.undotree
    vim.cmd("packadd nvim.undotree")
    vim.keymap.set("n", "<leader>u", function()
      require("undotree").open({ command = "rightbelow 30vnew" })
    end)
  end,
})
