return {
  "nvim-lualine/lualine.nvim",
  event = { "VeryLazy" },
  opts = {
    sections = {
      lualine_a = {
        {
          "mode",
          fmt = function(str)
            return string.sub(str, 1, 3)
          end,
        },
        {
          function()
            return "rec. @" .. vim.fn.reg_recording()
          end,
          cond = function()
            return vim.fn.reg_recording() ~= ""
          end,
        },
      },
    },
  },
}
