return {
	"lewis6991/gitsigns.nvim",
	event = { "VeryLazy" },
	opts = {
		current_line_blame = true,
		on_attach = function(bufnr)
			local gitsigns = require("gitsigns")

			local function map(mode, l, r, opts)
				opts = opts or {}
				opts.buffer = bufnr
				vim.keymap.set(mode, l, r, opts)
			end

			-- Navigation
			map("n", "]c", function()
				if vim.wo.diff then
					vim.cmd.normal({ "]c", bang = true })
				else
					gitsigns.nav_hunk("next")
				end
			end, { desc = "Git: [h]unk [n]ext" })

			map("n", "[c", function()
				if vim.wo.diff then
					vim.cmd.normal({ "[c", bang = true })
				else
					gitsigns.nav_hunk("prev")
				end
			end, { desc = "Git: [h]unk [p]revious" })

			-- Actions
			map("n", "<leader>hs", gitsigns.stage_hunk, { desc = "Git: [h]unk [s]tage" })
			map("n", "<leader>hr", gitsigns.reset_hunk, { desc = "Git: [h]unk [r]eset" })

			map("v", "<leader>hs", function()
				gitsigns.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
			end, { desc = "Git: [h]unk [s]tage" })

			map("v", "<leader>hr", function()
				gitsigns.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
			end, { desc = "Git: [h]unk [r]eset" })

			map("n", "<leader>hS", gitsigns.stage_buffer, { desc = "Git: [h]unk [S]tage Buffer" })
			map("n", "<leader>hR", gitsigns.reset_buffer, { desc = "Git: [h]unk [R]eset Buffer" })
			map("n", "<leader>hp", gitsigns.preview_hunk, { desc = "Git: [h]unk [p]review" })

			map("n", "<leader>hd", gitsigns.diffthis, { desc = "Git: [h]unk [d]iff" })

			map("n", "<leader>hD", function()
				gitsigns.diffthis("~")
			end, { desc = "Git: [h]unk [D]iff Buffer" })

			map("n", "<leader>hQ", function()
				gitsigns.setqflist("all")
			end, { desc = "Git: [h]unk [Q]Flist ALL" })
			map("n", "<leader>hq", gitsigns.setqflist, { desc = "Git: [h]unk [q]flist" })

			-- Toggles
			map("n", "<leader>tgb", gitsigns.toggle_current_line_blame, { desc = "Toggle: [g]it line [b]lame" })
			map("n", "<leader>tgd", gitsigns.toggle_deleted, { desc = "Toggle: [g]it [d]eleted" })
			map("n", "<leader>tgw", gitsigns.toggle_word_diff, { desc = "Toggle: [g]it [w]ord diff" })

			-- Text object
			map({ "o", "x" }, "ih", gitsigns.select_hunk, { desc = "inner hunk" })
			map({ "o", "x" }, "ah", gitsigns.select_hunk, { desc = "hunk" })
		end,
	},
}
