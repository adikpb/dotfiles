return {
  "lewis6991/gitsigns.nvim",
  event = { "BufReadPre", "BufReadPost" },
  opts = {
    current_line_blame = true,
    on_attach = function(bufnr)
      local gitsigns = require("gitsigns")

      local function map(mode, l, r, opts)
        opts = opts or {}
        opts.buffer = bufnr
        vim.keymap.set(mode, l, r, opts)
      end

      local opts = {}

      -- Navigation
      opts.desc = "Git: [h]unk [n]ext"
      map("n", "]c", function()
        if vim.wo.diff then
          vim.cmd.normal({ "]c", bang = true })
        else
          gitsigns.nav_hunk("next")
        end
      end, opts)

      opts.desc = "Git: [h]unk [p]revious"
      map("n", "[c", function()
        if vim.wo.diff then
          vim.cmd.normal({ "[c", bang = true })
        else
          gitsigns.nav_hunk("prev")
        end
      end, opts)

      -- Actions
      opts.desc = "Git: [h]unk [s]tage"
      map("n", "<leader>hs", gitsigns.stage_hunk, opts)
      opts.desc = "Git: [h]unk [r]eset"
      map("n", "<leader>hr", gitsigns.reset_hunk, opts)

      opts.desc = "Git: [h]unk [s]tage"
      map("v", "<leader>hs", function()
        gitsigns.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
      end, opts)

      opts.desc = "Git: [h]unk [r]eset"
      map("v", "<leader>hr", function()
        gitsigns.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
      end, opts)

      opts.desc = "Git: [h]unk [S]tage Buffer"
      map("n", "<leader>hS", gitsigns.stage_buffer, opts)
      opts.desc = "Git: [h]unk [R]eset Buffer"
      map("n", "<leader>hR", gitsigns.reset_buffer, opts)
      opts.desc = "Git: [h]unk [P]review"
      map("n", "<leader>hp", gitsigns.preview_hunk, opts)
      opts.desc = "Git: [h]unk [p]review inline"
      map("n", "<leader>hP", gitsigns.preview_hunk_inline, opts)

      opts.desc = "Git: [h]unk [d]iff"
      map("n", "<leader>hd", gitsigns.diffthis, opts)

      opts.desc = "Git: [h]unk [D]iff Buffer"
      map("n", "<leader>hD", function()
        gitsigns.diffthis("~")
      end, opts)

      opts.desc = "Git: [h]unk [Q]Flist ALL"
      map("n", "<leader>hQ", function()
        gitsigns.setqflist("all")
      end, opts)
      opts.desc = "Git: [h]unk [q]flist"
      map("n", "<leader>hq", gitsigns.setqflist, opts)

      -- Toggles
      opts.desc = "Toggle: [g]it line [b]lame"
      map("n", "<leader>tgb", gitsigns.toggle_current_line_blame, opts)
      opts.desc = "Toggle: [g]it [w]ord diff"
      map("n", "<leader>tgw", gitsigns.toggle_word_diff, opts)

      -- Text object
      opts.desc = "inner hunk"
      map({ "o", "x" }, "ih", gitsigns.select_hunk, opts)
      opts.desc = "hunk"
      map({ "o", "x" }, "ah", gitsigns.select_hunk, opts)
    end,
  },
}
