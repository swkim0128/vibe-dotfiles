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

-- csv.vim 네이티브 키맵 (ft=csv 버퍼에서 동작)
map("n", "<leader>cv", "<cmd>%ArrangeColumn<CR>", { desc = "CSV: Arrange columns (align widths)" })
map("n", "<leader>cV", "<cmd>%UnArrangeColumn<CR>", { desc = "CSV: Unarrange columns (raw)" })
map("n", "<leader>cs", function()
  vim.ui.input({ prompt = "Sort by column number (current=" .. vim.fn.col(".") .. ", or empty=cursor col): " }, function(input)
    if input == nil then return end
    if input == "" then
      vim.cmd("SortCsv")
    else
      vim.cmd("SortCsv " .. input)
    end
  end)
end, { desc = "CSV: Sort by column" })
map("n", "<leader>cS", function()
  vim.ui.input({ prompt = "Sort by column number (numeric, reverse): " }, function(input)
    if not input or input == "" then return end
    vim.cmd("SortCsv! n " .. input)
  end)
end, { desc = "CSV: Sort by column (numeric reverse)" })
map("n", "<leader>ch", "<cmd>HiColumn!<CR>", { desc = "CSV: Toggle column highlight" })
map("n", "<leader>cH", "<cmd>Header<CR>", { desc = "CSV: Fix header at top" })

-- conform 수동 포맷: 변경이 없거나 저장하지 않아도 즉시 포맷
vim.api.nvim_create_user_command("Format", function(args)
  local range = nil
  if args.count ~= -1 then
    local end_line = vim.api.nvim_buf_get_lines(0, args.line2 - 1, args.line2, true)[1]
    range = {
      start = { args.line1, 0 },
      ["end"] = { args.line2, end_line and #end_line or 0 },
    }
  end
  require("conform").format({ async = true, lsp_fallback = true, range = range })
end, { range = true, desc = "Conform: Format buffer or range" })

map("n", "<leader>cf", "<cmd>Format<CR>", { desc = "Conform: Format buffer" })
map("v", "<leader>cf", ":Format<CR>", { desc = "Conform: Format selection" })

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
