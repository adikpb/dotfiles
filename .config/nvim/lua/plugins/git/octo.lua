return {
  "pwntester/octo.nvim",
  dependencies = {
    "folke/snacks.nvim",
  },
  keys = { { "<leader>o", "<cmd>Octo actions<cr>", desc = "[O]cto" } },
  opts = { picker = "snacks" },
}
