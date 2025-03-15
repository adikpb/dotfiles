return {
	{
		"nvim-lualine/lualine.nvim",
		dependencies = { "nvim-tree/nvim-web-devicons", "folke/noice.nvim" },
		event = { "VeryLazy" },
		opts = {
			sections = {
				lualine_a = {
					"mode",
					{
						---@diagnostic disable-next-line: undefined-field, deprecated
						require("noice").api.statusline.mode.get,
						---@diagnostic disable-next-line: undefined-field, deprecated
						cond = require("noice").api.statusline.mode.has,
						fmt = function(str)
							return str:gsub("--%s.*%s--", "")
						end,
					},
				},
				lualine_z = {
					"location",
					{
						---@diagnostic disable-next-line: undefined-field, deprecated
						require("noice").api.statusline.showcmd.get,
						---@diagnostic disable-next-line: undefined-field, deprecated
						cond = require("noice").api.statusline.showcmd.has,
					},
				},
			},
		},
	},
	{
		"akinsho/bufferline.nvim",
		version = "*",
		dependencies = "nvim-tree/nvim-web-devicons",
		event = { "VeryLazy" },
		opts = {
			options = {
				hover = {
					enabled = true,
					delay = 200,
					reveal = { "close" },
				},
			},
		},
	},
}
