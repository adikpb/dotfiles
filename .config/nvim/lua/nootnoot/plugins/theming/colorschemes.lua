return {
  -- tokyonight
  {
    "folke/tokyonight.nvim",
    name = "tokyonight",
    lazy = false,
    priority = 1000,
    opts = {
      style = "night",
      transparent = vim.g.is_transparent,
      styles = {
        floats = vim.g.is_transparent and "transparent" or "normal",
      },
      dim_inactive = true,
      lualine_bold = true,
      on_colors = function(colors)
        if vim.g.is_transparent then
          colors.bg_statusline = colors.none
        end
      end,
      on_highlights = function(highlights, colors)
        if vim.g.is_transparent then
          highlights.TabLineFill = { bg = colors.none }
        end
      end,
    },
  },
}
