# Vibe Coding Cheat Sheet

> `q` 또는 `:q` 로 닫기  |  `/` 검색  |  `gg/G` 맨 위/아래

---

## 🚀 실전 활용 시나리오 (PARA Workflow)

### 1. 기획 및 작업 시작 (Basecamp)

> **상황:** `para` 세션에서 작업 노트를 읽고 새로운 태스크를 시작할 때

- **행동:** 터미널에 `vibe start [프로젝트명] [작업명]` 입력
- **결과:** 타겟 프로젝트 폴더에 백그라운드 세션이 열리고 에디터와 AI가 대기 상태로 전환됨

### 2. 서브 에이전트 작업 위임 (Delegation)

> **상황:** 화면을 전환하지 않고 타겟 프로젝트의 클로드에게 코딩을 지시할 때

- **행동:** 현재 창에서 `Prefix + d` (또는 `vibe cast`) 입력 후 지시사항 작성
- **결과:** 타겟 세션의 클로드가 백그라운드에서 코딩을 수행하고 완료 시 알림(Callback)을 보냄

### 3. 현장 검수 및 반영 (Review & Commit)

> **상황:** 완료 알림을 받고 코드를 확인한 뒤 Git에 반영할 때

1. `Prefix + f` 를 눌러 타겟 세션으로 화면 전환
2. Nvim에서 코드 검토 (필요시 검색 등 활용)
3. 터미널에서 `ga .` → `gcmsg "커밋 내용"` → `gp` 입력하여 푸시

### 4. 상황 종료 및 복귀 (Teardown)

> **상황:** 작업과 푸시가 모두 끝나고 다시 본진으로 돌아갈 때

- **행동:** `Prefix + x` (또는 `vibe done`) 입력
- **결과:** 현재 작업 세션이 파괴되고, 자동으로 `para` 세션(작업 노트 화면)으로 즉시 복귀

### 5. 작업 노트 갱신 (Documentation)

> **상황:** 복귀 후 `todo.md`에 방금 끝난 작업 내역을 기록할 때

- **행동:** `Prefix + C` 를 눌러 프롬프트 라이브러리를 열고 **'작업노트 업데이트'** 스킬을 주입

---

## 🛠️ Vibe Tools (Tmux Popup)

| 단축키 | 팝업 제목 | 기능 |
|--------|-----------|------|
| `Prefix + f` | Project Navigator | 프로젝트 fzf 선택 → nvim 70% + claude 30% 레이아웃 자동 구성 |
| `Prefix + C` | Claude Skills | 현재 세션의 Claude 패널에 스킬 프롬프트 자동 전송 |
| `Prefix + M` | My Command Menu | 자주 쓰는 명령어 fzf 팝업 (`commands.txt` 기반) |
| `Prefix + p` | Project Jumper | `~/Projects` 폴더 fzf 선택 → tmux 세션 생성/전환 |
| `Prefix + Tab` | yazi | 현재 경로에서 yazi 파일 탐색기 50% 분할 오픈 |
| `Prefix + ?` | Vibe Coding Cheat Sheet | 이 매뉴얼 팝업 (읽기 전용 nvim) |
| `Ctrl + F` | My Command Menu | 셸에서 바로 명령어 팝업 실행 |
| `vhelp` | — | 터미널에서 이 매뉴얼 직접 열기 |

### IPC — 패널 간 클로드 통신

```bash
# 1. 패널 ID 확인
tmux list-panes -a -F '#{pane_id} #{session_name}:#{window_index}.#{pane_index} #{pane_current_command}'

# 2. 작업 위임 (현재 패널 → 타겟 패널)
~/.config/vibe-tools/claude-delegate.sh '%3' '작업 내용'

# 3. 완료 보고 (타겟 패널 → 지휘관 패널)
~/.config/vibe-tools/claude-callback.sh '%1' '작업 결과 요약'
```

---

## 🪟 Tmux 핵심 단축키

### 프리픽스

| 키 | 설명 |
|----|------|
| `Ctrl + Space` | Prefix (기본) |
| `Ctrl + b` | Prefix (보조) |

### 세션 / 윈도우

| 단축키 | 기능 |
|--------|------|
| `Prefix + s` | 세션 트리 (전환) |
| `Prefix + $` | 세션 이름 변경 |
| `Prefix + d` | 세션 분리 (detach) |
| `Prefix + L` | 마지막 윈도우로 이동 |
| `Prefix + c` | 새 윈도우 생성 |
| `Prefix + ,` | 윈도우 이름 변경 |
| `Prefix + 1~9` | 윈도우 번호로 이동 |
| `Prefix + r` | tmux.conf 즉시 리로드 |

### 패널 분할 / 이동

| 단축키 | 기능 |
|--------|------|
| `Prefix + %` | 좌우 분할 |
| `Prefix + "` | 상하 분할 |
| `Option + h/j/k/l` | 패널 이동 (prefix 없이) |
| `Prefix + z` | 현재 패널 전체화면 토글 |
| `Prefix + x` | 현재 패널 닫기 |

### 패널 크기 조절

