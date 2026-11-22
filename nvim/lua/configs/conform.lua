-- 기존 PATH(프로젝트·mise 포함)를 우선하고, 없을 때 해당 Mason 도구만 찾는다.
local function formatter_command(name)
  return function()
    local executable = vim.fn.exepath(name)
    if executable ~= "" then return executable end
    local mason = vim.fn.stdpath "data" .. "/mason/bin/" .. name
    if vim.fn.executable(mason) == 1 then return mason end
    return name -- Conform의 도구 미발견 안내를 유지한다.
  end
end

local options = {
  formatters = {
    stylua = { command = formatter_command("stylua") },
    black = { command = formatter_command("black") },
  },
  formatters_by_ft = {
    lua = { "stylua" },
    css = { "prettier" },
    html = { "prettier" },
    python = { "black" },
    php = { "php_cs_fixer" },
    markdown = { "prettier" },
  },

  format_on_save = function(bufnr)
    if require("configs.save-policy").is_legacy_encoding(bufnr) then return end
    return { timeout_ms = 500, lsp_fallback = true }
  end,
}

return options
