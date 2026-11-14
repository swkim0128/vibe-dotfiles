# Herdr 화면 표시

`herdr/config.toml`과 표시 실행기는 공통 `herdr_config` 단계에서 `~/.config/herdr/`에 파일별 심링크로 배포한다. `herdr/runtime/`의 Rust 실행기를 `cargo build --locked --release`로 빌드한 뒤 `vibe-herdr`를 연결한다. Cargo는 공통 mise 설정의 Rust에서 제공한다. HUD adapter에는 Python 3.11 이상이 필요하다.

설치는 파일 배포 뒤 실행 중인 화면 반영까지 시도한다. 실제 `HERDR_SOCKET_PATH` 소켓과 `HERDR_TAB_ID`가 있는 Herdr 실행 셸에서 설치하면 해당 서버의 플러그인을 등록하고 `herdr server reload-config`, `~/.config/herdr/vibe-herdr bar ensure --current`를 순서대로 실행한다. 현재 탭의 기존 작업 프로세스·분할을 보존하며 하단 TUI를 만들거나 재사용한다. 문맥이 없으면 기본 세션을 선택하지 않고 후속 명령을 출력한다. 플러그인 등록·reload 실패 시 다음 반영은 보류하고, TUI 배치 실패는 파일 배포와 구분해 경고한다. 설치 종료가 모든 실행 중 화면의 반영 완료를 뜻하지는 않는다.

재사용한 TUI는 실행 중인 바이너리를 유지하므로 새 실행기 변경 반영은 미확인으로 보고한다. 공식 부모가 연결된 Codex pane에서 `~/.config/herdr/vibe-herdr bar ensure --current --parent-current --relaunch`로 명시 교체할 수 있다. 설치는 부모 대화를 추정하거나 AI CLI를 다시 실행하지 않는다. Herdr 본체 높이 패치도 자동 설치하지 않으며, 목표 높이를 지원하지 않으면 해당 TUI 배치는 미완료로 남는다.

시스템 지표·Dock 알림·시각은 하단 상태 TUI에서 확인하고, AI pane 제목에는 경로·브랜치·모델·작업 제목을 보고한다. workspace·tab·pane 이름과 agent의 `working/blocked/done/idle/unknown` 상태는 sidebar에서 확인한다. workspace마다 반복되던 시스템 지표 행은 제거했으며 공용 sys_* metadata 갱신은 유지한다. `done`은 Herdr의 관측 상태이며 요청 큐의 완료 상태를 뜻하지 않는다.

- 시스템 지표와 HUD는 5초마다 갱신한다. `CPU~`는 `ps %cpu`의 프로세스 평균 합을 논리 CPU 수로 나눈 근삿값이며 순간 CPU 측정치와 다르다. RAM은 active+wired+compressor 페이지의 GiB, 배터리는 `pmset` 값을 표시한다.
- Dock은 기존 5초 갱신에서 원샷 수집기를 필요할 때만 호출한다. Herdr 전용 캐시는 `~/.cache/vibe/herdr/`이며 같은 Herdr의 여러 TUI·상태 갱신은 잠금과 5초 TTL을 공유한다. 상주 수집기나 tmux 명령을 실행하지 않는다. 상태 JSON의 `ok`·수집 시각·마지막 성공 시각으로 성공한 빈 결과(`알림 0건`), 수집 실패, 미수집, 30초 이상 오래된 성공 값을 구분한다. 실패할 때 이전 성공 데이터를 보존하되 현재 성공처럼 표시하지 않는다.
- CodexBar는 `vibe-herdr usage`를 명시적으로 실행할 때 공식 앱의 `Contents/Helpers/CodexBarCLI usage --provider codex --source cli`를 사용한다. 60초 캐시와 최대 8초 제한을 적용하며 중복 조회는 파일 잠금으로 막는다. 캐시는 표시 문자열과 시각만 저장한다. 조회 실패 시 최근 성공 값을 최대 5분 동안 `~나이s`와 함께 표시하고, 이후 `CB 오래됨`으로 바꾼다. 성공 이력이 없으면 미설치·시간초과·조회실패를 표시한다. `CODEXBAR_CLI`로 설치 경로를 지정할 수 있다. 5초 주기 명령에서는 조회하지 않는다.
- 긴 cwd와 뱃지는 셀 폭으로 줄이고 tmux 서식·제어 문자는 제거한다. 좁은 화면에서는 Herdr가 하단 우측 영역을 숨길 수 있으며 sidebar의 compact 상태 표시는 유지된다.

