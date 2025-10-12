vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("UserLspConfig", { clear = true }),
  callback = function(ev)
    vim.lsp.inlay_hint.enable(true, { bufnr = ev.buf })
    vim.diagnostic.config({
      virtual_lines = {
        current_line = true,
      },
    })
  end,
})

-- vim.api.nvim_create_autocmd("LspAttach", {
--   group = vim.api.nvim_create_augroup("LspAttachDisableRuffHover", { clear = true }),
--   callback = function(args)
--     local client = vim.lsp.get_client_by_id(args.data.client_id)
--     if client == nil then
--       return
--     end
--     if client.name == "ruff" then
--       client.server_capabilities.hoverProvider = false
--     end
--   end,
--   desc = "LSP: Disable hover capability from Ruff",
-- })
