return {
	-- tokyonight
	{
		"folke/tokyonight.nvim",
		name = "tokyonight",
		lazy = false,
		priority = 1000,
		opts = {
			style = "night",
			styles = {
				floats = "normal",
			},
			dim_inactive = true,
			lualine_bold = true,
		},
	},
}
