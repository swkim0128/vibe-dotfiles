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
Mac **시스템·터미널 인프라** 원클릭 dotfiles. `./install.sh` 단독 실행으로 zsh / tmux / nvim(NvChad) / vibe-tools / glow 구성. AI 하네스(CLAUDE-*.md·훅·settings.work.json)는 외부 `vibe-claude-plugin` 레포로 SoC 분리. Ghostty 설정은 레포 밖(`~/.config/ghostty/`).

---

## 1. 진입점 — `install.sh`
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

### 2026-11-13 Neovim 읽기 전용 점검

기존 `Helix_도입조사_PHP53_및_실사용_2026-11-13.md`의 기능 대응·Kotlin 서버 차이·CSV 이슈 조사를 재사용했다. Yazi 팝업·Helix 배경 변경 `eb2d7df`는 유지한다. 아래는 현재 개인 기기의 설정·설치 파일을 읽은 결과이며 Neovim 실행·테스트·doctor·벤치마크·업데이트는 하지 않았다.

설치된 `~/.config/nvim/lua`는 이 저장소 `nvim/lua`의 심링크다. 설치본 `lazy-lock.json`의 31개 항목은 각 플러그인 checkout HEAD와 모두 일치했다. 다만 부트스트랩 `init.lua`와 잠금 파일은 이 저장소의 관리·설치 대상이 아니므로 새 기기에서 같은 구성을 재현한다는 보장은 없다. 최신 upstream 유지보수 상태나 각 checkout의 로컬 수정 여부까지 감사한 결과는 아니다.

| 우선순위·구분 | 파일 근거와 현재 상태 | 개선 효과·부작용·미확인 |
|---|---|---|
| P1 설정상 문제 — Kotlin | `nvim/lua/configs/lspconfig.lua:9`는 없는 `~/.local/share/nvim/mason/bin/kotlin-lsp`를 고정한다. 실제 실행 파일은 `/opt/homebrew/bin/kotlin-lsp`다. | 기존 실행 파일을 찾도록 연결하면 서버 시작 경로가 맞는다. 서버·JDK·프로젝트 호환성은 별도이며 실제 연결은 미검증. Helix 기본 `kotlin-language-server`와 같은 서버라고 취급하지 않는다. |
| P1 설정상 문제 — 주석 | `nvim/lua/mappings.lua:13`의 네 매핑은 `Comment.api`를 호출하나 사용자·NvChad 플러그인 선언, 잠금·설치 목록에 해당 모듈이 없다. NvChad 기본 `Space /`는 내장 `gcc`/`gc`를 사용한다. | 추가 플러그인 없이 같은 내장 동작에 연결할 수 있다. 일반·비주얼 모드의 선택 범위와 터미널 `Ctrl+/` 전달은 실제 확인이 필요하다. `Ctrl+/`·`Ctrl+_` 두 표기는 호환용이며 그 자체를 결함으로 보지 않는다. |
| P1 연결 누락 — LSP·formatter | 설치된 `NvChad/lua/nvchad/configs/mason.lua`는 `PATH="skip"`이다. Mason bin에는 black·stylua·php-cs-fixer만 있고 현재 셸 PATH에서는 세 도구와 lua-language-server·HTML/CSS 서버·php를 찾지 못했다. Intelephense·Prettier는 Homebrew 경로에서 발견했다. php-cs-fixer wrapper도 `php`를 호출한다. | 필요한 서버와 formatter의 경로·실행 런타임을 명시하면 기능을 예측하기 쉽다. Mason PATH 전체를 앞에 넣으면 프로젝트·mise 실행 파일보다 우선할 수 있으므로 범위를 정해야 한다. 실행 중 Neovim PATH·프로젝트 로컬 실행 파일·실제 LSP attach는 미확인이다. |
| P1 설정상 위험 — 저장·PHP 경계 | `configs/conform.lua:7`·`:11`은 PHP를 포함해 저장 시 500ms 포맷과 LSP fallback을 적용한다. `autocmds.lua:23`은 Markdown 외 모든 파일의 줄끝 공백을 지운다. `configs/lspconfig.lua`에는 PHP 5.3 대상 설정이 없고 기존 버전 명시 포맷 경로와 연결되지 않았다. | 프로젝트·파일형식·인코딩별 저장 정책을 정하면 레거시 파일의 의도치 않은 변경을 줄인다. 제외한 파일은 수동 정리가 필요하다. 인코딩 감지 목록은 저장·formatter·서버의 무손실 보장이 아니며 실제 손상 발생은 확인하지 않았다. 프로젝트별 설정도 이번 조사 대상 밖이다. |
| P2 키 충돌 — 완성 호출 | `herdr/config.toml:7`의 Ctrl+Space 접두 키와 설치된 `NvChad/.../configs/cmp.lua:19`의 수동 완성 호출이 같다. | Herdr 접두 키 또는 완성 호출 키 중 한쪽만 조정할 수 있다. 다른 도구의 Ctrl+Space 사용에도 영향을 줄 수 있으며 실제 입력 전달은 미검증이다. |
| P2 재현성·선택 개선 | `manifests/common.conf`는 Neovim lua 디렉터리만 연결한다. `mappings.lua:75`의 Miller 동작은 CSV 입력으로 고정돼 TSV 표시 지원과 범위가 다르다. `autocmds.lua:9`의 im-select는 현재 PATH에서 미발견이다. | 부트스트랩·잠금 관리, TSV 처리/제한, 입력기 전환 의존성을 각각 선택해 보완할 수 있다. 잠금 관리에는 업데이트 절차, TSV에는 구분자 보존, 입력기 변경에는 사용 습관을 고려해야 한다. 이번에 설치·수정하지 않았다. |

