return {
	"pwntester/octo.nvim",
	event = { "VeryLazy" },
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-telescope/telescope.nvim",
		"nvim-tree/nvim-web-devicons",
	},
	keys = { { "<leader>o", "<cmd>Octo actions<cr>", desc = "[O]cto" } },
	opts = true,
}
