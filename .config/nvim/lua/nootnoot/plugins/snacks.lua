return {
	"folke/snacks.nvim",
	priority = 1000,
	lazy = false,
	---@type snacks.Config
	opts = {
		bigfile = { enabled = true },
		indent = { enabled = true },
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
		scope = { enabled = true },
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