| 명령어 (Prefix + :) | 기능 |
|---------------------|------|
| `m70` | 패널 1을 가로 70%로 조정 |
| `m50` | 좌우 패널 균등 분할 |
| `killall` | 현재 세션 전체 종료 |

### 복사 모드 (vi)

| 단축키 | 기능 |
|--------|------|
| `Prefix + [` | 복사 모드 진입 |
| `v` | 선택 시작 |
| `y` | 복사 (pbcopy 연동) |
| `q` | 복사 모드 종료 |

### 세션 저장 / 복구 (Resurrect & Continuum)

| 단축키 | 기능 |
|--------|------|
| `Prefix + Ctrl+s` | 세션 수동 저장 |
| `Prefix + Ctrl+r` | 세션 수동 복구 |
| _(자동)_ | 15분마다 자동 저장, tmux 시작 시 자동 복구 |

### 플러그인 (TPM)

| 단축키 | 기능 |
|--------|------|
| `Prefix + I` | 플러그인 설치 |
| `Prefix + U` | 플러그인 업데이트 |
| `Prefix + Alt+u` | 미사용 플러그인 제거 |

---

## 📝 Neovim (NvChad) 주요 단축키

> Leader = `Space`

### 파일 탐색 (Telescope)

| 단축키 | 기능 |
|--------|------|
| `Space + ff` | 파일 이름 검색 |
| `Space + fg` | 전체 텍스트(grep) 검색 |
| `Space + fb` | 열려있는 버퍼 목록 |
| `Space + fh` | 도움말 태그 검색 |

### 파일 탐색기 (NvimTree)

| 단축키 | 기능 |
|--------|------|
| `Space + e` | NvimTree 토글 |
| `a` | 새 파일/폴더 생성 |
| `d` | 삭제 |
| `r` | 이름 변경 |

### 버퍼 이동

| 단축키 | 기능 |
|--------|------|
| `Tab` | 다음 버퍼 |
| `Shift + Tab` | 이전 버퍼 |
| `Space + x` | 현재 버퍼 닫기 |

### LSP

| 단축키 | 기능 |
|--------|------|
| `gd` | 정의로 이동 |
| `gr` | 참조 목록 |
| `K` | 호버 문서 |
| `Space + ca` | 코드 액션 |
| `Space + rn` | 심볼 이름 변경 |
| `[d` / `]d` | 이전/다음 진단 |

### 편집

| 단축키 | 기능 |
|--------|------|
| `Space + /` | 현재 줄 주석 토글 |
| `Space + fm` | 포매터 실행 (conform.nvim) |
| `Space + s` | 선택 영역/문단 → tmux 패널 전송 (vim-slime) |

### Mason (LSP 서버 관리)

| 명령어 | 기능 |
|--------|------|
| `:Mason` | LSP 서버 관리 UI |
| `:MasonInstallAll` | 설정된 서버 전체 설치 |
| `:Lazy` | 플러그인 관리 UI |

---

## 🚀 Git / Zsh 단축어

### Oh My Zsh git 플러그인 주요 alias

| alias | 원래 명령어 | 설명 |
|-------|------------|------|
| `gst` | `git status` | 상태 확인 |
| `ga` | `git add` | 스테이징 |
| `gaa` | `git add --all` | 전체 스테이징 |
| `gc` | `git commit -v` | 커밋 |
| `gcmsg` | `git commit -m` | 메시지 커밋 |
| `gco` | `git checkout` | 브랜치 전환 |
| `gcb` | `git checkout -b` | 새 브랜치 생성 후 전환 |
| `gb` | `git branch` | 브랜치 목록 |
| `gbd` | `git branch -d` | 브랜치 삭제 |
| `gl` | `git pull` | 풀 |
| `gp` | `git push` | 푸시 |
| `gpf` | `git push --force-with-lease` | 안전한 강제 푸시 |
| `glog` | `git log --oneline --decorate --graph` | 그래프 로그 |
| `gd` | `git diff` | 변경사항 확인 |
| `gds` | `git diff --staged` | 스테이징 변경사항 |
| `gsta` | `git stash push` | 스태시 저장 |
| `gstp` | `git stash pop` | 스태시 복원 |
| `gstl` | `git stash list` | 스태시 목록 |
| `grb` | `git rebase` | 리베이스 |
| `grbi` | `git rebase -i` | 인터랙티브 리베이스 |
| `grs` | `git restore` | 변경사항 되돌리기 |

### 커스텀 alias / 도구

| alias | 기능 |
|-------|------|
| `vim` / `vi` | nvim 실행 |
| `lg` | lazygit 실행 |
| `cd` | zoxide (스마트 디렉토리 이동) |
| `tools` | fzf 도구 런처 (btop, lazygit, duf 등) |
| `vhelp` | 이 매뉴얼 열기 |

### zoxide

| 명령어 | 기능 |
|--------|------|
| `cd 프로젝트명` | 히스토리 기반 스마트 이동 |
| `cd -` | 이전 디렉토리로 이동 |

---

*`~/.config/vibe-tools/cheatsheet.md` — Prefix+? 또는 `vhelp`로 열기*
