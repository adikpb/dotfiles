return {
	"pwntester/octo.nvim",
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-tree/nvim-web-devicons",
		"folke/snacks",
	},
	keys = { { "<leader>o", "<cmd>Octo actions<cr>", desc = "[O]cto" } },
	opts = { backend = "snacks" },
}
