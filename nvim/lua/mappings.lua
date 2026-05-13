require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")

-- 주석 토글 (일반/비주얼 모드 모두 지원, 터미널 <C-_> 호환)
map("n", "<C-/>", function() require("Comment.api").toggle.linewise.current() end, { desc = "주석 토글" })
map("n", "<C-_>", function() require("Comment.api").toggle.linewise.current() end, { desc = "주석 토글" })
map("v", "<C-/>", "<ESC><cmd>lua require('Comment.api').toggle.linewise(vim.fn.visualmode())<CR>", { desc = "선택 영역 주석" })
map("v", "<C-_>", "<ESC><cmd>lua require('Comment.api').toggle.linewise(vim.fn.visualmode())<CR>", { desc = "선택 영역 주석" })

-- lazygit
map("n", "<leader>gg", "<cmd>LazyGit<CR>", { desc = "Git: Toggle LazyGit" })

-- render-markdown: raw ↔ rendered 토글 (마크다운 표 컬럼 블록 선택 시 raw로 전환)
map("n", "<leader>mr", "<cmd>RenderMarkdown toggle<CR>", { desc = "Markdown: Toggle render (raw/rendered)" })

-- floating terminal: 기본 NvChad 크기 오버라이드 (90% x 85%)
map({ "n", "t" }, "<A-i>", function()
  require("nvchad.term").toggle {
    pos = "float",
    id = "floatTerm",
    float_opts = {
      relative = "editor",
      row = 0.05,
      col = 0.05,
      width = 0.9,
      height = 0.85,
      border = "single",
    },
  }
end, { desc = "Terminal: Floating (large)" })
