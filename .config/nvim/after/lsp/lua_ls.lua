return {
  ---@module "lspconfig"
  ---@type lspconfig.settings.lua_ls
  settings = {
    Lua = {
      completion = {
        callSnippet = "Replace",
      },
      diagnostics = {
        disable = {
          "missing-fields",
        },
      },
    },
  },
}
