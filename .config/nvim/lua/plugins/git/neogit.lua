return {
  "NeogitOrg/neogit",
  dependencies = {
    "esmuellert/codediff.nvim",
    "folke/snacks.nvim",
  },
  keys = { { "<leader>gg", "<cmd>Neogit<cr>", desc = "[N]eo [G]it" } },
  ---@module "neogit"
  ---@type NeogitConfig
  opts = { graph_style = "kitty", process_spinner = true },
}
