---
type: project-note
project: vibe-dotfiles
status: draft
created: 2026-05-28
updated: 2026-05-28
note: 살아있는 초안(living draft) — 계속 수정/보강한다.
---

# vibe-dotfiles — 현재 설정 노트 (Living Draft)

> 이 문서는 **초안**이며 계속 수정한다. "현재 프로젝트의 설정 상태 스냅샷 + 진행 노트" 용도.
> 정본 아키텍처 설명은 `CLAUDE.md`, 세부 KB는 `docs/knowledge-base/` 참조. 본 노트는 빠른 현황 파악용.

## 0. 한 줄 요약
Mac **시스템·터미널 인프라** 원클릭 dotfiles. `./setup.sh` 단독 실행으로 zsh / tmux / nvim(NvChad) / vibe-tools / glow 구성. AI 하네스(CLAUDE-*.md·훅·settings.work.json)는 외부 `vibe-claude-plugin` 레포로 SoC 분리. Ghostty 설정은 레포 밖(`~/.config/ghostty/`).

---

## 1. 진입점 — `setup.sh`
- Homebrew → CLI 도구(50+: lsd, bat, fzf, fd, ripgrep, git-delta, btop, neovim, tmux, starship, yazi, gh, jq, glow …) 설치
- Oh My Zsh + Zinit, Claude Code + 마켓플레이스 등록(omc / swkim0128 / cc-claude)
- Tmux TPM 설치, nvim lua → `~/.config/nvim/lua` 심볼릭 링크, vibe-tools → `~/.config/vibe-tools` 링크 + 실행권한
- `zsh/aliases.zsh` source 라인을 `~/.zshrc`에 등록, Git Delta 글로벌 설정(side-by-side, line-numbers)
- 선택적: 외부 `vibe-claude-plugin` 하네스 통합(미설치여도 정상 동작 — graceful degradation)

## 2. Zsh — `zsh/aliases.zsh`
- `vim`/`vi` → `nvim`, `EDITOR=nvim`
- `lg=lazygit`, `gco()`(브랜치 fzf, 최신순+로그 프리뷰), `gbd()`(브랜치 다중삭제)
- `vhelp`/`vibe` → vibe-tools 호출, `Ctrl+F` 위젯(my-tools.sh 팝업 런처), `tools()` fzf 도구 메뉴

## 3. Tmux — `tmux/.tmux.conf`
- **Prefix**: `Ctrl+Space` (보조 `Ctrl+b` 유지)
- Neovim 통합: `escape-time=10`, `focus-events=on`. 인덱스 1부터, 자동 재번호. 마우스 on(5줄 스크롤)
- **Pane 이동(prefix 없이)**: `Option+hjkl`, `Option+ㅗㅓㅏㅣ`(한글 IME 대응) → L/D/U/R
- **Pane 이동(prefix)**: `Prefix + hjkl` / `ㅗㅓㅏㅣ` (IME 무관 항상 동작)
- 주요 바인딩: `Prefix+Tab` yazi, `Prefix+M` my-tools 팝업, `Prefix+p` para 전환, `Prefix+f` 프로젝트 네비게이터, `Prefix+x` 세션종료→para, `Prefix+C` Claude Skills 팝업, `Prefix+?` 치트시트, `Prefix+r` 설정 리로드
- 테마: Catppuccin **macchiato**, 상태바(세션·디렉토리·git·CPU·RAM·배터리·시간)
- 플러그인: tpm, catppuccin, tmux-cpu/battery, **resurrect+continuum**(15분 자동저장, claude/nvim/npm/yazi 추적)

## 4. Neovim — `nvim/lua/` (NvChad)
- `options.lua`: 인코딩 시도순서 `ucs-bom,utf-8,cp949,euc-kr,latin1`(한글). 스왑/백업 off. Treesitter 폴딩
- `chadrc.lua`: catppuccin + 투명 배경. `mappings.lua`: `;`→`:`, `jk`→ESC, `Ctrl+/` 주석, `Leader+gg` LazyGit, `Alt+i` 플로팅 터미널
- `autocmds.lua`: VimEnter/FocusGained 시 **한→영 자동전환(im-select)**, CSV csvview 자동, 저장 시 줄끝 공백 제거(md 제외)
- 커스텀 플러그인: conform.nvim(자동포맷), render-markdown, lazygit, csvview, nvim-tree

