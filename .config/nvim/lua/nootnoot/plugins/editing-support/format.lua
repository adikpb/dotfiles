return {
	"stevearc/conform.nvim",
	event = { "BufReadPre" },
	cmd = { "ConformInfo" },
	keys = {
		{
			"<leader>f",
			function()
				require("conform").format({ async = true, lsp_format = "fallback" })
			end,
			mode = { "n", "v" },
			desc = "Format Buffer",
		},
	},
	opts = {
		formatters_by_ft = {
			lua = { "stylua" },
			python = { "ruff" },
			c = { "clang-format" },
			toml = { "taplo" },
		},
		formatters = { ["clang-format"] = { prepend_args = { "-style", "{IndentWidth: 4}" } } },
		-- Set up format-on-save
		format_after_save = function()
			return {
				async = true,
				timeout_ms = 500,
				lsp_format = "fallback",
			}
		end,
		--- Customize formatters
		-- formatters = {
		-- shfmt = {
		-- prepend_args = { "-i", "2" },
		-- },
		-- },
	},
}
