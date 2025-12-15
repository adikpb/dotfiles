return {
  "kosayoda/nvim-lightbulb",
  event = "LspAttach",
  opts = {
    autocmd = { enabled = true },
    ignore = {
      clients = {},
      ft = {},
      actions_without_kind = false,
    },
  },
}
