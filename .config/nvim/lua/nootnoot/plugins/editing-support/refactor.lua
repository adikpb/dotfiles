return {
  "ThePrimeagen/refactoring.nvim",
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
  },
  opts = true,
  keys = {
    {
      "<leader>rr",
      function()
        require("refactoring").select_refactor()
      end,
      mode = { "n", "x" },
      desc = "Refactor",
    },
  },
}
