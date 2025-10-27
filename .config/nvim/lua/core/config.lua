vim.g.is_transparent = true

local function ThemeMeUp(color)
  color = color or "tokyonight"
  vim.cmd.colorscheme(color)
end

ThemeMeUp()
