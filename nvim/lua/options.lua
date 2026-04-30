require "nvchad.options"

-- add yours here!

-- local o = vim.o
-- o.cursorlineopt ='both' -- to enable cursorline!

-- 파일 읽기 인코딩 시도 순서
vim.opt.fileencodings = { "ucs-bom", "utf-8", "cp949", "euc-kr", "latin1" }

-- 스왑/백업 파일 비활성화
vim.opt.swapfile = false
vim.opt.backup = false

-- 한글 IME 상태에서 노말/비주얼 모드 명령 인식 (두벌식)
vim.opt.langmap = "ㅂq,ㅈw,ㄷe,ㄱr,ㅅt,ㅛy,ㅕu,ㅣi,ㅐo,ㅔp," ..
                 "ㅁa,ㄴs,ㅇd,ㄹf,ㅎg,ㅗh,ㅓj,ㅏk,ㅡl," ..
                 "ㅋz,ㅌx,ㅊc,ㅍv,ㅠb,ㅜn"
