return {
	"folke/snacks.nvim",
	priority = 1000,
	lazy = false,
	---@type snacks.Config
	opts = {
		bigfile = { enabled = true },
		indent = {
			enabled = true,
			indent = {
				hl = {
					"SnacksIndent1",
					"SnacksIndent2",
					"SnacksIndent3",
					"SnacksIndent4",
					"SnacksIndent5",
					"SnacksIndent6",
					"SnacksIndent7",
					"SnacksIndent8",
				},
			},
			scope = {
				hl = {
					"SnacksIndentScope1",
					"SnacksIndentScope2",
					"SnacksIndentScope3",
					"SnacksIndentScope4",
					"SnacksIndentScope5",
					"SnacksIndentScope6",
					"SnacksIndentScope7",
					"SnacksIndentScope8",
				},
			},
			config = function(opts, _)
				local tokyonight_util = require("tokyonight.util")
				local indent_hls = opts.indent.hl
				local scope_hls = opts.scope.hl

				for i, _ in ipairs(indent_hls) do
					---@type vim.api.keyset.highlight
					---@diagnostic disable-next-line: assign-type-mismatch
					local hl = vim.api.nvim_get_hl(0, { name = indent_hls[i] })
					local hl_fg = string.format("#%x", hl.fg)

					hl.fg = hl_fg
					vim.api.nvim_set_hl(0, scope_hls[i], hl)

					hl_fg = tokyonight_util.darken(hl_fg, 0.05)
					hl.fg = hl_fg
					vim.api.nvim_set_hl(0, indent_hls[i], hl)
				end
			end,
		},
		input = { enabled = true },
		notifier = {
			enabled = true,
			timeout = 3000,
		},
		picker = {
			enabled = true,
			sources = {
				files = { hidden = true },
				grep = { hidden = true },
				grep_word = { hidden = true },
			},
		},
		quickfile = { enabled = true },
		scroll = { enabled = true },
	},
	keys = {
		{
			"<leader>.",
			function()
				require("snacks").picker()
			end,
			desc = "Show Available Pickers",
		},
		-- Top Pickers & Explorer
		{
			"<leader><space>",
			function()
				require("snacks").picker.smart()
			end,
			desc = "Smart Find Files",
		},
		{
			"<leader>,",
			function()
				require("snacks").picker.buffers()
			end,
			desc = "Buffers",
		},
		{
			"<leader>n",
			function()
				require("snacks").picker.notifications()
			end,
			desc = "Notification History",
		},
		-- find
		{
			"<leader>sf",
			function()
				require("snacks").picker.files()
			end,
			desc = "Find Files",
		},
		{
			"<leader>sr",
			function()
				require("snacks").picker.recent()
			end,
			desc = "Recent",
		},
		-- Grep
		{
			"<leader>sb",
			function()
				require("snacks").picker.grep_buffers()
			end,
			desc = "Grep Open Buffers",
		},
		{
			"<leader>sg",
			function()
				require("snacks").picker.grep()
			end,
			desc = "Grep",
		},
		{
			"<leader>sw",
			function()
				require("snacks").picker.grep_word()
			end,
			desc = "Visual selection or word",
			mode = { "n", "x" },
		},
		-- search
		{
			"<leader>sh",
			function()
				require("snacks").picker.help()
			end,
			desc = "Help Pages",
		},
		{
			"<leader>sR",
			function()
				require("snacks").picker.resume()
			end,
			desc = "Resume",
		},
		-- LSP
		{
			"gd",
			function()
				require("snacks").picker.lsp_definitions()
			end,
			desc = "Goto Definition",
		},
		{
			"gD",
			function()
				require("snacks").picker.lsp_declarations()
			end,
			desc = "Goto Declaration",
		},
		{
			"grr",
			function()
				require("snacks").picker.lsp_references()
			end,
			nowait = true,
			desc = "References",
		},
		{
			"gI",
			function()
				require("snacks").picker.lsp_implementations()
			end,
			desc = "Goto Implementation",
		},
		{
			"gy",
			function()
				require("snacks").picker.lsp_type_definitions()
			end,
			desc = "Goto T[y]pe Definition",
		},
		{
			"<leader>ss",
			function()
				require("snacks").picker.lsp_symbols()
			end,
			desc = "LSP Symbols",
		},
		{
			"<leader>sS",
			function()
				require("snacks").picker.lsp_workspace_symbols()
			end,
			desc = "LSP Workspace Symbols",
		},
		-- Other
		{
			"<leader>rf",
			function()
				require("snacks").rename.rename_file()
			end,
			desc = "Rename File",
		},
		{
			"<leader>nh",
			function()
				require("snacks").notifier.hide()
			end,
			desc = "Dismiss All Notifications",
		},
	},
}
