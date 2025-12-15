return {
  "nvim-lualine/lualine.nvim",
  event = { "VeryLazy" },
  opts = {
    sections = {
      lualine_a = {
        {
          "mode",
          type = "vim_fun",
          fmt = function(mode)
            local mode_map = {
              n = "N",
              i = "I",
              R = "R",
              v = "V",
              V = "VL",
              ["<C-v>"] = "VB",
              c = "C",
              s = "S",
              S = "SL",
              ["<C-s>"] = "SB",
              t = "T",
            }
            return mode_map[mode] or mode
          end,
        },
      },
      lualine_b = {
        {
          function()
            return "rec. @" .. vim.fn.reg_recording()
          end,
          cond = function()
            return vim.fn.reg_recording() ~= ""
          end,
        },
        "diff",
        "diagnostics",
      },
      lualine_x = { "encoding", "fileformat" },
      lualine_y = { {
        "searchcount",
        fmt = function(count)
          return count ~= "[0/0]" and count or ""
        end,
      } },
    },
  },
}
