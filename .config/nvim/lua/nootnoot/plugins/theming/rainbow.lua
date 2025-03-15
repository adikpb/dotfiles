return {
	{
		"lukas-reineke/indent-blankline.nvim",
		main = "ibl",
		event = { "BufReadPre", "BufReadPost" },
		opts = {
			indent = {
				highlight = {
					"RainbowRed",
					"RainbowYellow",
					"RainbowBlue",
					"RainbowOrange",
					"RainbowGreen",
					"RainbowViolet",
					"RainbowCyan",
				},
			},
			scope = {
				enabled = true,
			},
		},
	},
	{
		url = "https://gitlab.com/HiPhish/rainbow-delimiters.nvim",
		main = "rainbow-delimiters.setup",
		event = { "BufReadPre", "BufReadPost" },
		opts = {
			highlight = {
				"RainbowDelimiterRed",
				"RainbowDelimiterYellow",
				"RainbowDelimiterBlue",
				"RainbowDelimiterOrange",
				"RainbowDelimiterGreen",
				"RainbowDelimiterViolet",
				"RainbowDelimiterCyan",
			},
		},
	},
}
