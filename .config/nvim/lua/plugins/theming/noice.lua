return {
  "folke/noice.nvim",
  event = { "VeryLazy" },
  dependencies = {
    { "MunifTanjim/nui.nvim" },
  },
  opts = {
    presets = {
      bottom_search = true,
      command_palette = false,
      long_message_to_split = false,
      inc_rename = false, -- inc-rename.nvim
      lsp_doc_border = true,
    },
    lsp = {
      override = {
        ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
        ["vim.lsp.util.stylize_markdown"] = true,
      },
    },
    cmdline = { view = "cmdline" },
    views = {
      mini = {
        win_options = {
          winhighlight = { Normal = "Normal" },
        },
      },
    },
  },
}