## 5. vibe-tools/ — 셸 스크립트
| 파일 | 역할 |
|------|------|
| `vibe.sh` | PARA 워크플로우: main(베이스캠프)/start(프로젝트 fzf→nvim+claude 분할)/fzf/cast(원격 지시)/done |
| `overnight_worker.sh` | 02:00 launchd 야간 자율 분석: git 활동→PARA 블루프린트, 진행내역 append, TOP 과제 스파이크 |
| `my-tools.sh` | 컨텍스트별(common/main/sub) 명령 팝업. tmux 내 send-keys / 외부 stdout |
| `claude-send.sh` | tmux 패널 간 Claude 메시지 전송. symlink: `claude-delegate.sh`(위임)/`claude-callback.sh`(콜백) |
| `claude-skills.sh` | Claude 스킬 팝업(캐시 목록 fzf, `--refresh`) |
| `claude-switch.sh` | 타 패널 claude 프로젝트 경로 변경 재기동 |
| `issue-start.sh` | 이슈 브랜치 자동화: fetch→develop 최신화→`feature/<이슈>` |
| `vhelp.sh` | 치트시트 뷰어(nvim -R) |
| 기타 | `cheatsheet.md`, `sessionizer-paths.txt`, `commands_{common,main,sub}.txt` |

## 6. Ghostty — `~/.config/ghostty/config` ⚠️ 레포 미관리(이 dotfiles 밖)
- theme: Catppuccin Macchiato / font: D2Coding(+Ligature) 14, `calt`+`liga` 리가처
- window: decoration on, padding 10, `window-theme=system` / 배경 opacity 0.9 + blur 15
- cursor block + blink, `mouse-hide-while-typing`, `copy-on-select=true`, scrollback 10000
- **`macos-option-as-alt = true`** ← Option 키 관련(§8 이슈 참조)
- `shell-integration=zsh`, `confirm-close-surface=false`

## 7. glow / docs / 기타
- `glow/`: `glow.yml`(style=catppuccin-macchiato, pager on, width auto) + 색상 테마 json
- `docs/`: `harness-engineering-snapshot-2026-05-09.md`, `harness-pipeline.md`, `claude-headless-automation.md`, `csvview-issue-draft.md`, **본 파일**
- `docs/knowledge-base/`(KB SSoT): `kb_iconv_cache.md`, `kb_mac_system.md`, `kb_notion.md`, `README.md`
- `.claude/`: `settings.local.json`, `audit-log.jsonl`, `docs/`(로컬 분석 캐시) / `tests/`: bats

---

## 8. 현재 이슈 / 진행 노트

### [OPEN] 한글 IME 상태에서 `Option + ㅗㅓㅏㅣ` 페인 이동 미동작
- **요청**: 한글 입력 중에도 `Option+ㅗㅓㅏㅣ`(=Option+hjkl)로 페인 이동.
- **현황 점검**:
  - tmux: `M-h/j/k/l` **및** `M-ㅗ/ㅓ/ㅏ/ㅣ` 바인딩 모두 존재 + 라이브 서버 로드 확인됨(`tmux list-keys -T root`). 설정 결함 아님.
  - ghostty: `macos-option-as-alt = true` 이미 설정됨.
- **근본 원인**: macOS에서 **CJK IME(한글/중국어)가 활성일 때 Option/Alt 모디파이어가 IME에 흡수되어 tmux로 Meta로 전달되지 않음**. IME가 조합한 글자(ㅗ)는 모디파이어가 제거된 일반 텍스트로 들어오므로 `M-ㅗ`는 물론 `M-h`도 트리거 불가. → tmux/ghostty 설정으로 완전 해결 불가한 **알려진 한계**(Ghostty discussion [#10310](https://github.com/ghostty-org/ghostty/discussions/10310), 확장키 관련 [#9340](https://github.com/ghostty-org/ghostty/discussions/9340)).
- **현실적 대안**:
  1. ✅ **`Prefix(Ctrl+Space) + ㅗㅓㅏㅣ`** — IME 무관 항상 동작(이미 바인딩됨, lines 107–110). 가장 신뢰성 높음.
  2. 이동 직전 잠깐 영문 전환 후 `Option+hjkl`(워크플로우 깨짐).
  3. IME를 거치지 않는 별도 모디파이어/단축키 재설계(예: `Ctrl`/`Cmd` 기반 페인 이동) 검토.
- **TODO**: tmux 설정 주석(현재 iTerm2만 언급)을 Ghostty + IME 한계 반영으로 갱신. 사용 흐름에 1안이 맞는지 사용자 확인 필요.

### [참고] 서브에이전트 파일 쓰기 제약 (이 환경)
- 백그라운드 서브에이전트는 `Edit/Write/cp` 및 일부 경로 Read가 권한 정책으로 차단됨. → **조사/탐색(read-only)만 위임**, 실제 파일 수정은 메인 세션에서 수행.

---

## 변경 이력
- 2026-05-28: 초안 작성 (설정 인벤토리 + 한글 IME 페인이동 이슈 진단).
