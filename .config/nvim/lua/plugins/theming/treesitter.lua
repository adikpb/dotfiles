return {
  "nvim-treesitter/nvim-treesitter",
  lazy = false,
  branch = "main",
  build = ":TSUpdate",
  config = function()
    require("nvim-treesitter").install({
      "bash",
      "css",
      "diff",
      "fish",
      "git_rebase",
      "gitcommit",
      "gitignore",
      "html",
      "javascript",
      "kitty",
      "lua",
      "markdown",
      "markdown_inline",
      "python",
      "regex",
      "rust",
      "vim",
      "vimdoc",
    })
  end,
}
