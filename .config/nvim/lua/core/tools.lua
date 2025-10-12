LSP_SERVERS = {
  lua_ls = {},
  rust_analyzer = {},
  basedpyright = {},
  clangd = {},
  jdtls = {},
  marksman = {},
  taplo = {},
}

local CODE_FORMATTERS = {
  stylua = {},
  ruff = {},
  ["clang-format"] = {},
  prettier = {},
}

local TOOLS = { mmdc = {} } -- not available in brew
TOOLS = vim.tbl_keys(vim.tbl_deep_extend("force", TOOLS, LSP_SERVERS, CODE_FORMATTERS))

local MANUALLY_INSTALLED_TOOLS = {}

ENSURE_INSTALLED = vim.tbl_filter(function(name)
  return not vim.tbl_contains(MANUALLY_INSTALLED_TOOLS, name)
end, TOOLS)
