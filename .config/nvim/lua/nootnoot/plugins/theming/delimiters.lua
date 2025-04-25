return {
	url = "https://gitlab.com/HiPhish/rainbow-delimiters.nvim",
	main = "rainbow-delimiters.setup",
	submodules = false,
	event = { "BufReadPre", "BufReadPost" },
	opts = {
		highlight = {
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
}
