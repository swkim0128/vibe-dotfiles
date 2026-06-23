# HANDOFF — 2026-06-23 (cmux/Ghostty 터미널 셋업, 집에서 이어서)

> 집(개인 Mac)에서 이어가세요. vibe-dotfiles 는 git 동기화 — 먼저 `git -C <vibe-dotfiles 경로> pull`.

## ✅ 회사 머신에서 완료 (master 커밋 d15939c, 원격 푸시됨)
- `ghostty/config` 신규 — Catppuccin Macchiato, D2Coding, opacity 0.9 등 (기존 ~/.config/ghostty/config 와 내용 동일, 후행공백만 정리)
- `setup.sh` — GUI 터미널 앱 섹션 추가: `install_cask ghostty` + `install_cask cmux` (cmux 는 homebrew core, 커스텀 tap 불필요) + `~/.config/ghostty/config` 심볼릭 링크 + `cmux hooks setup` 수동 안내 출력
- `CLAUDE.md` / `README.md` — `ghostty/` 디렉토리 문서화
- 회사 머신 `~/.config/ghostty/config` → 레포 심볼릭 링크 적용 완료 (원본은 `config.pre-dotfiles.bak` 백업)

## 🔴 집에서 할 일 (cmux 앱 설치 — sudo 필요라 회사 비대화형 세션에서 막혔던 부분)
1. `git -C <vibe-dotfiles 경로> pull` 로 최신 받기
2. 터미널에서 직접 실행 (sudo 비밀번호 프롬프트 뜸):
   - `brew install --cask ghostty`
   - `brew install --cask cmux`
   (또는 `./setup.sh` 재실행 — `install_cask` 멱등, 이미 설치된 건 skip. 단 setup.sh 전체는 zsh/tmux/nvim 도 재배포함)
3. 집 머신에도 ghostty config 심볼릭 링크 적용: `./setup.sh` 가 자동 처리하거나 수동으로 `ln -s <레포>/ghostty/config ~/.config/ghostty/config` (기존 파일 있으면 백업 먼저)
4. (선택) cmux 실행 → 테마/폰트가 ghostty config 에서 상속되는지 확인
5. (선택) AI 에이전트 알림 연동: `cmux hooks setup` — `~/.claude` 훅 수정함 (SoC 상 dotfiles 가 자동 실행 안 함, 수동 결정)

## 참고
- cmux = libghostty 기반 macOS 터미널 (vertical tabs + AI 에이전트 알림, cmux.com). `~/.config/ghostty/config` 의 테마/폰트/색상 상속, 자체 설정은 `~/.config/cmux/cmux.json`
- brew cask 는 비대화형 Claude 세션에서 sudo 때문에 설치 불가 — 메모리 `brew-cask-needs-sudo` 참고
