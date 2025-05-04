---@param args vim.api.keyset.create_autocmd.callback_args
local function oil_bridge(args)
  if vim.bo[args.buf].ft ~= "oil" then
    return
  end

  local oil = require("oil")

  local entry = oil.get_cursor_entry()
  if not entry then
    return
  end

  local s, api = pcall(require, "nvim-tree.api")

  if not s then
    return
  end

  local filename = entry.name
  local directory = oil.get_current_dir()
  local path = directory .. filename

  api.tree.collapse_all(false)
  api.tree.find_file({ buf = path, focus = false })
end

return {
  {
    "stevearc/oil.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    lazy = false,
    keys = { { "<leader>pv", "<cmd>Oil<CR>", desc = "[p]roject [v]iew" } },
    ---@module "oil"
    ---@type oil.SetupOpts
    opts = {
      default_file_explorer = true,
      view_options = {
        show_hidden = true,
        is_always_hidden = function(name, _)
          return name == ".."
        end,
      },
      keymaps = {
        ["<C-h>"] = false,
        ["<C-l>"] = false,
      },
      preview_win = {
        -- Custom fields
        ---@type oil.OpenPreviewOpts
        split_options = { vertical = true, split = "aboveleft" },
        width = 80,
      },
    },
    config = function(_, opts)
      local oil = require("oil")
      local util = require("oil.util")
      local layout = require("oil.layout")
      local actions = require("oil.actions")
      local preview_width = opts.preview_win.width
      local win_opts = opts.preview_win.split_options

      vim.api.nvim_create_augroup("OilBridge", { clear = false })
      vim.api.nvim_create_autocmd({ "BufEnter" }, {
        group = "OilBridge",
        pattern = "oil://*",
        callback = function(args)
          vim.api.nvim_create_autocmd({ "CursorMoved" }, {
            group = "OilBridge",
            buffer = args.buf,
            callback = function(args)
              oil_bridge(args)
            end,
          })
        end,
      })

      -- snacks.nvim rename
      vim.api.nvim_create_autocmd("User", {
        pattern = "OilActionsPost",
        callback = function(event)
          local src = event.data.actions.src_url
          local dst = event.data.actions.dest_url
          if event.data.actions.type == "move" then
            require("snacks").rename.on_rename_file(src, dst)
          end
        end,
      })

      -- github.com/stevearc/oil.nvim/blob/master/lua/oil/actions.lua#L70
      local function togglePreview()
        local entry = oil.get_cursor_entry()
        if not entry then
          vim.notify("Could not find entry under cursor", vim.log.levels.ERROR)
          return
        end
        local winid = util.get_preview_win()
        if winid then
          local cur_id = vim.w[winid].oil_entry_id
          if entry.id == cur_id then
            vim.api.nvim_win_close(winid, true)
            if util.is_floating_win() then
              local float_win_opts = layout.get_fullscreen_win_opts()
              vim.api.nvim_win_set_config(0, float_win_opts)
            end
            return
          end
        end
        oil.open_preview(win_opts, function(err)
          winid = util.get_preview_win()
          if not err and winid then
            vim.api.nvim_win_set_width(winid, preview_width)
          end
        end)
      end

      -- https://github.com/stevearc/oil.nvim/blob/master/doc/recipes.md
      local detailed_view = false

      local keymaps = {
        ["gd"] = {
          desc = "Toggle file detail view",
          callback = function()
            detailed_view = not detailed_view
            if detailed_view then
              require("oil").set_columns({
                "icon",
                "permissions",
                "size",
                "mtime",
              })
            else
              oil.set_columns({ "icon" })
            end
          end,
        },
        ["<C-p>"] = vim.deepcopy(actions.preview, true),
      }
      keymaps["<C-p>"].callback = togglePreview
      opts.keymaps = vim.tbl_deep_extend("force", opts.keymaps, keymaps)

      oil.setup(opts)
    end,
  },
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    keys = {
      {
        "<leader>pt",
        function()
          local api = require("nvim-tree.api")
          api.tree.toggle({ find_file = true, focus = false })
          oil_bridge({ buf = 0 })
        end,
        desc = "[p]roject [t]ree",
      },
    },
    opts = {
      hijack_netrw = false,
      sync_root_with_cwd = true,
      select_prompts = true,
      view = {
        centralize_selection = true,
        side = "right",
        width = 30,
        -- float = { enable = true },
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
  },
}
