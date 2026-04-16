require "nvchad.options"

-- add yours here!

-- local o = vim.o
-- o.cursorlineopt ='both' -- to enable cursorline!

-- 파일 읽기 인코딩 시도 순서
vim.opt.fileencodings = { "ucs-bom", "utf-8", "cp949", "euc-kr", "latin1" }

-- 스왑/백업 파일 비활성화
vim.opt.swapfile = false
vim.opt.backup = false