사용자 `Alt+i`는 NvChad 기본 매핑을 큰 창으로 의도적으로 덮어쓴다. `Space cf`/`:Format`과 기본 `Space fm`은 같은 formatter의 별도 수동 진입점이며, 중복 실행 증거는 없다. `Space cf`는 비동기·명시적 범위 처리, `Space fm`은 기본 동기 경로여서 무조건 하나를 삭제하지 않는다. NvChad와 사용자 conform 선언도 동일 플러그인 설정을 병합하는 구조다. 설치된 Conform은 `lsp_fallback=true`를 `lsp_format="fallback"`으로 처리하므로 외부 formatter와 LSP를 항상 연속 호출한다는 해석은 맞지 않는다. 수동 포맷 뒤 저장하면 별도의 저장 포맷은 다시 실행될 수 있다.

LSP 완성 capabilities·LuaSnip 확장·nvim-cmp의 LSP/snippet/buffer/Lua/path 소스와 진단 표시는 NvChad 기본 설정에 연결돼 있다. 설정 연결을 실제 완성·진단 성공으로 보고하지 않는다. 현재 소스에서 별도 LSP 저장 포맷 훅은 발견하지 않았다.

병행 사용은 단순 UTF-8 편집·탐색에서 Helix를 시험하고, LuaSnip 모음·Markdown 렌더링·CSV 가상 표·Miller 가공·고정 트리·Diffview 이력·접기가 필요한 작업은 Neovim에 남기는 순서가 적절하다. gitsigns·Diffview·lazygit은 변경 구간·리뷰·Git 조작이라는 역할 차이가 있어 겹치는 메뉴만으로 제거하지 않는다. CSV 렌더링의 기존 재현·가설은 [기존 이슈 초안](csvview-issue-draft.md)을 재사용하며 재현을 반복하지 않았다. 현재 느림의 측정 근거가 없으므로 플러그인 수나 nvim-tree 제한시간만으로 성능 결함을 판정하지 않는다.

우선 변경 후보는 Kotlin 실행 경로·주석 매핑·필요 실행 파일 연결·레거시 저장 정책이다. 실제 변경 범위는 사용자와 정한 뒤 적용한다. Yazi와 기존 Helix 인스턴스, Neovim 제품 설정은 이번 점검에서 변경하지 않았다.

### #12 Neovim 작업계획 — v1 · 2026-11-23

**v1 계획 작성 당시 기록이다.** 위 11/13 조사에서 나온 네 후보를 대상으로 하며, 당시 Neovim 제품 코드·설치·실행·검사는 수행하지 않았다. 이후 승인된 구현 상태는 아래 변경 기록에서 구분한다. #11 대시보드 개선은 사용자 요청으로 임시 보류하며 기존 요청의 owner·queued 상태는 변경하지 않는다.

