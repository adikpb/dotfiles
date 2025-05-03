return {
  "stevearc/oil.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  lazy = false,
  keys = { { "<leader>pv", "<cmd>Oil<CR>", desc = "[p]roject [v]iew" } },
  ---@module "oil"
  ---@type oil.SetupOpts
  opts = {
    default_file_explorer = true,
    win_options = {
      winbar = "%!v:lua.get_oil_winbar()",
    },
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

    -- https://github.com/stevearc/oil.nvim/blob/master/lua/oil/actions.lua#L70
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
    function _G.get_oil_winbar()
      local bufnr = vim.api.nvim_win_get_buf(vim.g.statusline_winid)
      local dir = oil.get_current_dir(bufnr)
      if dir then
        return vim.fn.fnamemodify(dir, ":~")
      else
        return vim.api.nvim_buf_get_name(0)
      end
    end

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
}
