return {
	-- tokyonight
	{
		"folke/tokyonight.nvim",
		name = "tokyonight",
		lazy = false, -- make sure we load this during startup if it is your main colorscheme
		priority = 1000, -- make sure to load this before all the other start plugins
		opts = {
			-- your configuration comes here
			-- or leave it empty to use the default settings
			style = "night", -- The theme comes in three styles, `storm`, `moon`, a darker variant `night` and `day`
			light_style = "day", -- The theme is used when the background is set to light
			transparent = not vim.g.neovide, -- Enable this to disable setting the background color
			terminal_colors = true, -- Configure the colors used when opening a `:terminal` in [Neovim](https://github.com/neovim/neovim)
			styles = {
				-- Style to be applied to different syntax groups
				-- Value is any valid attr-list value for `:help nvim_set_hl`
				comments = { italic = true },
				keywords = { italic = true },
				functions = {},
				variables = {},
				-- Background styles. Can be "dark", "transparent" or "normal"
				sidebars = "dark", -- style for sidebars, see below
				floats = "dark", -- style for floating windows
			},
			day_brightness = 0.3, -- Adjusts the brightness of the colors of the **Day** style. Number between 0 and 1, from dull to vibrant colors
			dim_inactive = true, -- dims inactive windows
			lualine_bold = true, -- When `true`, section headers in the lualine theme will be bold

			--- You can override specific highlights to use other groups or a hex color
			--- function will be called with a Highlights and ColorScheme table
			---@param highlights tokyonight.Highlights
			---@param colors ColorScheme
			on_highlights = function(highlights, colors)
				local util = require("tokyonight.util")

				-- lukas-reineke/indent-blankline
				local rainbow_highlights = {
					"RainbowRed",
					"RainbowYellow",
					"RainbowBlue",
					"RainbowOrange",
					"RainbowGreen",
					"RainbowViolet",
					"RainbowCyan",
				}
				for _, i in pairs(rainbow_highlights) do
					local color = string.gsub(i, "Rainbow", "")
					color = string.lower(color)
					if color == "violet" then
						color = "purple"
					end
					highlights[i] = { fg = util.darken(colors[color], 0.2) }
				end
			end,
		},
	},
}