기준은 `swkim0128/vibe-dotfiles`의 `master` 커밋 `51ed2f36a20676145d912d1ec48343cb3ecd3eeb`이다. 11/13 조사 결과를 재사용하고, 아래 코드 발췌에 필요한 기존 소스만 대조했다. 당시 설치 파일·PATH 관측을 오늘의 실행 결과로 갱신한 것은 아니다. 문서 형식은 설정 저장소의 [작업계획 템플릿](../../vibe-ai-config/skills/harness/task-plan/assets/work-plan.md), [변경 기록 템플릿](../../vibe-ai-config/templates/change-report.md), [작성 기준](../../vibe-ai-config/docs/change-documentation.md)을 필요한 항목만 적용했다.

#### 변경계획 — 같은 조건의 AS-IS / 예정 TO-BE

| 변경 ID·조건 | AS-IS — 현재 소스·기존 조사 | TO-BE — 구현 예정 | 이유·영향·유지 조건 |
|---|---|---|---|
| CHG-01 Kotlin 파일 열기 | Mason 아래의 `kotlin-lsp` 경로를 고정. 조사 당시 그 파일은 없고 Homebrew 실행 파일이 존재 | 선택한 실행 환경에서 기존 `kotlin-lsp`를 탐색하고, 없으면 Kotlin 서버만 시작하지 않고 이유 안내 | 잘못된 경로 호출 방지. JetBrains 서버·`--stdio` 유지. JDK·프로젝트 호환성과 실제 attach는 별도 확인 |
| CHG-02 일반·선택 영역 주석 | 네 단축키가 설치 목록에 없는 `Comment.api` 호출 | 기존 내장 주석 동작 `gcc`/`gc`에 연결 | 모듈 누락 제거. 일반/선택 범위 및 `<C-/>`·`<C-_>` 호환 유지. 새 플러그인 추가 없음 |
| CHG-03 필요한 LSP·formatter 호출 | Mason `PATH="skip"`. 선언된 도구 일부 또는 `php` 런타임을 당시 PATH에서 찾지 못함 | 실제 사용하는 언어의 기존 도구·런타임만 연결. 프로젝트 로컬·mise 우선순위를 보존하고 미설치 도구는 명시 | 선언과 실제 실행 경로 차이 축소. Mason PATH 전체 우선 삽입·도구 일괄 설치는 하지 않음. 필요한 언어 목록은 구현 전 확정 |
| CHG-04 PHP 5.3·레거시 인코딩 파일 저장 | PHP도 저장 포맷 대상. Markdown 외 공백 정리. PHP 5.3·인코딩별 보호 조건 없음 | 확인된 레거시 대상은 자동포맷·LSP 저장 fallback·공백 정리에서 제외. 수동 포맷은 기존 PHP 버전 명시·UTF-8 캐시 경로 사용 | 원치 않는 구문·바이트 변경 방지. 일반 UTF-8 파일의 기존 동작 유지. 인코딩 감지만으로 안전 판정하지 않음. 대상 프로젝트·경계 미확정이면 해당 구현 보류 |

#### 핵심 코드와 처리 차이

아래 AS-IS는 기준 판본의 실제 발췌다. TO-BE는 **설명용 구현 예정 예시**이며 저장된 제품 코드가 아니다.

**CHG-01** — [configs/lspconfig.lua](../nvim/lua/configs/lspconfig.lua)의 `kotlin_lsp` 설정은 서버 시작 시 아래 고정 경로를 넘긴다.

```lua
-- AS-IS 실제 코드
cmd = { vim.fn.stdpath "data" .. "/mason/bin/kotlin-lsp", "--stdio" },
-- TO-BE 예정 예시: 비어 있지 않을 때만 설정·enable
local kotlin_lsp = vim.fn.exepath("kotlin-lsp")
-- cmd = { kotlin_lsp, "--stdio" }
```

탐색 실패를 다른 Kotlin 서버로 자동 대체하지 않는다. 실행 파일을 찾는 것과 프로젝트에 연결되는 것은 서로 다른 완료 조건이다.

**CHG-02** — [mappings.lua](../nvim/lua/mappings.lua)의 일반 모드 호출부를 내장 동작으로 교체하고, 선택 영역도 같은 원칙을 적용할 예정이다.

```lua
-- AS-IS 실제 코드의 호출부
require("Comment.api").toggle.linewise.current()
-- TO-BE 예정 예시: 나머지 호환키·선택 모드도 같은 방식으로 연결
map("n", "<C-/>", "gcc", { remap = true, desc = "주석 토글" })
map("x", "<C-/>", "gc", { remap = true, desc = "선택 영역 주석" })
```

