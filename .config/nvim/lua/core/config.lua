vim.g.is_transparent = true

-- primeagen
local function ThemeMeUp(color)
  color = color or "tokyonight"
  vim.cmd.colorscheme(color)
end

vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function(_)
    ThemeMeUp()
  end,
})
