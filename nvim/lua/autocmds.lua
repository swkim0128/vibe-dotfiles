local autocmd = vim.api.nvim_create_autocmd

require "nvchad.autocmds"

-- 한글 상태로 vim 진입 시 영어로 전환
autocmd({ "VimEnter", "FocusGained" }, {
  pattern = "*",
  callback = function()
    vim.fn.system("im-select com.apple.keylayout.ABC")
  end,
})

-- 마크다운 제외, 저장 시 줄 끝 공백 제거
autocmd("BufWritePre", {
  pattern = "*",
  callback = function()
    if vim.bo.filetype == "markdown" then return end
    local save_cursor = vim.fn.getpos(".")
    pcall(function() vim.cmd [[%s/\s\+$//e]] end)
    vim.fn.setpos(".", save_cursor)
  end,
})
