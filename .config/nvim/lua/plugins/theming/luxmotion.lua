return {
  "LuxVim/nvim-luxmotion",
  event = { "VeryLazy" },
  config = function()
    require("luxmotion").setup({
      cursor = { enabled = false },
      scroll = {
        duration = 250,
        easing = "linear",
      },
    })
  end,
}
