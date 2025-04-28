return {
  "akinsho/bufferline.nvim",
  version = "*",
  dependencies = "nvim-tree/nvim-web-devicons",
  event = { "VeryLazy" },
  ---@type bufferline.UserConfig
  opts = {
    options = {
      mode = "buffers", -- set to "tabs" to only show tabpages instead
      numbers = "buffer_id",
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
  config = function(_, opts)
    local bufferline = require("bufferline")
    opts.options.style_preset = bufferline.style_preset.minimal
    bufferline.setup(opts)
  end,
}
