---@module "lazy.types"
---@type LazyPluginSpec
return {
	url = "https://gitlab.com/HiPhish/rainbow-delimiters.nvim",
	main = "rainbow-delimiters.setup",
	submodules = false,
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
}