HUD는 공식 `agent_session`의 전체 native ID와 실제 전경 CLI PID, pane 셸의 프로세스 계보, 시작 시각, terminal ID와 socket inode를 확인한 뒤 읽는다. 제목·cwd·최근 대화로 연결을 추정하지 않는다. 현재 등록된 dashboard 훅 경로 또는 `VIBE_DASHBOARD_HUD_SCRIPT`에서 기존 HUD 모듈을 찾아 `configure(load())`와 기존 Docker 저장소 어댑터를 사용한다. 호스트의 과거 원장으로 우회하지 않는다. 60초가 지난 HUD는 미확인으로 처리한다.

`vibe-herdr status --sidebar-only`가 시스템 수집·workspace metadata·프로젝트 제목을 갱신한다. 활성 workspace의 AI pane에 native 대화 참조가 없으면 이미 읽은 pane 목록과 socket inode를 확인해 Rust에서 `HUD 미연결`을 보고한다. 참조가 있으면 HUD 저장소의 공식 API가 Python 모듈이므로 `hud.py`만 별도 프로세스로 최대 2초 호출한다. `VIBE_HERDR_HUD_ADAPTER`로 해당 adapter 경로를 지정할 수 있다. 주기 실행과 알림 전달은 Rust가 담당한다. 기존 `status.py`와 `plugins/top-alert/notify.py`는 호환·기존 검사 자료로 보존하며 설정과 플러그인은 실행하지 않는다.

표시 metadata는 의미 상태를 변경하지 않고 15초 후 만료된다. native ID가 없으면 `HUD 미연결`, 연결·PID·저장소 검증이 실패하면 `HUD 연결 미확인`을 표시한다. 실제 관측이 없는 서브·요청 수를 0으로 만들지 않는다. 대화 연결에는 하네스 저장소의 Herdr SessionStart 배포와 사용자 훅 신뢰가 필요하다. 기존 대화에 새 SessionStart가 없으면 연결 여부는 미확인으로 남는다.

검증: `cargo clippy --locked --manifest-path herdr/runtime/Cargo.toml -- -D warnings`, `python3 -B tests/test_herdr_display.py`. 기존 Python 검사는 HUD 검증 계약과 이관 전 동작을 확인한다. 실제 Rust 실행·설정 검사·reload는 Herdr 안의 기존 제어 셸에서 수행한다.

## Yazi 팝업과 Helix 배경

