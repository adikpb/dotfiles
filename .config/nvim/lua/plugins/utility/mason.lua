return {
  "WhoIsSethDaniel/mason-tool-installer.nvim",
  event = { "VeryLazy" },
  dependencies = {
    {
      "mason-org/mason-lspconfig.nvim",
      dependencies = { { "mason-org/mason.nvim", opts = {} } },
      opts = { automatic_enable = { exclude = ENSURE_INSTALLED } },
    },
  },
  opts = { auto_update = true, ensure_installed = ENSURE_INSTALLED },
}
