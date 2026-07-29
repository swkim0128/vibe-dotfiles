require("nvchad.configs.lspconfig").defaults()

local servers = { "html", "cssls", "intelephense" }
vim.lsp.enable(servers)

-- Kotlin LSP (JetBrains 공식 kotlin-lsp, mason 설치). shopping-danuri 등 Kotlin 소스 추적용.
-- lspconfig 기본 cmd 는 intellij-server 라 mason 바이너리명(kotlin-lsp)과 달라 cmd override 필요.
vim.lsp.config("kotlin_lsp", {
  cmd = { vim.fn.stdpath "data" .. "/mason/bin/kotlin-lsp", "--stdio" },
})
vim.lsp.enable "kotlin_lsp"

-- read :h vim.lsp.config for changing options of lsp servers
