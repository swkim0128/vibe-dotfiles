require("nvchad.configs.lspconfig").defaults()

local servers = { "html", "cssls", "intelephense" }
vim.lsp.enable(servers)

-- JetBrains Kotlin LSP: 현재 실행 환경의 설치 경로를 사용한다.
local kotlin_lsp = vim.fn.exepath("kotlin-lsp")
if kotlin_lsp ~= "" then
  vim.lsp.config("kotlin_lsp", { cmd = { kotlin_lsp, "--stdio" } })
  vim.lsp.enable "kotlin_lsp"
else
  vim.schedule(function()
    vim.notify("Kotlin LSP 미시작: kotlin-lsp를 찾지 못했습니다. Neovim에서 :echo exepath('kotlin-lsp')로 실행 경로를 확인하세요.", vim.log.levels.WARN)
  end)
end

-- read :h vim.lsp.config for changing options of lsp servers
