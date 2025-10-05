---@type table<string, vim.lsp.Config>
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
local formatters = {
  stylua = {},
  ruff = {},
  ["clang-format"] = {},
  prettier = {},
}
local tools = { mmdc = {} } -- not available in brew
local manually_installed_servers = {}
tools = vim.tbl_keys(vim.tbl_deep_extend("force", tools, servers, formatters))
local ensure_installed = vim.tbl_filter(function(name)
  return not vim.tbl_contains(manually_installed_servers, name)
end, tools)

return {
  "WhoIsSethDaniel/mason-tool-installer.nvim",
  event = { "BufReadPost", "BufNewFile" },
  cmd = { "LspInfo", "LspInstall", "LspUninstall", "Mason" },
  dependencies = {
    "saghen/blink.cmp",
    {
      "mason-org/mason-lspconfig.nvim",
      dependencies = {
        "neovim/nvim-lspconfig",
        {
          "mason-org/mason.nvim",
          opts = {},
        },
      },
      opts = {
        automatic_enable = true,
      },
    },
  },
  config = function()
    local blink_cmp = require("blink.cmp")
    local mason_tool_installer = require("mason-tool-installer")

    vim.api.nvim_create_autocmd("LspAttach", {
      group = vim.api.nvim_create_augroup("UserLspConfig", { clear = true }),
      callback = function(ev)
        vim.lsp.inlay_hint.enable(true, { bufnr = ev.buf })
        vim.diagnostic.config({
          virtual_lines = {
            current_line = true,
          },
        })
      end,
    })

    vim.api.nvim_create_autocmd("LspAttach", {
      group = vim.api.nvim_create_augroup("LspAttachDisableRuffHover", { clear = true }),
      callback = function(args)
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if client == nil then
          return
        end
        if client.name == "ruff" then
          client.server_capabilities.hoverProvider = false
        end
      end,
      desc = "LSP: Disable hover capability from Ruff",
    })

    local client_cap = vim.lsp.protocol.make_client_capabilities()
    client_cap = vim.tbl_deep_extend("force", client_cap, blink_cmp.get_lsp_capabilities())
    client_cap = vim.tbl_deep_extend("force", client_cap, {
      textDocument = {
        foldingRange = {
          dynamicRegistration = false,
          lineFoldingOnly = true,
        },
      },
    })

    for server_name, server_config in pairs(servers) do
      server_config.capabilities = vim.tbl_deep_extend("force", client_cap, server_config.capabilities or {})
      vim.lsp.config(server_name, server_config)
    end

    mason_tool_installer.setup({
      auto_update = true,
      run_on_start = true,
      ensure_installed = ensure_installed,
    })
  end,
}
