return {
  "ThePrimeagen/refactoring.nvim",
  opts = {},
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
