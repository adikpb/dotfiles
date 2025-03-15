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
			"hrsh7th/nvim-cmp",
			dependencies = {
				-- Sources
				"hrsh7th/cmp-path",
				"hrsh7th/cmp-nvim-lsp",
				"petertriho/cmp-git",
				-- Snippets
				{
					"L3MON4D3/LuaSnip",
					version = "v2.*",
					dependencies = { "rafamadriz/friendly-snippets" },
					config = function()
						require("luasnip.loaders.from_vscode").lazy_load()
					end,
					build = "make install_jsregexp",
				},
				"saadparwaiz1/cmp_luasnip", -- luasnip completions
				"onsails/lspkind.nvim", -- vscode like pictograms
				"lukas-reineke/cmp-under-comparator", -- dunder completions later
			},
			config = function()
				local cmp = require("cmp")
				local lspkind = require("lspkind")
				local luasnip = require("luasnip")

				cmp.setup({
					snippet = {
						expand = function(args)
							luasnip.lsp_expand(args.body)
						end,
					},
					mapping = cmp.mapping.preset.insert({
						["<C-k>"] = cmp.mapping.select_prev_item(), -- previous suggestion
						["<C-j>"] = cmp.mapping.select_next_item(), -- next suggestion
						["<C-b>"] = cmp.mapping.scroll_docs(-4),
						["<C-f>"] = cmp.mapping.scroll_docs(4),
						["<C-Space>"] = cmp.mapping.complete(), -- show completion suggestions
						["<C-e>"] = cmp.mapping.abort(), -- close completion window
						["<CR>"] = cmp.mapping.confirm({ select = true }),
						["<C-l>"] = cmp.mapping(function()
							if luasnip.expand_or_locally_jumpable() then
								luasnip.expand_or_jump()
							end
						end, { "i", "s" }),
						["<C-h>"] = cmp.mapping(function()
							if luasnip.locally_jumpable(-1) then
								luasnip.jump(-1)
							end
						end, { "i", "s" }),
					}),
					sources = cmp.config.sources({
						{ name = "luasnip" }, -- snippets
						{ name = "nvim_lsp" },
						{ name = "git" },
						{ name = "path" }, -- file system paths
					}),
					formatting = {
						format = lspkind.cmp_format({
							maxwidth = 50,
							ellipsis_char = "...",
						}),
					},
					sorting = {
						comparators = {
							cmp.config.compare.offset,
							cmp.config.compare.exact,
							cmp.config.compare.score,
							require("cmp-under-comparator").under,
							cmp.config.compare.kind,
							cmp.config.compare.sort_text,
							cmp.config.compare.length,
							cmp.config.compare.order,
						},
					},
					experimental = { ghost_text = true },
				})
			end,
		},
		{
			"windwp/nvim-autopairs",
			opts = true,
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
		local cmp = require("cmp")
		local cmp_autopairs = require("nvim-autopairs.completion.cmp")
		local cmp_nvim_lsp = require("cmp_nvim_lsp")
		local lspconfig = require("lspconfig")
		local mason = require("mason")
		local mason_lspconfig = require("mason-lspconfig")
		local mason_tool_installer = require("mason-tool-installer")

		cmp.event:on("confirm_done", cmp_autopairs.on_confirm_done())

		vim.api.nvim_create_autocmd("LspAttach", {
			group = vim.api.nvim_create_augroup("UserLspConfig", {}),
			callback = function(ev)
				vim.lsp.inlay_hint.enable(true, { bufnr = ev.buf })
				-- Buffer local mappings.
				-- See `:help vim.lsp.*` for documentation on any of the below functions
				local opts = { buffer = ev.buf, silent = true }

				-- set keybinds
				opts.desc = "Show LSP References"
				vim.keymap.set("n", "grr", "<cmd>Telescope lsp_references<CR>", opts)
				opts.desc = "Show LSP Definitions"
				vim.keymap.set("n", "gd", "<cmd>Telescope lsp_definitions<CR>", opts)
				opts.desc = "Smart Rename"
				vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
				opts.desc = "Code Actions"
				vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts)
				opts.desc = "Restart LSP"
				vim.keymap.set("n", "<leader>lrs", ":LspRestart<CR>", opts)
			end,
		})

		local capabilities = vim.tbl_deep_extend(
			"force",
			{},
			vim.lsp.protocol.make_client_capabilities(),
			cmp_nvim_lsp.default_capabilities()
		)
		capabilities.textDocument.foldingRange = {
			dynamicRegistration = false,
			lineFoldingOnly = true,
		}

		vim.notify(
			"Install List: " .. vim.inspect(ensure_installed),
			vim.log.levels.DEBUG,
			{ title = "lua/nootnoot/plugins/lsp.lua" }
		)

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
					server.capabilities = vim.tbl_deep_extend("force", {}, capabilities, server.capabilities or {})
					lspconfig[server_name].setup(server)
				end,
			},
		})
	end,
}
