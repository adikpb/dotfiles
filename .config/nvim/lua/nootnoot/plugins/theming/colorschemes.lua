return {
  -- tokyonight
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
      dim_inactive = true,
      lualine_bold = true,
      ---@param colors ColorScheme
      on_colors = function(colors)
        colors.bg_statusline = colors.none
      end,
      ---@param highlights tokyonight.Highlights
      ---@param colors ColorScheme
      on_highlights = function(highlights, colors)
        highlights.WhichKeyNormal = { bg = colors.bg_float }
        if vim.g.is_transparent then
          highlights.TabLineFill = { bg = colors.none }
        end
      end,
    },
  },
}
