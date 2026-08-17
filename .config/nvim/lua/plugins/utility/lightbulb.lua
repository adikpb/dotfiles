return {
  "kosayoda/nvim-lightbulb",
  event = "LspAttach",
  ---@module "nvim-lightbulb"
  ---@type nvim-lightbulb.Config
  opts = {
    autocmd = { enabled = true },
    code_lenses = true,
    sign = {enabled = false},
    virtual_text = {enabled = true}
  },
}
