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

-- csvview: CSV 컬럼 정렬 표시 토글
map("n", "<leader>cv", "<cmd>CsvViewToggle<CR>", { desc = "CSV: Toggle column view" })

-- csvview: 강제 새로고침 (extmark stale 시 복구)
map("n", "<leader>cr", function()
  local ok, csvview = pcall(require, "csvview")
  if not ok then return end
  local b = vim.api.nvim_get_current_buf()
  if csvview.is_enabled(b) then csvview.disable(b) end
  vim.defer_fn(function()
    pcall(csvview.enable, b)
    vim.cmd("redraw!")
  end, 30)
end, { desc = "CSV: Force refresh column view" })

-- Miller(mlr) 기반 CSV 정렬·필터 (헤더 보존, quoted comma 안전)
-- csvview의 extmark가 buffer 교체 후 잔존하지 않도록 Lua API로 정확히 detach→re-attach
local function mlr_pipe(args, prompt_label, prompt_default)
  vim.ui.input({ prompt = prompt_label, default = prompt_default or "" }, function(input)
    if not input or input == "" then return end
    local bufnr = vim.api.nvim_get_current_buf()
    local csvview_ok, csvview = pcall(require, "csvview")
    local was_active = csvview_ok and csvview.is_enabled(bufnr) or false
    if was_active then csvview.disable(bufnr) end

    local mlr_cmd = string.format("mlr --csv %s %s", args, vim.fn.shellescape(input))
    local view = vim.fn.winsaveview()
    local pre_lines = vim.api.nvim_buf_line_count(bufnr)
    local ok, err = pcall(function() vim.cmd("%!" .. mlr_cmd) end)
    local success = ok and vim.v.shell_error == 0

    if not ok then
      vim.notify("[mlr] 실행 실패: " .. tostring(err), vim.log.levels.ERROR)
    elseif vim.v.shell_error ~= 0 then
      vim.notify(string.format("[mlr] exit=%d. 명령: %s", vim.v.shell_error, mlr_cmd), vim.log.levels.ERROR)
      vim.cmd("silent undo")
    else
      local post_lines = vim.api.nvim_buf_line_count(bufnr)
      vim.notify(string.format("[mlr] OK (%d→%d lines) — %s", pre_lines, post_lines, mlr_cmd), vim.log.levels.INFO)
    end

    vim.fn.winrestview(view)

    -- csvview 재활성화: defer로 buffer change autocmd 처리 후 attach
    if was_active and csvview_ok then
      vim.defer_fn(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          pcall(csvview.enable, bufnr)
          vim.cmd("redraw!")
        end
      end, 50)
    end
    _ = success
  end)
end

map("n", "<leader>cs", function() mlr_pipe("sort -f", "Sort by column(s) (comma-separated): ") end,
  { desc = "CSV: Sort by column (lexical asc)" })
map("n", "<leader>cS", function() mlr_pipe("sort -nr", "Sort by column (numeric desc): ") end,
  { desc = "CSV: Sort by column (numeric desc)" })
map("n", "<leader>cF", function() mlr_pipe("filter", "Filter expression (e.g. $mallType==\"I_SMARTSTORE\"): ") end,
  { desc = "CSV: Filter rows (mlr expression)" })

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
