# Vibe Dotfiles Architecture Guide

이 레포지토리는 사용자의 Mac 개발 환경을 원클릭으로 구축하는 핵심 설정(Dotfiles) 저장소입니다.

## 🏗️ 역할 분담 (중요)
- **이 레포지토리 (`vibe-dotfiles`):** 터미널 껍데기, Zsh, Tmux, Neovim 설정, 시스템 스크립트, Claude Code의 '환경 설정(`settings.json`)'을 담당합니다.
- **마켓플레이스 레포지토리 (`vibe-claude-plugin`):** Claude Code의 프롬프트, 스킬, MCP 등 '지능과 페르소나'를 전담합니다. 
⚠️ **절대 이 레포지토리 안에 직접 스킬(`SKILL.md`)을 추가하지 마세요. 스킬은 마켓플레이스 레포지토리에서 관리합니다.**

## 🚀 설치 진입점
- 모든 설치와 심볼릭 링크 구성은 `./setup.sh` 단일 스크립트를 통해 이루어집니다.
- 환경 분기: 설치 시 개인용(`settings.json`)과 업무용(`settings.work.json`) 환경을 선택할 수 있습니다.

## 🛠️ 주요 구조
- `tmux/` : `.tmux.conf` 및 세션 설정
- `nvim/lua/` : NvChad 기반 에디터 설정
- `vibe-tools/` : 커스텀 셸 스크립트 (`vibe.sh`, `claude-delegate.sh` 등)
- `zsh/` : `aliases.zsh` 관리
