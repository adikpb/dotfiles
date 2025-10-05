return {
  "stevearc/conform.nvim",
  event = { "BufWritePre", "BufWritePost" },
  cmd = { "ConformInfo" },
  keys = {
    {
      "<leader>f",
      function()
        require("conform").format({ async = true, lsp_format = "fallback" })
      end,
      mode = { "n", "v" },
      desc = "Format Buffer",
    },
  },
  opts = {
    formatters_by_ft = {
      lua = { "stylua" },
      python = { "ruff_format" },
      c = { "clang-format" },
      _ = { "prettier" },
    },
    default_format_opts = {
      lsp_format = "fallback",
    },
    formatters = {
      ["clang-format"] = { prepend_args = { "-style", "{IndentWidth: 4}" } },
    },
    -- Set up format-on-save
    format_after_save = {
      async = true,
    },
  },
}
