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

---

## ⚙️ 하네스 규칙 (Harness Rules)

### 언어 & 스택
- 주요 언어: Bash, Zsh, Lua (Neovim), Markdown
- 모든 셸 스크립트는 `set -euo pipefail` 으로 시작해야 합니다.
- 외부 도구 호출 전 `command -v <tool>` 로 존재 여부를 확인하세요.

### 도구 기반 검증
셸 스크립트(`.sh`) 작성·수정 후 반드시 실행:
```bash
shellcheck <파일명>      # 정적 분석 — 문법 오류 및 취약점 검출
bash -n <파일명>         # shellcheck 미설치 시 최소 구문 검사 대안
```
`tests/` 디렉터리에 `bats` 테스트가 있는 경우:
```bash
bats tests/             # 단위 테스트 실행
```

### 세션 인수인계
**작업 중단 전:** 완료 항목, 남은 TODO, 발생한 에러를 `todo.md`에 기록하세요.

**작업 재개 시:** 가장 먼저 `todo.md`를 읽어 이전 컨텍스트를 파악하고 최우선 과제를 확인하세요.

`todo.md` 형식:
```markdown
## 완료
- [x] 항목

## TODO
- [ ] 항목

## 에러 / 블로커
- 현상: / 원인: / 해결 여부:
```
