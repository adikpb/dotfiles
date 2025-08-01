return {
  { "kevinhwang91/promise-async" },
  {
    "kevinhwang91/nvim-ufo",
    event = { "LspAttach" },
    dependencies = {
      "chrisgrieser/nvim-origami",
      opts = true,
    },
    opts = true,
    config = function(opts)
      local ufo = require("ufo")

      -- vim.o.foldcolumn = "1" -- '0' is not bad
      -- Using ufo provider need a large value,
      -- feel free to decrease the value
      vim.o.foldlevel = 99
      vim.o.foldlevelstart = 99
      vim.o.foldenable = true

      local map = vim.keymap.set
      map("n", "zR", ufo.openAllFolds, { desc = "Open all folds" })
      map("n", "zM", ufo.closeAllFolds, { desc = "Close all folds" })
      map("n", "zr", ufo.openFoldsExceptKinds, { desc = "Fold less" })
      map("n", "zm", ufo.closeFoldsWith, { desc = "Fold more" })
      map("n", "K", function()
        local winid = ufo.peekFoldedLinesUnderCursor(true)
        if not winid then
          vim.lsp.buf.hover()
        end
      end, { desc = "LSP Hover/Peek Fold", buffer = true })

      ufo.setup(opts)
    end,
  },
}
