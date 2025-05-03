local servers = {
  lua_ls = {
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
  },
  rust_analyzer = {
    ["rust-analyzer "] = {
      settings = {
        cargo = {
          allFeatures = true,
        },
      },
    },
  },
  basedpyright = {},
  clangd = {},
  jdtls = {},
  marksman = {},
  taplo = {},
}
local formatters = { stylua = {}, ruff = {}, ["clang-format"] = {} }
local manually_installed_servers = {}
local tools
tools = vim.tbl_keys(vim.tbl_deep_extend("force", {}, servers, formatters))
local ensure_installed = vim.tbl_filter(function(name)
  return not vim.tbl_contains(manually_installed_servers, name)
end, tools)

return {
  "neovim/nvim-lspconfig",
  event = { "BufReadPost", "BufNewFile" },
  cmd = { "LspInfo", "LspInstall", "LspUninstall", "Mason" },
  dependencies = {
    "saghen/blink.cmp",
    { "williamboman/mason.nvim", opts = true },
    "williamboman/mason-lspconfig.nvim",
    "WhoIsSethDaniel/mason-tool-installer.nvim",
  },
  config = function()
    local blink_cmp = require("blink.cmp")
    local mason = require("mason")
    local mason_lspconfig = require("mason-lspconfig")
    local mason_tool_installer = require("mason-tool-installer")

    vim.api.nvim_create_autocmd("LspAttach", {
      group = vim.api.nvim_create_augroup("UserLspConfig", {}),
      callback = function(ev)
        vim.lsp.inlay_hint.enable(true, { bufnr = ev.buf })
        vim.diagnostic.config({
          virtual_lines = {
            current_line = true,
          },
        })
      end,
    })

    local cap = vim.lsp.protocol.make_client_capabilities()
    cap = vim.tbl_deep_extend("force", cap, blink_cmp.get_lsp_capabilities())
    cap = vim.tbl_deep_extend("force", cap, {
      textDocument = {
        foldingRange = {
          dynamicRegistration = false,
          lineFoldingOnly = true,
        },
      },
    })

    mason_tool_installer.setup({
      auto_update = true,
      run_on_start = false,
      start_delay = 3000,
      debounce_hours = 12,
      ensure_installed = ensure_installed,
    })
    vim.api.nvim_command("MasonToolsClean")
    vim.api.nvim_command("MasonToolsUpdate")

    -- mason.setup()

    mason_lspconfig.setup({
      handlers = {
        function(server_name)
          if server_name == "ruff" then
            return
          end
          local server_config = servers[server_name] or {}
          -- This handles overriding only values explicitly passed
          -- by the server configuration above. Useful when disabling
          -- certain features of an LSP (for example, turning off formatting for tsserver)
          server_config.capabilities = vim.tbl_deep_extend("force", {}, cap, server_config.capabilities or {})
          vim.lsp.config(server_name, server_config)
          vim.lsp.enable(server_name)
        end,
      },
    })
  end,
}
