vim.api.nvim_create_autocmd("VimEnter", {
  group = vim.api.nvim_create_augroup("OpencodeLspSetup", { clear = true }),
  callback = function()
    vim.lsp.enable("opencode-server", require("opencode.config").opts.lsp.enabled)
  end,
})
