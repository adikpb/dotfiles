return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  ---@type snacks.Config
  opts = {
    bigfile = { enabled = true },
    indent = {
      enabled = true,
      indent = {
        hl = {
          "SnacksIndent1",
          "SnacksIndent2",
          "SnacksIndent3",
          "SnacksIndent4",
          "SnacksIndent5",
          "SnacksIndent6",
          "SnacksIndent7",
          "SnacksIndent8",
        },
      },
      scope = {
        hl = {
          "SnacksIndentScope1",
          "SnacksIndentScope2",
          "SnacksIndentScope3",
          "SnacksIndentScope4",
          "SnacksIndentScope5",
          "SnacksIndentScope6",
          "SnacksIndentScope7",
          "SnacksIndentScope8",
        },
      },
      config = function(opts, _)
        local tokyonight_util = require("tokyonight.util")
        local indent_hls = opts.indent.hl
        local scope_hls = opts.scope.hl

        for i, _ in ipairs(indent_hls) do
          ---@type vim.api.keyset.highlight
          ---@diagnostic disable-next-line: assign-type-mismatch
          local hl = vim.api.nvim_get_hl(0, { name = indent_hls[i] })
          local hl_fg = string.format("#%x", hl.fg)

          hl.fg = hl_fg
          vim.api.nvim_set_hl(0, scope_hls[i], hl)

          hl_fg = tokyonight_util.darken(hl_fg, 0.05)
          hl.fg = hl_fg
          vim.api.nvim_set_hl(0, indent_hls[i], hl)
        end
      end,
    },
    input = { enabled = true },
    notifier = {
      enabled = true,
      timeout = 3000,
    },
    ---@class snacks.picker.Config
    picker = {
      enabled = true,
      sources = {
        files = { hidden = true },
        grep = { hidden = true },
        grep_word = { hidden = true },
        undo = {
          layout = {
            preset = "sidebar",
          },
        },
        notifications = {
          confirm = function(picker, item)
            ---@type integer
            local preview_buf = picker.preview.win.buf
            local buf = vim.api.nvim_create_buf(false, true)

            local icon = item.item.icon
            local level = item.item.level:upper()
            local title = icon .. level .. " " .. item.item.title
            local text = vim.api.nvim_buf_get_lines(preview_buf, 0, -1, true)
            local ft = item.item.ft or item.preview.ft

            local height_win = vim.o.lines
            local width_win = vim.o.columns
            local height = math.min(math.floor(height_win * 0.6), #text)
            local width = math.floor(width_win * 0.6)

            vim.bo[buf].ft = ft
            vim.api.nvim_buf_set_lines(buf, 0, -1, true, text)
            vim.bo[buf].modifiable = false
            local win_opts = {
              relative = "editor",
              height = height,
              width = width,
              row = (height_win - height) / 2 - 2,
              col = (width_win - width) / 2,
              style = "minimal",
              title = title,
              title_pos = "center",
            }

            vim.api.nvim_open_win(buf, true, win_opts)
            vim.api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>close<cr>", {})
            vim.api.nvim_buf_set_keymap(buf, "n", "<esc>", "<cmd>close<cr>", {})

            picker:close()
          end,
        },
      },
    },
    quickfile = { enabled = true },
    scroll = {
      enabled = true,
      filter = function(buf)
        local excluded_filetypes = { "blink-cmp-menu" }
        local b = vim.b[buf]
        local bo = vim.bo[buf]
        return vim.g.snacks_scroll ~= false
          and b.snacks_scroll ~= false
          and bo.buftype ~= "terminal"
          and not vim.tbl_contains(excluded_filetypes, bo.filetype)
      end,
    },
    statuscolumn = { enabled = true },
  },
  keys = {
    {
      "<leader>.",
      function()
        Snacks.picker.pickers()
      end,
      desc = "Show Available Pickers",
    },
    -- Top Pickers & Explorer
    {
      "<leader><space>",
      function()
        Snacks.picker.smart()
      end,
      desc = "Smart Find Files",
    },
    {
      "<leader>,",
      function()
        Snacks.picker.buffers()
      end,
      desc = "Buffers",
    },
    {
      "<leader>n",
      function()
        Snacks.picker.notifications()
      end,
      desc = "[n]otifications",
    },
    -- find
    {
      "<leader>sf",
      function()
        Snacks.picker.files()
      end,
      desc = "[s]earch [f]iles",
    },
    {
      "<leader>sr",
      function()
        Snacks.picker.recent()
      end,
      desc = "Recent",
    },
    -- Grep
    {
      "<leader>/",
      function()
        Snacks.picker.grep()
      end,
      desc = "Grep",
    },
    {
      "<leader>sb",
      function()
        Snacks.picker.grep_buffers()
      end,
      desc = "Grep Open Buffers",
    },
    {
      "<leader>sw",
      function()
        Snacks.picker.grep_word()
      end,
      desc = "Grep Visual Selection or Word",
      mode = { "n", "x" },
    },
    -- search
    {
      "<leader>sh",
      function()
        Snacks.picker.help()
      end,
      desc = "[s]earch [h]elp Pages",
    },
    {
      "<leader>sR",
      function()
        Snacks.picker.resume()
      end,
      desc = "[s]earch [R]esume",
    },
    -- LSP
    {
      "gd",
      function()
        Snacks.picker.lsp_definitions()
      end,
      desc = "Goto [d]efinition",
    },
    {
      "gD",
      function()
        Snacks.picker.lsp_declarations()
      end,
      desc = "Goto [D]eclaration",
    },
    {
      "grr",
      function()
        Snacks.picker.lsp_references()
      end,
      nowait = true,
      desc = "[r]eferences",
    },
    {
      "gri",
      function()
        Snacks.picker.lsp_implementations()
      end,
      desc = "Goto [i]mplementation",
    },
    {
      "grt",
      function()
        Snacks.picker.lsp_type_definitions()
      end,
      desc = "Goto [t]ype Definition",
    },
    {
      "<leader>ss",
      function()
        Snacks.picker.lsp_workspace_symbols()
      end,
      desc = "LSP Work[s]pace [s]ymbols",
    },
    -- Other
    {
      "<leader>nh",
      function()
        Snacks.notifier.hide()
      end,
      desc = "Dismiss All Notifications",
    },
    {
      "<leader>rf",
      function()
        Snacks.rename.rename_file()
      end,
      desc = "[r]ename [f]ile",
    },
    {
      "<leader>u",
      function()
        Snacks.picker.undo()
      end,
      desc = "[u]ndo tree",
    },
  },
  init = function()
    vim.api.nvim_create_autocmd("User", {
      pattern = "VeryLazy",
      callback = function()
        -- Setup some globals for debugging (lazy-loaded)
        _G.dd = function(...)
          Snacks.debug.inspect(...)
        end
        _G.bt = function()
          Snacks.debug.backtrace()
        end
        vim.print = _G.dd
      end,
    })
  end,
}
