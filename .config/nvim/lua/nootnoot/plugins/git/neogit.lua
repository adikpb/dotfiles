return {
	"NeogitOrg/neogit",
	event = { "VeryLazy" },
	dependencies = {
		"nvim-lua/plenary.nvim",
		"sindrets/diffview.nvim",
		"folke/snacks.nvim",
	},
	keys = { { "<leader>gg", "<cmd>Neogit<cr>", desc = "[N]eo [G]it" } },
	config = true,
}
