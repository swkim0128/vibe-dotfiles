# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 설치 및 적용

새 Mac에서 전체 환경 설치:
```bash
./setup.sh        # 심볼릭 링크 생성 및 zsh alias 등록
source ~/.zshrc   # alias 즉시 적용
```

tmux 설정 변경 후 즉시 적용:
```bash
tmux source-file ~/.tmux.conf
```

## 아키텍처 개요

모든 설정 파일은 이 저장소에 있고, `setup.sh`가 각 경로에 심볼릭 링크를 생성합니다. 파일을 수정하면 시스템에 즉시 반영됩니다.

| 저장소 경로 | 링크 대상 |
|------------|----------|
| `tmux/.tmux.conf` | `~/.tmux.conf` |
| `vibe-tools/` | `~/.config/vibe-tools/` |
| `nvim/lua/` | `~/.config/nvim/lua/` |
| `vibe-tools/claude-config/settings.json` | `~/.claude/settings.json` |
| `vibe-tools/claude-config/hooks/` | `~/.claude/hooks/` |
| `zsh/aliases.zsh` | `~/.zshrc`에서 source |

`vibe-config@swkim0128` 플러그인은 GitHub URL을 마켓플레이스로 등록하여 설치하므로 로컬 클론이 필요하지 않습니다. `~/.claude/plugins/cache/swkim0128/vibe-config/` 가 Claude Code에 의해 관리됩니다.

## 주요 컴포넌트

### vibe-tools/
tmux 팝업 메뉴, 프로젝트 세션 매니저, Claude IPC 스크립트가 모여 있습니다.

- **`tmux-sessionizer.sh`** — `Prefix+f`: fzf로 프로젝트 폴더 선택 후 tmux 세션 전환
- **`my-tools.sh`** — `Prefix+M` / `Ctrl+F`: 커스텀 명령어 fzf 팝업
- **`claude-delegate.sh`** / **`claude-callback.sh`** — tmux 패널 간 Claude IPC (작업 위임/보고)
- **`claude-skills.sh`** — `Prefix+C`: Claude 스킬 목록 팝업

### vibe-tools/claude-config/
Claude Code 전역 설정. `settings.json`에서 활성화된 플러그인 목록을 관리합니다.

### `vibe-config@swkim0128` 플러그인
개인 Claude Code 플러그인. [swkim0128/vibe-claude-plugin](https://github.com/swkim0128/vibe-claude-plugin) 레포에서 관리하며, `setup.sh` 가 GitHub URL을 `swkim0128` 마켓플레이스로 등록하고 `claude plugin install vibe-config@swkim0128` 로 설치합니다 (로컬 클론 불필요).

캐시 경로: `~/.claude/plugins/cache/swkim0128/vibe-config/`
- `hooks/hooks.json`: Stop 시 `Glass.aiff`, Notification 시 `Ping.aiff` + macOS 알림
- `skills/claude-ipc/SKILL.md`: 패널 간 작업 위임 워크플로우 스킬
- `prompts/*.txt`: `claude-skills.sh` (`Prefix+C`) 가 캐시 경로에서 직접 읽음
- `mcp/mcp-config.json`: `setup.sh` 가 `~/.claude/claude.json` 의 `mcpServers` 에 병합

### nvim/lua/
NvChad 기반 Neovim 설정. `chadrc.lua`(테마), `mappings.lua`(키맵), `plugins/init.lua`(추가 플러그인), `configs/`(LSP/포매터) 구조입니다.

## Claude IPC 사용법

다른 tmux 패널의 Claude에게 작업을 위임할 때:
```bash
# 패널 ID 확인
tmux list-panes -a -F '#{pane_id} #{session_name}:#{window_index}.#{pane_index} #{pane_current_command}'

# 작업 위임 (현재 패널 → %3 패널)
~/.config/vibe-tools/claude-delegate.sh '%3' '작업 내용'

# 완료 보고 (위임받은 패널 → 지휘관 패널)
~/.config/vibe-tools/claude-callback.sh '%1' '결과 요약'
```
