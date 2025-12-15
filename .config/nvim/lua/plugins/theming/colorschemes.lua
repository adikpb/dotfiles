return {
  ---@module "tokyonight"
  {
    "folke/tokyonight.nvim",
    name = "tokyonight",
    lazy = false,
    priority = 1001,
    opts = {
      style = "night",
      transparent = vim.g.is_transparent,
      styles = {
        sidebars = vim.g.is_transparent and "transparent" or "normal",
        floats = vim.g.is_transparent and "transparent" or "normal",
      },
      dim_inactive = not vim.g.is_transparent,
      lualine_bold = true,
      ---@param colors ColorScheme
      on_colors = function(colors)
        if vim.g.is_transparent then
          colors.bg_statusline = colors.none
        end
      end,
    },
  },
}