**CHG-03·04** — [configs/conform.lua](../nvim/lua/configs/conform.lua)의 `php = { "php_cs_fixer" }`, `format_on_save = { timeout_ms = 500, lsp_fallback = true }`와 [autocmds.lua](../nvim/lua/autocmds.lua)의 `if vim.bo.filetype == "markdown" then return end`가 현재 연결 지점이다. 예정 흐름은 `실제 언어·프로젝트 확인 → 레거시 저장 대상이면 자동 변경 제외 → 일반 대상만 선택한 formatter·런타임 실행`이다. 저장 포맷만 끄고 공백 정리나 수동 포맷으로 같은 보호를 우회하지 않도록 각 진입점을 함께 다룬다. 아직 확정하지 않은 레거시 판별 함수·실행 경로를 완성 코드처럼 제시하지 않는다.

#### 순서·검증 방법·미실행

| 단계 | 담당·산출물 | 선행 조건·다음 행동 |
|---|---|---|
| 계획 — 이번 범위 | 설정 담당: 이 절과 대화 본문의 전후 비교 | 메인에서 네 후보·필요 언어·레거시 경계를 검토. 계획 작성은 구현 승인으로 간주하지 않음 |
| 구현 — 아직 미착수 | 승인 후 설정 담당: 해당 Lua 파일만 최소 수정, 실제 diff·계획 대비 차이 기록 | 필요한 언어·프로젝트 범위 확정 후 CHG-01/02, CHG-03/04 순으로 진행 |
| 검증 — 아직 미실행 | 별도 요청 후 `[검증] → verify`: 변경 Lua 파일별 `luac -p <파일>` 및 합의한 실제 동작 확인 | 문법 통과와 실제 LSP·저장 성공을 구분. 새 테스트가 필요하면 시나리오 먼저 합의 |

구현 후 확인할 조건은 다음과 같다. **현재 네 항목 모두 미실행이며 통과 근거·새 테스트 소스·검증 로그는 없다.**

| 연결 | 예정 확인 방법·기대 결과 | 한계·중단 조건 |
|---|---|---|
| CHG-01 | 실제 Kotlin 프로젝트에서 LSP 연결·진단 확인. 실행 파일 미발견 조건에서는 해당 서버 미시작·이유 안내 | 문법 검사만으로 JDK·서버 호환성을 판정하지 않음 |
| CHG-02 | 일반 한 줄/선택 여러 줄의 주석·해제, 두 호환키의 실제 터미널 입력 확인 | 표시·주석 범위와 실제 입력 전달을 따로 확인 |
| CHG-03 | 필요한 언어별 실제 LSP/formatter 실행 경로와 버전 확인, 프로젝트 도구 우선·도구 없음 안내 확인 | 언어·런타임 미확정이면 설치·실행하지 않음 |
| CHG-04 | 승인된 복사 fixture에서 PHP 5.3·CP949/EUC-KR 저장 시 자동포맷·공백 정리 미호출과 원본 바이트 보존, 일반 UTF-8 저장 동작 보존 확인. 수동 포맷은 기존 버전·캐시 경로만 확인 | 실제 원본 파일을 시험 변경하지 않음. 대상 판별·기대 바이트·PHP 버전 미확정이면 보류 |

**완료 기준과 다음 행동:** 이번 산출물은 계획 v1의 본문 보고까지다. 제품 구현·테스트 작성·실행·배포·실행 반영은 모두 미착수다. 메인이 이 계획에서 적용할 후보와 필요한 언어·레거시 대상을 회수한 뒤 승인된 범위만 후속 구현한다. 부트스트랩·잠금파일·CSV/TSV·입력기·완성키·대시보드는 이 계획에 추가하지 않는다.

### #12 변경 기록 — 2026-11-23 · 구현 완료·동작 미검증

사용자가 계획 v1(`43411b1`) 구현을 승인했다. 아래는 그 판본 대비 실제 소스 변경이며 위 계획의 예정 동작·미착수 기록은 당시 내용으로 보존한다. 실제 비교는 `git diff 43411b1 -- nvim/lua`로 볼 수 있다.

