return {
  "akinsho/bufferline.nvim",
  version = "*",
  event = "VeryLazy",
  ---@module "bufferline"
  ---@type bufferline.UserConfig
  opts = {
    options = {
      -- minimal
      style_preset = 2,
      diagnostics = "nvim_lsp",
      -- offsets = {
      --     {
      --         filetype = "NvimTree",
      --         text = "File Explorer" | function ,
      --         text_align = "left" | "center" | "right"
      --         separator = true
      --     }
      -- },
      -- can also be a table containing 2 custom separators
      -- [focused and unfocused]. eg: { '|', '|' }
    },
  },
}
