return {
  ---@module "lspconfig"
  ---@type lspconfig.settings.rust_analyzer
  ["rust-analyzer"] = {
    settings = {
      cargo = {
        allFeatures = true,
      },
    },
  },
}
