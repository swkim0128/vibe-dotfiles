---
name: update-vibe-commands
description: Use when adding, editing, or removing commands from the personal vibe-tools command collection (commands.txt, aliases.zsh, tools() function)
---

# Update Vibe Commands

## Overview

개인 vibe-tools의 명령어 모음을 업데이트한다. 추가 위치는 용도에 따라 세 곳으로 나뉜다.

## 어디에 추가할지 결정

| 상황 | 파일 |
|------|------|
| fzf 팝업 메뉴에서 선택 실행 (`Ctrl+F`) | `commands.txt` |
| 짧은 단축 명령어 (항상 쓰는 것) | `aliases.zsh` — alias |
| btop/lazygit 같은 TUI 도구 선택 메뉴 | `aliases.zsh` — `tools()` 함수 |

## 파일 경로

```
~/Project/vibe-dotfiles/vibe-tools/commands.txt   ← Ctrl+F 팝업 명령어 목록
~/Project/vibe-dotfiles/zsh/aliases.zsh            ← alias / tools() 함수
```

> 심볼릭 링크이므로 dotfiles 경로를 직접 편집한다.

## commands.txt 형식

```
# ── 섹션 이름 ──────────────────────────────────────
🔧 표시될 이름 | 실행할 명령어
```

- `#` 줄은 주석(섹션 헤더), 빈 줄은 무시됨
- `|` 앞이 fzf에 표시되는 레이블, 뒤가 실제 실행 명령어
- 이모지를 앞에 붙이면 가독성이 좋아짐

**예시:**
```
# ── Git ─────────────────────────────────────────────
🌿 브랜치 목록 확인 | git branch -a
📤 현재 브랜치 푸시 | git push origin HEAD
```

## aliases.zsh — alias 추가

```bash
# ── 섹션 ─────────────────────────────────────────────
alias 단축어="실행명령어"
```

**예시:**
```bash
alias dk="docker"
alias dc="docker compose"
```

## aliases.zsh — tools() 함수에 TUI 도구 추가

`tools()` 함수 내 `cmds` 배열에 항목 추가:

```bash
"명령어:이모지  설명"
```

**예시:**
```bash
local cmds=(
  "btop:🖥️  시스템 모니터링"
  "lazygit:📦 Git UI"
  "yazi:📂 파일 탐색기"    # ← 추가
)
```

## 변경 후 적용

```bash
# aliases.zsh 변경 시
source ~/.zshrc

# commands.txt는 즉시 반영됨 (Ctrl+F 로 확인)
```