`Ctrl+b` 또는 `Ctrl+Space`를 누른 뒤 `Tab`을 누르면 현재 작업 폴더에서 Yazi가 중앙 80% 크기의 팝업으로 열린다. 파일 탐색 화면에서 `q` 또는 `Esc`로 종료하면 원래 화면으로 돌아온다. 검색·이름 변경 등의 입력창에서 `Esc`는 기존 취소 동작을 유지한다. Herdr 내장 팝업을 사용하므로 탭 분할을 추가하지 않는다. 기본 `prefix+e`의 스크롤백 편집 기능은 유지한다. 팝업 정본은 `herdr/config.toml`이며 적용은 실행 중인 Herdr 셸에서 `herdr server reload-config`로 한다. Yazi 키맵 정본은 `yazi/keymap.toml`이며 `~/.config/yazi/keymap.toml`에 연결한다. 이 키맵은 일반 셸에서 실행한 Yazi에도 적용되며 다음 Yazi 실행부터 읽힌다. 사용자가 2026-11-14 새 단축키와 팝업 동작을 확인했다. 이후 추가한 `Esc` 종료는 실제 입력 미검증이다. [Herdr 공식 설정 안내](https://herdr.dev/tui/docs/configuration/#custom-command-keybindings) · [Yazi 공식 키맵 안내](https://yazi-rs.github.io/docs/configuration/keymap)

Helix 정본은 `helix/config.toml`과 `helix/themes/catppuccin_mocha_terminal.toml`이다. 공통 `helix_config` 단계가 두 파일을 `~/.config/helix/` 아래 같은 구조로 연결하고 기존 파일은 타임스탬프 백업으로 보존한다. 내장 Mocha를 상속하고 편집 영역의 글자색만 지정해 터미널 기본 배경을 사용한다. 메뉴·상태줄·선택 색상은 내장 테마를 따른다. Helix 25.07.1의 [테마 병합](https://github.com/helix-editor/helix/blob/25.07.1/helix-view/src/theme.rs#L125)과 [깊이별 교체](https://github.com/helix-editor/helix/blob/25.07.1/helix-loader/src/lib.rs#L175)에 따라 `ui.background` 항목 전체가 교체되므로 상속한 `bg`가 남지 않는다. 새 Helix 실행부터 적용되며 이미 열린 편집기는 사용자가 `:config-reload`로 반영할 수 있다.

## Dock 알림의 환경별 독립 실행

공통 원샷 `bin/dock-badges.sh`의 인자 없는 호출은 cmux가 쓰던 global 캐시 계약을 유지한다. `--slack`은 stdout만 반환하며 캐시를 바꾸지 않는다. tmux와 Herdr는 각각 `--backend tmux`, `--backend herdr`를 명시해 캐시·상태·잠금·PID 경로를 분리한다. 기본 cache root는 `~/.cache/vibe`이고 `VIBE_CACHE_DIR`로 바꿀 수 있다. 하위 경로·파일명·TTL·표시 문구·collector 설치 경로는 `vibe-tools/dock-badges.json`에 정의하며 Rust는 빌드에 포함한다. JSON 변경은 Rust 재빌드가 필요하다.

tmux는 `~/.cache/vibe/tmux/`에 기록하는 기존 poller를 사용하고 tmux 클라이언트에만 Slack 증가 알림을 전달한다. Herdr는 `~/.cache/vibe/herdr/`의 상태만 표시하며 tmux poller나 tmux 알림 전달에 의존하지 않는다. 한쪽의 종료·수집 실패·접근성 권한 문제는 다른 쪽의 캐시나 실행 상태를 덮지 않는다. 접근성 조회 자체는 같은 공통 스크립트를 사용하지만 호출한 환경의 권한으로 각각 수행한다.

설치 목록은 공통 collector와 tmux poller를 `~/.config/bin/`에 연결한다. JSON은 기존 `~/.config/vibe-tools` 디렉터리 링크에 포함된다. 2026-11-11에는 이 두 링크와 Rust release 빌드만 반영하고 현재 업무·개인 하단 TUI를 다시 열었다. 실제 Herdr 상태가 `ok:true`로 갱신돼 두 TUI에서 Slack·Notion 뱃지가 표시됐다. cmux의 설정·global 캐시는 변경하지 않았다. tmux 설정 정본은 교체했지만 실행 중인 tmux에 주입하거나 전체 설정을 reload하지 않았으며 다음 정상 tmux 로드부터 전용 poller·표시 경로를 사용한다.

## 상단 중앙 알림

Hammerspoon과 로컬 Herdr 플러그인 `vibe.top-alert`로 완료·응답 필요 알림을 화면 상단 중앙에 표시한다. Herdr 본체는 수정하지 않으며 하단 전용 pane도 만들지 않는다. 기존 Herdr 팝업은 중복 표시를 막기 위해 `ui.toast.delivery = "off"`로 설정한다.

- 정적 정의: `hammerspoon/herdr-alert.json`의 위치·글꼴·색상·표시 시간과 `herdr/plugins/top-alert/herdr-plugin.toml`의 이벤트·명령 매핑.
- 실행: `vibe-herdr notify`가 `pane.agent_status_changed` 이벤트의 `done`·`blocked`만 Hammerspoon 로컬 IPC에 전달하고, `hammerspoon/herdr-alert.lua`가 canvas로 알림을 그린다. 이벤트 문자열은 Lua의 십진 byte escape로 전달하며 stdin을 닫고 5초 제한과 UUID 응답 검사를 적용한다. `hs`는 PATH 또는 사용자·공용 Applications에서 찾는다. 가로 중앙을 유지하고 메뉴 막대 아래 작업 영역에서 JSON의 `position.topMargin`(기본 16px)만큼 내려 표시한다. 완료는 초록 4초, 응답 필요는 노랑 8초다. 새 알림은 이전 알림을 대체한다.
- 표시 내용: 스페이스, pane ID, 에이전트, 보고된 작업 제목. 셸에서 문구를 실행하거나 에이전트 입력을 전송하지 않는다. `blocked`는 Herdr가 보고한 응답 필요 상태이며 질문·실행 승인 유형을 별도로 판독하지 않는다.
- 카드 구성은 Herdr 기본 toast의 중립 테두리와 상태 표시·보조 본문을 따른다. 글씨 13pt·여백 8px·테두리 1px로 줄이고 `● 상태`만 상태색으로 표시한다. 본문은 중립색·왼쪽 정렬이며 최대 너비 520px 안에서 한 줄로 줄인다. 상단 여백 16px와 기존 표시 시간은 유지한다. 2026-11-11 Herdr 알림 모듈만 다시 로드해 반영했고 로컬 미리보기를 한 번 호출했다. 별도 화면 캡처나 육안 품질 확인은 하지 않았다.
- 설치: `Brewfile`에 Hammerspoon을 선언하고 `hammerspoon_config` 단계로 `~/.hammerspoon/`에 파일별 링크를 만든다. `herdr_config`는 현재 Herdr 문맥이 있을 때 플러그인 경로를 등록한다. 첫 설치 후 Hammerspoon을 실행해 초기 질문에 답한다. 설정을 읽으면 로그인 시 자동 실행이 활성화된다. 기존 설정 파일은 설치기의 백업 규칙을 따른다. 설치기는 파일 배포와 실행 중 반영을 구분하고 Hammerspoon 실행·메뉴 Reload Config 안내를 출력한다. 기존 자동 재로드 수단이 없어 실행 중 반영은 미확인으로 남긴다.
- 설정 변경: JSON 또는 Lua 변경 후 Hammerspoon 메뉴의 Reload Config를 사용한다. 수동 시험은 `herdr plugin action invoke test --plugin vibe.top-alert`, 실행 결과는 `herdr plugin log list --plugin vibe.top-alert`로 확인한다. Hammerspoon이 종료되거나 IPC 설정 로드에 실패하면 알림은 전달되지 않으며 실패가 플러그인 로그에 남는다.

이 연결은 Herdr 알림을 새로 생성한다. Slack 등 다른 앱의 기존 macOS 알림 위치를 옮기지 않는다. 외부 서비스로 데이터를 보내거나 제3자 알림 플러그인을 내려받지 않는다. 공식 동작 근거: [hs.canvas](https://www.hammerspoon.org/docs/hs.canvas.html), [hs.ipc](https://www.hammerspoon.org/docs/hs.ipc.html), [Herdr 플러그인](https://herdr.dev/tui/docs/plugins/).

## 상태 TUI와 팝업 비교

같은 플러그인의 `tui`와 `popup`은 `vibe-herdr view`를 실행한다. 주기 명령과 같은 시스템·Dock 수집 함수를 사용하며, 5초마다 실제 값을 갱신하고 q 또는 Esc로 닫을 때까지 유지한다. 8행 이하 pane에서는 CPU·RAM·배터리와 날짜·시각을 마지막 줄에 함께 표시하고, 알림을 그 바로 위에 붙여 두 줄 전체를 하단 정렬한다. 날짜·시각은 줄 끝에 보존한다. 1행이면 지표·시각 행만 남기며 폭이 좁아지면 지표부터 줄이고 시각의 뒷부분을 우선 보존한다. 마지막 줄에는 줄바꿈을 출력하지 않아 화면이 밀리지 않는다. 크기 변경은 이미 수집한 값으로 즉시 다시 그리며 추가 수집하지 않는다. 높은 TUI·팝업의 기존 배치는 유지한다. 두 배치·팝업 크기(68×16)는 플러그인 manifest에, 색상과 compact 행 순서·하단 정렬은 빌드에 포함하는 `herdr/runtime/view.json`에 분리했다. 정의를 변경하면 실행기를 다시 빌드한다.

Herdr 안의 실행 셸에서 다음 명령으로 연다. TUI의 workspace는 현재 대상 ID를 지정하고 팝업은 활성 pane을 기준으로 연다.

```bash
herdr plugin pane open --plugin vibe.top-alert --entrypoint tui --workspace <workspace-id> --focus
herdr plugin pane open --plugin vibe.top-alert --entrypoint popup --focus
herdr plugin pane open --plugin vibe.top-alert --entrypoint tui --placement split --target-pane <pane-id> --direction down --no-focus
```

위 명령은 수동 비교용이다. 설치 시에는 현재 Herdr 탭 문맥이 있을 때 기존 `bar ensure --current`로 하단 배치를 보장한다. 문맥이 없으면 실행할 후속 명령만 안내한다.

compact에서도 `view.json`의 개별 색을 적용해 CPU는 파랑, RAM은 보라, BAT는 초록으로 표시한다. 문구 길이를 먼저 제한한 뒤 색을 입혀 좁은 화면에서도 제어 코드가 잘리지 않게 한다. 기본 Herdr v0.9.5의 비율 상한 0.9에서는 전체 81행 중 하단이 외곽 8행·내부 6행으로 제한됐다. 2026-11-11 세밀한 비율 지원 패치가 반영된 서버에서 업무·개인 첫 탭의 하단을 각각 비율 0.9382716·외곽 5행·내부 3행으로 적용했다. 전체 폭과 작업 분할·Codex 프로세스를 보존했고 실제 터미널 버퍼도 공백 없이 내용 3행을 반환했다. 사용자 클라이언트의 실제 화면 연결과 API 기하 확인은 구분한다.

## 하단 상태 위치 고정

하단 알림은 Dock 수집 원본의 모든 앱과 개수를 표시한다. 한 줄 폭을 넘으면 `↔`가 나타나며, 상태 TUI에 포커스를 둔 채 좌우 방향키로 전체 내용을 읽을 수 있다. Home 키는 처음으로 돌아간다. 알림 이동은 지표·시각과 부모 대화 연결에 영향을 주지 않는다.

Herdr의 Codex pane에서 `prefix+i` 또는 `prefix+ㅑ`를 누르면 하단 상태 TUI 하나를 만들거나 재사용하고 전체 폭·목표 외곽 5행으로 맞춘다. 서브에이전트·알림·지표와 시각을 위한 내용 3행과 테두리 2행을 확보한다. 단축키는 기존 플러그인의 `bar` action에 `--parent-current`를 전달한다. 이 높이에는 세밀한 분할 비율을 지원하는 Herdr가 필요하다. 지원하지 않는 서버에서는 목표 높이 미적용을 오류로 보고하며 비율 0.9를 적용 성공으로 간주하지 않는다.

```bash
~/.config/herdr/vibe-herdr bar ensure --current
~/.config/herdr/vibe-herdr bar ensure --current --parent-current
~/.config/herdr/vibe-herdr bar ensure --tab <tab-id>
```

`--current`는 플러그인 또는 Herdr 셸의 실제 탭 문맥이 필요하다. 문맥이 없는 셸에서는 탭 ID를 명시한다. 위치를 다시 맞출 때 같은 명령을 사용한다. 설치 시 현재 탭에 한 번 적용하며 상주 감시는 하지 않는다.

상태 TUI는 실제 실행 파일 경로와 `view` argv로 확인한다. 올바른 전체 폭 하단 배치는 작업 pane 수와 무관하게 재사용한다. 새 배치·위치 복원은 작업 pane 1~2개인 탭에서 지원하며, 임시 탭으로 프로세스를 보존해 이동한 뒤 원래 작업 분할의 방향·비율을 복원한다. terminal ID와 셸·Codex/Claude PID를 확인하고 기존 작업 pane을 닫거나 다시 실행하지 않는다. 동시 실행은 세션별 파일 잠금으로 막는다. 상태 TUI가 여러 개거나 확대된 탭·지원하지 않는 분할이면 변경 전에 중단한다. 실패 시 현재 pane 확인과 재실행 명령을 출력하고, 임시 이동한 pane이 남으면 먼저 원래 탭으로 복귀하는 구체적인 명령을 안내한다.

내용 행 수·테두리 행 수·작업 pane 최소 행 수·허용 비율과 플러그인 entrypoint·위치 정의는 빌드에 포함되는 `herdr/runtime/bar.json`에 둔다. 실행기는 실제 탭 높이에서 목표 비율을 계산하고 적용 후 외곽 행 수와 전체 폭을 다시 확인한다. 작은 화면은 기존 작업 분할의 비율까지 고려해 최소 높이를 보존할 수 없으면 변경 전에 중단한다. 허용 비율을 벗어나는 화면도 자동 보정으로 성공 처리하지 않는다. 키 문법은 [공식 플러그인 문서](https://herdr.dev/tui/docs/plugins/#keybindings)를 따른다. 설치 후 플러그인 등록과 설정 reload를 적용하면 사용할 수 있다.

세밀한 비율 지원 패치는 `herdr/patches/status-height.patch`에 보존한다. 기준은 Herdr `v0.9.5`·commit `2ecf19a`이며 `src/layout.rs`의 두 비율 정규화 경로를 0.01~0.99로 맞춘다. 해당 기준 소스와 다른 변경을 보존하는 별도 checkout에서 패치 적용 가능 여부를 확인한 뒤 사용한다. 이 파일의 보관이나 dotfiles 설치는 Herdr 본체 빌드·배포를 수행하지 않으며 실제 서버 반영과 별개다. 다른 버전이나 다른 컴퓨터에는 해당 서버의 소스·빌드·프로세스 보존 배포 절차가 필요하다. 설치기의 자동 다운로드·자동 본체 빌드는 추가하지 않는다.

현재 통합 후보에 함께 적용된 Shift+Y 들여쓰기 제거 변경도 `herdr/patches/copy-dedent.patch`에 5개 파일의 diff 원문으로 보존한다. 높이 패치와 적용 범위가 겹치지 않으며 기준 버전·별도 본체 반영 조건은 [패치 안내](../herdr/patches/README.md)를 따른다.

## 이 TUI에서만 부모 대화의 서브에이전트 보기

서브에이전트 행은 부모 Codex pane을 명시한 TUI에서만 켠다. 부모 대화 ID는 Herdr의 공식 `agent_session`에서 읽으며 cwd·제목·포커스·최근 대화로 추정하거나 직접 입력하지 않는다. 같은 탭의 다른 Codex와 다른 workspace의 서브에이전트는 합치지 않는다.

```bash
~/.config/herdr/vibe-herdr bar ensure --tab <tab-id> --parent-pane <parent-codex-pane-id>
~/.config/herdr/vibe-herdr bar ensure --tab <tab-id> --parent-pane <parent-codex-pane-id> --relaunch
~/.config/herdr/vibe-herdr view --parent-pane <parent-codex-pane-id>
```

첫 명령은 새 하단 TUI를 만들 때만 연결한다. 기존 TUI가 있으면 `scope_requires_relaunch`를 반환하고 그대로 보존한다. 명시한 `--relaunch`는 기존 전체 폭 하단을 대상으로만 교체한다. 먼저 기존 TUI에서 목표 높이 지원을 확인하고 그 아래 새 TUI를 만든다. 새 실행·scope·작업 분할과 프로세스를 확인한 뒤 기존 TUI 하나만 닫아 분할을 합친다. 기존 작업 pane을 이동하거나 다시 만들지 않아 여러 작업 pane이 있는 탭에서도 사용할 수 있다. 기존 TUI를 닫기 전 검증이 실패하면 기존 TUI는 유지하고 식별 가능한 새 TUI만 정리한다.

`--parent-current`는 단축키의 `HERDR_PLUGIN_CONTEXT_JSON.pane_id` 또는 셸의 `HERDR_PANE_ID`에 명시된 호출 pane만 부모로 선택한다. 두 값이 함께 있고 다르면 중단한다. 공식 Codex 참조가 없는 셸에서 호출하면 Codex pane에서 같은 단축키를 사용할 것을 안내하며 다른 pane을 추정하지 않는다. 기존 scope가 현재 공식 부모·TUI·PID·terminal·socket과 정확히 같을 때만 기존 ensure 경로로 재사용한다. scope가 없거나 다르면 `scope_requires_relaunch`를 유지하며 자동 재연결·교체하지 않는다. 명시 `--parent-pane`의 재연결 계약과 부모 옵션 없는 명령의 기존 동작은 유지한다.

`view` 명령은 Herdr가 제공하는 해당 pane 문맥 안에서 실행하며, `HERDR_PANE_ID` 또는 `HERDR_PLUGIN_CONTEXT_JSON.pane_id`가 없으면 연결 미확인으로 남는다. Herdr 서버 handoff로 socket 세대가 바뀌면 이전 scope는 무효이므로 공식 부모 참조를 확인한 뒤 `--relaunch`로 명시적으로 다시 연결한다.

API 주소는 `--api-url <URL>` > `VIBE_SUBAGENTS_API_URL` > 기존 등록 producer 경로에서 불러온 `config.load()['port']` 순으로 정한다. 설정만 읽으며 legacy HUD 모듈이나 저장소의 `configure()`는 호출하지 않는다. 마지막 경로는 `VIBE_DASHBOARD_CONFIG`·`VIBE_DASHBOARD_PORT`와 기존 설정 파일을 따른다. 주소는 loopback HTTP만 허용하며 proxy·redirect를 사용하지 않는다. 저장소 API 주소 `storage.endpoint`를 dashboard API로 사용하지 않는다. adapter의 Python은 `view.json`의 `python_relative_path`로 기존 mise shim을 사용한다. GUI가 물려준 시스템 Python 3.9에는 설정 로드에 필요한 `tomllib`이 없어 조회가 실패하므로 로그인 셸의 PATH에 의존하지 않는다.

새 bar에는 socket 옆 `*.vibe-subagents-<socket-inode>-<pane-id>.json` 파일을 `0600`·덮어쓰기 금지로 만든다. 파일에는 대상 TUI와 부모 pane·terminal·PID·부모 프로세스 시작 시각·공식 session 참조를 고정하며 토큰·요청 원문을 넣지 않는다. TUI는 본인 pane·프로세스에 해당하는 파일만 읽고, socket 세대나 어느 식별자라도 바뀌면 연결을 거부한다. 정상적인 q/Esc 종료 시 본인이 읽은 파일을 지운다. 강제 종료 뒤 파일이 남아도 다른 TUI PID나 새 socket에는 재사용하지 않는다. 남은 파일을 자동 청소하거나 다른 TUI에 배포하지 않는다.

공식 session이 없으면 `서브 부모 대화 미연결`, API 오류·읽기 실패이면 `서브 조회 실패`, scope가 달라지면 `서브 연결 불일치`로 구분한다. 정확한 전체 부모 ID를 받는 `/api/subagents.json?session_id=…&internal=1`의 scope와 개별 항목을 대조하며, 실패 시 전역 조회나 과거 HUD 원장으로 돌아가지 않는다. 부모 CLI의 계보·PID·시작 시각과 TUI terminal·socket을 조회 전후 다시 확인한다. 연결 뒤 다른 대화로 자동 재결합하지 않는다. 공식 session 참조가 나중에 생겼거나 실행 프로세스가 바뀌었다면 명시적으로 다시 열어야 한다. 새 pane의 TUI 프로세스가 아직 준비되지 않았을 때도 scope 설치를 중단하며 자동 재시도하지 않는다.

현재 관측은 공식 Codex app-server에서 loaded 부모의 직접 자식을 전부 조회한 응답을 사용한다. `kind=codex-app-server`, `complete=true`, `parent_loaded=true`와 coverage를 확인하고 실제 조회 시각 `observed_at`으로 신선도를 판정한다. native `active`만 실행 관측, `idle`은 유휴, `notLoaded`는 미적재로 표시하며 완료로 추정하지 않는다. 이 완전한 현재 관측에서만 `서브 실행 0`을 확정한다. 과거 lifecycle 목록이 비어 있는 것은 `서브 현재 관측 없음`으로 표시한다. 마지막 lifecycle 이벤트가 오래됐다는 이유만으로 장기 실행 목록을 숨기지 않는다.

표시는 `서브 실행 관측 N · 역할#짧은ID` 한 줄이다. 공식 이름이 있으면 우선하고, 그렇지 않으면 역할과 ID 뒤 8자를 사용해 같은 UUID 앞부분을 가진 담당도 구별한다. 작업 설명의 FIFO 연결로 이름을 추정하거나 요청 본문을 표시하지 않는다. HTTP 2초·adapter 3초 상한과 관측 TTL은 `view.json`에 둔다. scoped receipt `*.observation.json`은 단계·예외 종류·Python 실행 정보만 `0600`으로 기록하며 응답 본문·프롬프트·토큰은 기록하지 않는다. 정상적인 q/Esc 종료 시 본인 receipt도 지운다.

compact 화면에는 남는 높이가 있을 때만 알림 바로 위에 한 줄을 추가한다. 기존 알림과 지표·시각을 우선 보존하며 pane 높이·분할 비율을 늘리지 않는다. 위치·색·최대표시 수·TTL은 `herdr/runtime/view.json`의 `subagents`에 둔다. 이 정보는 TUI에서만 사용하며 전역 status metadata로 보내지 않는다.

2026-11-11 개인 대화는 해당 thread가 출력한 일회성 commentary 표식과 실제 pane 출력·PID·시작 시각·계보를 대조해 연결했다. 업무 대화는 사용자의 명시 지정 매핑과 기존 peer의 확정 쌍·현재 PID/계보·동일 공식 daemon의 정확한 loaded 참조를 대조한 연결이다. 업무 표식을 직접 관측했다는 뜻은 아니다. 두 부모 모두 다른 공식 참조가 없음을 확인한 뒤 정상 `pane.report_agent_session`을 사용했으며 가짜 SessionStart나 현재 Codex 재시작은 하지 않았다.

현재 두 하단에서 실제 관측을 확인했다. 개인은 `서브 실행 관측 1 · worker#e09c9b9c`, 업무는 `서브 실행 0 · 유휴 3 · 미적재 17`을 표시했다. 외곽 5행·Dock 독립 수집·부모 Codex 프로세스는 보존했다. 기존 실행파일·adapter 심링크로 필요한 release 빌드와 해당 bar 재실행만 반영했으며 테스트·린트·전체 설치·전체 회귀 검사는 수행하지 않았다.