| 변경 | 실제 AS-IS → TO-BE | 영향·확인 범위 |
|---|---|---|
| CHG-01 | Mason 고정 경로 → `vim.fn.exepath("kotlin-lsp")`. 있을 때만 `--stdio` 설정·enable, 없으면 경로 확인 명령 안내 | 다른 Kotlin 서버로 대체하지 않음. PATH 밖 설치는 미발견으로 안내. 실제 attach·JDK 호환성 미검증 |
| CHG-02 | `Comment.api` 네 호출 → 일반 `gcc`·선택 `gc`에 `remap=true`로 연결 | 추가 플러그인 없음. `<C-/>`·`<C-_>` 유지. 선택 모드는 `x`이며 실제 터미널 입력·선택 범위 미검증 |
| CHG-03 | `black`·`stylua`의 기본 명령 탐색 → PATH 실행 파일 우선, 없으면 해당 Mason 파일의 실행 가능 여부 확인 | 전체 PATH 변경·도구 설치 없음. Prettier·Intelephense 기존 연결 유지. HTML/CSS 서버·Lua 서버·PHP 런타임은 새로 연결하지 않음 |
| CHG-04 | 인코딩 구분 없는 저장 → `configs/save-policy.lua`의 버퍼 `fileencoding`이 CP949/EUC-KR이면 자동포맷·LSP 저장 fallback·공백 정리 생략 | 파일명·경로만으로 프로젝트 버전을 추정하지 않음. 일반 인코딩의 기존 저장 옵션 유지. `:Format`·`Space cf`·`Space fm`도 직접 포맷 거부·기존 PHP 5.3 캐시 명령 안내 |

핵심 코드는 CHG-01의 `if kotlin_lsp ~= ""`, CHG-02의 `map("n", "<C-/>", "gcc", { remap = true, ... })`, CHG-03의 `formatter_command`, CHG-04의 `is_legacy_encoding`이다. Conform 저장 콜백과 공백 정리 콜백이 같은 인코딩 판정을 쓰며, 저장 포맷은 옵션을 반환하지 않아 외부 formatter와 LSP fallback 모두 호출하지 않도록 했다. `Space fm`은 기존 동기 호출에서 보호된 `:Format`의 비동기 호출로 연결되므로 이 동작 차이도 실제 키 확인 대상이다. 다른 플러그인의 직접 LSP/Conform API 호출까지 전역 차단하는 기능은 아니다.

**계획 대비 제한·미확인:** 현재 설정의 언어 선언과 기존 Mason `black`·`stylua`, Homebrew Kotlin·Prettier·Intelephense 파일만 근거로 삼았다. 도구 파일 존재는 Python/Node/PHP 런타임 실행 성공을 뜻하지 않는다. PHP 5.3 포맷 설정 파일은 있으나 실제 프로젝트·버전과의 매핑은 확보하지 못했다. 따라서 **UTF-8로 열린 PHP 5.3 파일에는 이번 인코딩 보호가 적용되지 않는다.** 실제 프로젝트·버전·인코딩 근거를 확보한 뒤 해당 범위의 저장 정책을 보완해야 하며, 현재 구성을 레거시 전체 보호 완료로 보고하지 않는다. 인코딩 오감지·버퍼 수동 변경도 보호 범위 밖이다.

**구현·검증·반영:** 다섯 Lua 파일의 소스 구현 완료(새 파일 `configs/save-policy.lua` 포함). 이번 요청에 별도 동작 검사 승인은 없으므로 위 검증계획의 사례·`luac`·LSP·포맷·fixture 검사는 실행하지 않았다. 등록 자동검사의 결과만 별도로 취급하며, 기존 config 검사 실패 상한 3회는 유지한다. 기존 `~/.config/nvim/lua` 심링크를 쓰는 구성은 다음 로드에서 변경 소스를 읽으며 전체 설치는 필요 없다. 실행 중 Neovim의 실제 로드·키 동작·저장 반영은 미확인이고 재시작·강제 재로드하지 않았다.

**운영·다음 행동:** #12는 과거 다른 owner라 현재 대화의 공식 `show`가 권한 거부를 반환했다. owner·상태를 가장하거나 재배정하지 않고 실제 변경 결과를 메인에 반환한다. 메인에서 남은 PHP 프로젝트 경계와 필요한 도구 런타임을 회수하고, 별도 승인된 검사 범위만 후속 수행한다. #11 보류와 기존 queued 기록은 유지한다.

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
