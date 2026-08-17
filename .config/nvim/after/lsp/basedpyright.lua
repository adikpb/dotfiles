return {
  ---@module "lspconfig"
  ---@type lspconfig.settings.basedpyright
  settings = {
    basedpyright = {
      analysis = {
        diagnosticMode = "workspace",
      },
    },
  },
}
