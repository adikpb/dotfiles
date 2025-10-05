return {
  "lewis6991/gitsigns.nvim",
  event = { "BufReadPre", "BufReadPost" },
  opts = {
    current_line_blame = true,
    on_attach = function(bufnr)
      local gitsigns = require("gitsigns")
      local opts = { buffer = bufnr }

      -- Navigation
      opts.desc = "Git: [h]unk [n]ext"
      vim.keymap.set("n", "]c", function()
        if vim.wo.diff then
          vim.cmd.normal({ "]c", bang = true })
        else
          gitsigns.nav_hunk("next")
        end
      end, opts)

      opts.desc = "Git: [h]unk [p]revious"
      vim.keymap.set("n", "[c", function()
        if vim.wo.diff then
          vim.cmd.normal({ "[c", bang = true })
        else
          gitsigns.nav_hunk("prev")
        end
      end, opts)

      -- Actions
      opts.desc = "Git: [h]unk [s]tage"
      vim.keymap.set("n", "<leader>hs", gitsigns.stage_hunk, opts)
      opts.desc = "Git: [h]unk [r]eset"
      vim.keymap.set("n", "<leader>hr", gitsigns.reset_hunk, opts)

      opts.desc = "Git: [h]unk [s]tage"
      vim.keymap.set("v", "<leader>hs", function()
        gitsigns.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
      end, opts)

      opts.desc = "Git: [h]unk [r]eset"
      vim.keymap.set("v", "<leader>hr", function()
        gitsigns.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
      end, opts)

      opts.desc = "Git: [h]unk [S]tage Buffer"
      vim.keymap.set("n", "<leader>hS", gitsigns.stage_buffer, opts)
      opts.desc = "Git: [h]unk [R]eset Buffer"
      vim.keymap.set("n", "<leader>hR", gitsigns.reset_buffer, opts)
      opts.desc = "Git: [h]unk [P]review"
      vim.keymap.set("n", "<leader>hp", gitsigns.preview_hunk, opts)
      opts.desc = "Git: [h]unk [p]review inline"
      vim.keymap.set("n", "<leader>hP", gitsigns.preview_hunk_inline, opts)

      opts.desc = "Git: [h]unk [d]iff"
      vim.keymap.set("n", "<leader>hd", gitsigns.diffthis, opts)

      opts.desc = "Git: [h]unk [D]iff Buffer"
      vim.keymap.set("n", "<leader>hD", function()
        gitsigns.diffthis("~")
      end, opts)

      opts.desc = "Git: [h]unk [Q]Flist ALL"
      vim.keymap.set("n", "<leader>hQ", function()
        gitsigns.setqflist("all")
      end, opts)
      opts.desc = "Git: [h]unk [q]flist"
      vim.keymap.set("n", "<leader>hq", gitsigns.setqflist, opts)

      -- Toggles
      -- opts.desc = "Toggle: [g]it line [b]lame"
      -- vim.keymap.set("n", "<leader>tgb", gitsigns.toggle_current_line_blame, opts)
      -- opts.desc = "Toggle: [g]it [w]ord diff"
      -- vim.keymap.set("n", "<leader>tgw", gitsigns.toggle_word_diff, opts)

      if package.loaded["snacks"] then
        Snacks.toggle
          .new({
            name = "Git Line Blame",
            get = function()
              return gitsigns.toggle_current_line_blame(nil)
            end,
            set = function(state)
              gitsigns.toggle_current_line_blame(not state)
            end,
          })
          :map("<leader>tgb")
        Snacks.toggle
          .new({
            name = "Git Word Diff",
            get = function()
              return gitsigns.toggle_word_diff(nil)
            end,
            set = function(state)
              gitsigns.toggle_word_diff(not state)
            end,
          })
          :map("<leader>tgw")
      end

      -- Text object
      opts.desc = "inner hunk"
      vim.keymap.set({ "o", "x" }, "ih", gitsigns.select_hunk, opts)
      opts.desc = "hunk"
      vim.keymap.set({ "o", "x" }, "ah", gitsigns.select_hunk, opts)
    end,
  },
}
