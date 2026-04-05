return {
  "kosayoda/nvim-lightbulb",
  event = "LspAttach",
  opts = {
    autocmd = { enabled = true },
    code_lenses = true,
    sign = {enabled = false},
    float = {enabled = true}
  },
}
