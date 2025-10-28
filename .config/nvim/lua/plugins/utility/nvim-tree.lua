return {
  "nvim-tree/nvim-tree.lua",
  keys = {
    {
      "<leader>pt",
      function()
        local api = require("nvim-tree.api")
        api.tree.toggle({ find_file = true, focus = false })
      end,
      desc = "[p]roject [t]ree",
    },
  },
  opts = {
    sync_root_with_cwd = true,
    select_prompts = true,
    view = {
      centralize_selection = true,
      side = "right",
      width = 30,
    },
    renderer = {
      group_empty = true,
      indent_width = 1,
      hidden_display = "all",
      highlight_git = "all",
      highlight_diagnostics = "all",
      highlight_opened_files = "all",
      highlight_modified = "all",
      indent_markers = {
        enable = true,
      },
      icons = {
        web_devicons = {
          folder = {
            enable = true,
          },
        },
        show = {
          hidden = false,
        },
      },
    },
    hijack_directories = {
      enable = false,
    },
    update_focused_file = {
      enable = true,
    },
    diagnostics = {
      enable = true,
      severity = {
        min = vim.diagnostic.severity.WARN,
      },
    },
    modified = {
      enable = true,
    },
    filters = {
      git_ignored = false,
    },
    actions = {
      use_system_clipboard = false,
      change_dir = {
        enable = false,
      },
      open_file = {
        window_picker = {
          enable = false,
        },
      },
    },
    trash = {
      cmd = "",
    },
  },
}
