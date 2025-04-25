local servers = {
	lua_ls = {
		settings = {
			Lua = {
				completion = {
					callSnippet = "Replace",
				},
				-- You can toggle below to ignore Lua_LS's noisy `missing-fields` warnings
				diagnostics = {
					disable = {
						"missing-fields",
					},
				},
			},
		},
	},
	marksman = {},
	pyright = {
		settings = {
			python = {
				analysis = {
					diagnosticMode = "workspace",
				},
			},
		},
	},
	ruff = {
		on_attach = function(client)
			client.server_capabilities.hoverProvider = false
		end,
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
	clangd = {},
	jdtls = {},
	taplo = {},
}
local formatters = { stylua = {}, ruff = {}, ["clang-format"] = {} }
local manually_installed_servers = {}
local mason_tools_to_install = vim.tbl_keys(vim.tbl_deep_extend("force", {}, servers, formatters))
local ensure_installed = vim.tbl_filter(function(name)
	return not vim.tbl_contains(manually_installed_servers, name)
end, mason_tools_to_install)

return {
	"neovim/nvim-lspconfig",
	event = { "BufReadPost", "BufWritePost", "BufNewFile" },
	cmd = { "LspInfo", "LspInstall", "LspUninstall", "Mason" },
	dependencies = {
		{
			"saghen/blink.cmp",
			dependencies = {
				"rafamadriz/friendly-snippets",
				{
					"Kaiser-Yang/blink-cmp-git",
					dependencies = { "nvim-lua/plenary.nvim" },
				},
			},
			version = "1.*",
			---@module 'blink.cmp'
			---@type blink.cmp.Config
			opts = {
				keymap = { preset = "enter" },
				completion = {
					documentation = { window = { border = "rounded" } },
					ghost_text = { enabled = true },
					menu = { auto_show = true, border = "rounded" },
				},
				cmdline = {
					completion = {
						ghost_text = { enabled = true },
						menu = { auto_show = true },
						list = { selection = { preselect = false } },
					},
				},
				sources = {
					default = { "lazydev", "lsp", "path", "snippets", "git", "buffer" },
					providers = {
						lazydev = {
							name = "LazyDev",
							module = "lazydev.integrations.blink",
							score_offset = 100,
						},
						git = {
							module = "blink-cmp-git",
							name = "Git",
						},
					},
				},
			},
		},
		{ "williamboman/mason.nvim", opts = true },
		"williamboman/mason-lspconfig.nvim",
		"WhoIsSethDaniel/mason-tool-installer.nvim",
		{
			"kosayoda/nvim-lightbulb",
			opts = {
				autocmd = { enabled = true },
				ignore = {
					clients = {},
					ft = {},
					actions_without_kind = false,
				},
			},
		},
		{
			"kevinhwang91/nvim-ufo",
			opts = {},
			config = function(opts)
				local ufo = require("ufo")

				-- vim.o.foldcolumn = "1" -- '0' is not bad
				vim.o.foldlevel = 99 -- Using ufo provider need a large value, feel free to decrease the value
				vim.o.foldlevelstart = 99
				vim.o.foldenable = true

				ufo.setup(opts)
			end,
			dependencies = { "kevinhwang91/promise-async" },
		},
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
			end,
		})

		local capabilities = vim.lsp.protocol.make_client_capabilities()
		capabilities = vim.tbl_deep_extend("force", capabilities, blink_cmp.get_lsp_capabilities())
		capabilities = vim.tbl_deep_extend("force", capabilities, {
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

		mason.setup()

		mason_lspconfig.setup({
			handlers = {
				function(server_name)
					local server = servers[server_name] or {}
					-- This handles overriding only values explicitly passed
					-- by the server configuration above. Useful when disabling
					-- certain features of an LSP (for example, turning off formatting for tsserver)
					server.capabilities = vim.tbl_deep_extend("force", {}, server.capabilities or {}, capabilities)
					vim.lsp.config(server_name, server)
					vim.lsp.enable(server_name)
				end,
			},
		})
	end,
}
