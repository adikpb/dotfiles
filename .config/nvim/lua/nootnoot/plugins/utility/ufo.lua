return {
	"kevinhwang91/nvim-ufo",
	dependencies = { "kevinhwang91/promise-async", "chrisgrieser/nvim-origami" },
	event = { "LspAttach" },
	opts = {},
	config = function(opts)
		local ufo = require("ufo")

		-- vim.o.foldcolumn = "1" -- '0' is not bad
		-- Using ufo provider need a large value,
		-- feel free to decrease the value
		vim.o.foldlevel = 99
		vim.o.foldlevelstart = 99
		vim.o.foldenable = true

		local map = vim.keymap.set
		map("n", "zR", ufo.openAllFolds, { desc = "Open all folds" })
		map("n", "zM", ufo.closeAllFolds, { desc = "Close all folds" })
		map("n", "zr", ufo.openFoldsExceptKinds, { desc = "Fold less" })
		map("n", "zm", ufo.closeFoldsWith, { desc = "Fold more" })
		map("n", "K", function()
			local winid = ufo.peekFoldedLinesUnderCursor()
			if not winid then
				vim.lsp.buf.hover()
			end
		end, { desc = "Hover" })

		ufo.setup(opts)
	end,
}
