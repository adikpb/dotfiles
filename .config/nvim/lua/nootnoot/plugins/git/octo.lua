return {
	"pwntester/octo.nvim",
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-tree/nvim-web-devicons",
		"folke/snacks.nvim",
	},
	keys = { { "<leader>o", "<cmd>Octo actions<cr>", desc = "[O]cto" } },
	opts = { picker = "snacks" },
}
