return {
	"NeogitOrg/neogit",
	event = { "VeryLazy" },
	dependencies = {
		"nvim-lua/plenary.nvim",
		"sindrets/diffview.nvim",
		"nvim-telescope/telescope.nvim",
	},
	keys = { { "<leader>ng", "<cmd>Neogit<cr>", desc = "[N]eo [G]it" } },
	config = true,
}
