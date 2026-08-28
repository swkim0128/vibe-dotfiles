return {
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre", "BufNewFile" }, -- 저장 직전 + 새 버퍼 진입 시 로드
    cmd = { "Format", "ConformInfo" },
    opts = require "configs.conform",
  },

  -- These are some examples, uncomment them if you want to see them work!
  {
    "neovim/nvim-lspconfig",
    config = function()
      require "configs.lspconfig"
    end,
  },

  -- test new blink
  -- { import = "nvchad.blink.lazyspec" },

  -- Kotlin 구문 하이라이팅·구조 이동(treesitter) — NvChad 기본 파서 + kotlin 추가
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "lua", "luadoc", "printf", "vim", "vimdoc",
        "kotlin",
      },
    },
  },

  {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = {
      'nvim-treesitter/nvim-treesitter',
      'nvim-tree/nvim-web-devicons'
    },
    ft = { "markdown" },
    opts = {
      -- 기본 설정만으로도 매우 예쁩니다!

      -- 1. 제목 (Headings) 설정: Nerd Font 아이콘 적용 및 여백
      heading = {
        sign = true,
        icons = { '󰲡 ', '󰲣 ', '󰲥 ', '󰲧 ', '󰲩 ', '󰲫 ' },
        width = 'block', -- 배경을 화면 우측 끝까지 꽉 채움

        -- [1] 단계별 좌우 여백: H1이 가장 넓고 H4부터는 여백 없음
        left_pad  = { 3, 2, 1, 0, 0, 0 },
        right_pad = { 3, 2, 1, 0, 0, 0 },

        -- [2] 단계별 테두리 렌더링 켜기 (H1, H2만 상하 확장을 적용)
        border = { true, true, false, false, false, false },
        border_virtual = true,

        -- [3] 상/하단 테두리 문자 (단일 문자열 — 단계별 on/off 는 border 배열이 담당)
        above = '▄',
        below = '▀',
      },

      -- 2. 코드 블록 (Code Blocks) 설정: 화면을 꽉 채우는 배경색 적용
      code = {
        sign = false,
        width = 'block', -- 코드 블록이 텍스트 길이에 맞춰지지 않고 끝까지 채워짐
        right_pad = 1,
        disable_background = { 'diff' },
      },

      -- 3. 글머리 기호 (Bullets): 들여쓰기 뎁스별로 다른 아이콘 적용
      bullet = {
        icons = { '●', '○', '◆', '◇' },
        right_pad = 1,
      },

      -- 4. 체크박스 (Checkboxes): 할 일(TODO) 관리를 위한 직관적인 아이콘
      checkbox = {
        unchecked = { icon = '󰄱 ' }, -- 빈 체크박스 [ ]
        checked   = { icon = '󰱒 ' }, -- 완료된 체크박스 [x]
        custom = {
          -- 진행 중인 작업 [-] 입력 시 시계 아이콘으로 변환
          progress = { raw = '[-]', rendered = '󰥔 ', highlight = 'RenderMarkdownWarn' },
        },
      },

      -- 5. 인용구 (Blockquotes) 및 표 (Tables)
      quote = {
        icon = '┃',
      },
      -- 표: 옵션 키는 'table' 이 아니라 'pipe_table' 이다 (settings.lua M.pipe_table).
      -- 둥근 모서리는 style 이 아니라 preset 소관 (style enum = full|normal|none).
      pipe_table = {
        preset = 'round',
        cell = 'padded',
      },
      -- 표가 창 폭을 넘으면 본문만 wrap 되고 테두리(가상 텍스트)는 잘려 박스가 무너진다.
      -- 렌더 중에는 wrap 을 끄고 가로 스크롤로 본다. 편집 중에는 원래 값으로 복귀.
      win_options = {
        wrap = { default = vim.o.wrap, rendered = false },
      },
    },
  },

  {
    "kdheepak/lazygit.nvim",
    cmd = {
      "LazyGit",
      "LazyGitConfig",
      "LazyGitCurrentFile",
      "LazyGitFilter",
      "LazyGitFilterCurrentFile",
    },
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
  },

  -- csvview.nvim: CSV/TSV 컬럼 정렬 표시 (virtual text — 원본 미수정)
  {
    "hat0uma/csvview.nvim",
    ft = { "csv", "tsv" },
    cmd = { "CsvViewEnable", "CsvViewDisable", "CsvViewToggle" },
    opts = {
      parser = { comments = { "#", "//" } },
      view = {
        display_mode = "border",
        header_lnum = 1,
      },
    },
    config = function(_, opts)
      require("csvview").setup(opts)
    end,
  },

  -- nvim-tree: 긴 파일명이 잘리지 않도록 폭 가변 확장
  {
    "nvim-tree/nvim-tree.lua",
    opts = {
      view = {
        width = {
          min = 30,   -- 최소 폭
          max = -1,   -- 최장 파일명에 맞춰 자동 확장 (제한 없음)
          padding = 1,
        },
      },
      renderer = {
        full_name = true, -- 그래도 잘리는 경우 전체 이름 팝업 표시
      },
      -- 현재 편집 중인 파일을 트리에서 자동으로 펼쳐 하이라이트 —
      -- <leader>ff 로 위치 근처 파일을 열면 트리가 그 경로로 바로 이동(탭 드릴링 대체).
      update_focused_file = {
        enable = true,
        update_root = false, -- 루트는 바꾸지 않고 위치만 공개
      },
    },
  },

  -- diffview.nvim: 작업 후 변경 리뷰 — 좌측 변경파일 목록 + 우측 좌우 diff.
  -- nvim-tree 경로 드릴링 없이 "바뀐 파일만" 순회(<Tab>)하며 변경 부분을 하이라이트로 확인.
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewToggleFiles", "DiffviewFocusFiles", "DiffviewFileHistory" },
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      require("diffview").setup {}
    end,
  },
}
