# HANDOFF — Session Context Transfer

> 이전 세션 작업 컨텍스트. 새 세션(다른 PC 포함)에서 이 파일을 읽고 이어서 작업.
> (구 2026-07-07 핸드오프는 완료되어 대체됨.)

## Session Info
- Date: 2026-07-29
- Machine: 회사 PC → **개인 PC에서 이어서 작업 예정** (git pull 후 이 파일 확인)
- Repos: vibe-dotfiles (master 직접) / vibe-ai-config (이번 세션 변경 없음, clean·07-23 핸드오프 유효)
- Context: DWDEV-4996 워크스페이스에서 **Kotlin neovim 소스 추적 환경** 셋업 요청 → nvim 설정 보완
- 대상 프로젝트: shopping-danuri (순수 Kotlin 4312 파일, Java 0, 멀티모듈)

## What Succeeded (vibe-dotfiles master 커밋+push 완료, origin 동기화)
1. **Kotlin LSP 활성화** (`5784065`, `nvim/lua/configs/lspconfig.lua`)
   - 원인: mason에 JetBrains `kotlin-lsp` 바이너리는 설치돼 있었으나 lspconfig 활성 목록에서 누락 + mason-lspconfig 미설치라 기본 cmd(`intellij-server`)가 mason 바이너리명(`kotlin-lsp`)과 불일치.
   - 조치: `vim.lsp.config("kotlin_lsp", { cmd = { <mason>/bin/kotlin-lsp, "--stdio" } })` + `vim.lsp.enable "kotlin_lsp"`.
   - 검증(배선): cmd 해석·바이너리 실행 가능·root_markers(`settings.gradle.kts`)→shopping-danuri 루트 감지·nvim이 서버 spawn(rpc 통신 로그 확인) 모두 PASS.
2. **treesitter kotlin 파서** (`5784065`, `nvim/lua/plugins/init.lua`)
   - 주석 처리돼 있던 treesitter 스펙 활성화 + `ensure_installed`에 `kotlin` 추가 (NvChad 기본 파서 유지).
3. **`<leader>H` 커서 단어 노란색 표시 토글** (`ab475c6`, `nvim/lua/mappings.lua`)
   - kotlin-lsp가 `documentHighlightProvider` **미지원 확정**(`:lua vim.lsp.buf.document_highlight()` → "not supported")이라 LSP 비의존 `matchadd` 기반으로 구현.
   - bg `#FAE3B0`(catppuccin yellow), 창 로컬, 커서 이동해도 유지, 같은 단어 재입력 시 해제. `<leader>h`(NvChad 수평분할)와 충돌 피해 대문자 `H`.

## Current State
- vibe-dotfiles: **clean, master, origin 동기화 완료**(미push 0). nvim 변경은 auto-commit 훅으로 자동 커밋·푸시됨.
- vibe-ai-config: 이번 세션 변경 없음. 기존 handoff(2026-07-23) 유효.
- ⚠️ 회사 PC의 실행 중 nvim(pane %12)은 **재시작 전이라 이전 설정** — 아래 검증은 nvim 재기동 후 수행.

## Next Steps (개인 PC에서, nvim 재시작 후 검증)
1. **kotlin_lsp attach 확인** — `:LspInfo` 또는 `:lua =vim.lsp.get_clients()`에 `kotlin_lsp`. JetBrains 서버라 첫 실행 시 Gradle 인덱싱으로 수십 초~수 분 소요(정상). `:LspLog`에 error/exit 없으면 대기.
2. **treesitter kotlin** — 재시작 시 자동 컴파일. `.kt`에서 `:InspectTree`로 확인.
3. **`<leader>H`** — 커서 단어 노란색 표시·토글 실동작 확인.
4. **소스 사용처 확인 수단** (요청 맥락 정리):
   - 현재 파일 내 표시 → `<leader>H`(구현 완료).
   - 정의 이동 → `gd` / Ctrl+클릭. 참조 목록 → `grr`(→quickfix, `referencesProvider` 지원 시).
   - 콜 계층 트리 → 내장 `vim.lsp.buf.incoming_calls()`/`outgoing_calls()`(quickfix, `callHierarchyProvider` 지원 시. kotlin-lsp pre-alpha라 미지원 가능 — capability로 확인).
5. **(선택) 추가 보완 후보** — 아직 미설치:
   - IntelliJ식 사용처 **펼침 트리 UI**: `trouble.nvim`(가벼움) 또는 `lspsaga.nvim`.
   - 자동 하이라이트(커서 멈추면 자동): `vim-illuminate`(treesitter/regex 폴백 → kotlin-lsp 미지원과 무관하게 동작).
   - Java 프로젝트용: mason `jdtls` 설치돼 있으나 미활성(shopping-danuri는 Java 0이라 현재 불요).

## Key Files (vibe-dotfiles/)
- `nvim/lua/configs/lspconfig.lua` — LSP 서버 활성(html/cssls/intelephense/**kotlin_lsp**)
- `nvim/lua/plugins/init.lua` — 플러그인 스펙(treesitter kotlin 포함)
- `nvim/lua/mappings.lua` — 커스텀 키맵(Ctrl+클릭 정의이동, **`<leader>H`** 노란색 표시)
- (레퍼런스, 유지 중) `vibe-tools/`: `skill_audit_worker.sh`(22시), `notion_diary_worker.sh`(18시), `cmux-no-workspace.txt`/`cmux-lib.sh`/`cmux-proj.sh`, `overnight_worker.sh`(2시)
