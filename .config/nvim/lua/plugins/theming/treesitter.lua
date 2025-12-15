return {
  "nvim-treesitter/nvim-treesitter",
  lazy = false,
  branch = "main",
  build = ":TSUpdate",
  config = function()
    require("nvim-treesitter").install({
      "bash",
      "css",
      "fish",
      "html",
      "javascript",
      "lua",
      "markdown",
      "markdown_inline",
      "norg",
      "python",
      "regex",
      "rust",
      "vim",
      "vimdoc",
    })
  end,
}
