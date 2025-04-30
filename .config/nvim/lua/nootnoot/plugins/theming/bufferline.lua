return {
  "akinsho/bufferline.nvim",
  version = "*",
  dependencies = "nvim-tree/nvim-web-devicons",
  event = { "VeryLazy" },
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
