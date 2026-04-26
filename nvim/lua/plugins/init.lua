return {
  {
    "stevearc/conform.nvim",
    -- event = 'BufWritePre', -- uncomment for format on save
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

  -- {
  -- 	"nvim-treesitter/nvim-treesitter",
  -- 	opts = {
  -- 		ensure_installed = {
  -- 			"vim", "lua", "vimdoc",
  --      "html", "css"
  -- 		},
  -- 	},
  -- },
  --
  {
    "stevearc/conform.nvim",
    event = 'BufWritePre', -- 저장 직전에 실행되도록 설정
    config = function()
      require "configs.conform"
    end,
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
      table = {
        style = 'round', -- 표의 모서리를 둥글게(╭, ╮, ╰, ╯) 처리
        cell = 'padded',
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
    },
  },
}
