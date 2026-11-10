# Herdr 화면 표시

`herdr/config.toml`과 표시 실행기는 공통 `herdr_config` 단계에서 `~/.config/herdr/`에 파일별 심링크로 배포한다. `herdr/runtime/`의 Rust 실행기를 `cargo build --locked --release`로 빌드한 뒤 `vibe-herdr`를 연결한다. Cargo는 공통 mise 설정의 Rust에서 제공한다. HUD adapter에는 Python 3.11 이상이 필요하다. 기존 Herdr 제어 셸에서 `herdr config check`, `herdr server reload-config`로 적용한다.

시스템 지표·Dock 알림·시각은 하단 상태 TUI에서 확인하고, AI pane 제목에는 경로·브랜치·모델·작업 제목을 보고한다. workspace·tab·pane 이름과 agent의 `working/blocked/done/idle/unknown` 상태는 sidebar에서 확인한다. workspace마다 반복되던 시스템 지표 행은 제거했으며 공용 sys_* metadata 갱신은 유지한다. `done`은 Herdr의 관측 상태이며 요청 큐의 완료 상태를 뜻하지 않는다.

- 시스템 지표와 HUD는 5초마다 갱신한다. `CPU~`는 `ps %cpu`의 프로세스 평균 합을 논리 CPU 수로 나눈 근삿값이며 순간 CPU 측정치와 다르다. RAM은 active+wired+compressor 페이지의 GiB, 배터리는 `pmset` 값을 표시한다.
- Dock은 기존 `~/.cache/vibe/dock-badges.raw`만 읽는다. 새 수집기를 시작하지 않는다. 30초가 지난 캐시는 `알림?오래됨`, 없거나 읽지 못하거나 빈 캐시는 `알림?`로 표시한다. 기존 수집기는 성공 표식이 없어 빈 결과를 0건으로 확정하지 않는다.
- CodexBar는 `vibe-herdr usage`를 명시적으로 실행할 때 공식 앱의 `Contents/Helpers/CodexBarCLI usage --provider codex --source cli`를 사용한다. 60초 캐시와 최대 8초 제한을 적용하며 중복 조회는 파일 잠금으로 막는다. 캐시는 표시 문자열과 시각만 저장한다. 조회 실패 시 최근 성공 값을 최대 5분 동안 `~나이s`와 함께 표시하고, 이후 `CB 오래됨`으로 바꾼다. 성공 이력이 없으면 미설치·시간초과·조회실패를 표시한다. `CODEXBAR_CLI`로 설치 경로를 지정할 수 있다. 5초 주기 명령에서는 조회하지 않는다.
- 긴 cwd와 뱃지는 셀 폭으로 줄이고 tmux 서식·제어 문자는 제거한다. 좁은 화면에서는 Herdr가 하단 우측 영역을 숨길 수 있으며 sidebar의 compact 상태 표시는 유지된다.

HUD는 공식 `agent_session`의 전체 native ID와 실제 전경 CLI PID, pane 셸의 프로세스 계보, 시작 시각, terminal ID와 socket inode를 확인한 뒤 읽는다. 제목·cwd·최근 대화로 연결을 추정하지 않는다. 현재 등록된 dashboard 훅 경로 또는 `VIBE_DASHBOARD_HUD_SCRIPT`에서 기존 HUD 모듈을 찾아 `configure(load())`와 기존 Docker 저장소 어댑터를 사용한다. 호스트의 과거 원장으로 우회하지 않는다. 60초가 지난 HUD는 미확인으로 처리한다.

`vibe-herdr status --sidebar-only`가 시스템 수집·workspace metadata·프로젝트 제목을 갱신한다. 활성 workspace의 AI pane에 native 대화 참조가 없으면 이미 읽은 pane 목록과 socket inode를 확인해 Rust에서 `HUD 미연결`을 보고한다. 참조가 있으면 HUD 저장소의 공식 API가 Python 모듈이므로 `hud.py`만 별도 프로세스로 최대 2초 호출한다. `VIBE_HERDR_HUD_ADAPTER`로 해당 adapter 경로를 지정할 수 있다. 주기 실행과 알림 전달은 Rust가 담당한다. 기존 `status.py`와 `plugins/top-alert/notify.py`는 호환·기존 검사 자료로 보존하며 설정과 플러그인은 실행하지 않는다.

표시 metadata는 의미 상태를 변경하지 않고 15초 후 만료된다. native ID가 없으면 `HUD 미연결`, 연결·PID·저장소 검증이 실패하면 `HUD 연결 미확인`을 표시한다. 실제 관측이 없는 서브·요청 수를 0으로 만들지 않는다. 대화 연결에는 하네스 저장소의 Herdr SessionStart 배포와 사용자 훅 신뢰가 필요하다. 기존 대화에 새 SessionStart가 없으면 연결 여부는 미확인으로 남는다.

검증: `cargo clippy --locked --manifest-path herdr/runtime/Cargo.toml -- -D warnings`, `python3 -B tests/test_herdr_display.py`. 기존 Python 검사는 HUD 검증 계약과 이관 전 동작을 확인한다. 실제 Rust 실행·설정 검사·reload는 Herdr 안의 기존 제어 셸에서 수행한다.

## 상단 중앙 알림

Hammerspoon과 로컬 Herdr 플러그인 `vibe.top-alert`로 완료·응답 필요 알림을 화면 상단 중앙에 표시한다. Herdr 본체는 수정하지 않으며 하단 전용 pane도 만들지 않는다. 기존 Herdr 팝업은 중복 표시를 막기 위해 `ui.toast.delivery = "off"`로 설정한다.

- 정적 정의: `hammerspoon/herdr-alert.json`의 위치·글꼴·색상·표시 시간과 `herdr/plugins/top-alert/herdr-plugin.toml`의 이벤트·명령 매핑.
- 실행: `vibe-herdr notify`가 `pane.agent_status_changed` 이벤트의 `done`·`blocked`만 Hammerspoon 로컬 IPC에 전달하고, `hammerspoon/herdr-alert.lua`가 canvas로 알림을 그린다. 이벤트 문자열은 Lua의 십진 byte escape로 전달하며 stdin을 닫고 5초 제한과 UUID 응답 검사를 적용한다. `hs`는 PATH 또는 사용자·공용 Applications에서 찾는다. 가로 중앙을 유지하고 메뉴 막대 아래 작업 영역에서 JSON의 `position.topMargin`(기본 16px)만큼 내려 표시한다. 완료는 초록 4초, 응답 필요는 노랑 8초다. 새 알림은 이전 알림을 대체한다.
- 표시 내용: 스페이스, pane ID, 에이전트, 보고된 작업 제목. 셸에서 문구를 실행하거나 에이전트 입력을 전송하지 않는다. `blocked`는 Herdr가 보고한 응답 필요 상태이며 질문·실행 승인 유형을 별도로 판독하지 않는다.
- 설치: `Brewfile`에 Hammerspoon을 선언하고 `hammerspoon_config` 단계로 `~/.hammerspoon/`에 파일별 링크를 만든다. `herdr_config`는 플러그인 경로를 등록한다. 첫 설치 후 Hammerspoon을 실행해 초기 질문에 답한다. 설정을 읽으면 로그인 시 자동 실행이 활성화된다. 기존 설정 파일은 설치기의 백업 규칙을 따른다.
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

하단 배치는 마지막 명령으로 열고 Herdr의 크기 조절로 3~8행을 확보한다. 설치기가 pane을 자동으로 만들거나 기존 화면을 재배치하지 않는다.
