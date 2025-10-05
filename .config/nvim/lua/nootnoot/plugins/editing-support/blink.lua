return {
  "saghen/blink.cmp",
  dependencies = {
    "rafamadriz/friendly-snippets",
    "Kaiser-Yang/blink-cmp-git",
  },
  version = "1.*",
  event = { "VeryLazy" },
  ---@module "blink.cmp"
  ---@type blink.cmp.Config
  opts = {
    keymap = { preset = "enter" },
    completion = {
      menu = {
        auto_show = false,
        draw = {
          columns = {
            { "kind_icon" },
            { "label", "label_description", gap = 1 },
            { "source_id" },
          },
          components = {
            kind_icon = {
              text = function(ctx)
                local icon = ctx.kind_icon
                if vim.tbl_contains({ "Path" }, ctx.source_name) then
                  local nvim_devicons = require("nvim-web-devicons")
                  local dev_icon, _ = nvim_devicons.get_icon(ctx.label)
                  if dev_icon then
                    icon = dev_icon
                  end
                else
                  icon = require("lspkind").symbolic(ctx.kind, {
                    mode = "symbol",
                  })
                end

                return icon .. ctx.icon_gap
              end,

              -- Optionally, use the highlight groups from nvim-web-devicons
              -- You can also add the same function for `kind.highlight` if you
              -- want to keep the highlight groups in sync with the icons.
              highlight = function(ctx)
                local hl = ctx.kind_hl
                if vim.tbl_contains({ "Path" }, ctx.source_name) then
                  local nvim_devicons = require("nvim-web-devicons")
                  local dev_icon, dev_hl = nvim_devicons.get_icon(ctx.label)
                  if dev_icon then
                    hl = dev_hl
                  end
                end
                return hl
              end,
            },
            source_id = {
              highlight = "BlinkCmpGhostText",
            },
          },
        },
      },
      ghost_text = { enabled = true, show_with_menu = false },
    },
    cmdline = {
      completion = {
        ghost_text = { enabled = true },
        menu = { auto_show = true },
        list = { selection = { preselect = false } },
      },
    },
    sources = {
      default = { "lazydev", "lsp", "path", "snippets", "git", "buffer" },
      providers = {
        lazydev = {
          name = "LazyDev",
          module = "lazydev.integrations.blink",
          score_offset = 100,
        },
        git = {
          module = "blink-cmp-git",
          name = "Git",
        },
      },
    },
  },
}
