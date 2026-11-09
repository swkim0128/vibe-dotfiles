# Herdr 화면 표시

`herdr/config.toml`과 표시 실행기는 공통 `herdr_config` 단계에서 `~/.config/herdr/`에 파일별 심링크로 배포한다. Python 3.11 이상이 필요하다. 기존 Herdr 제어 셸에서 `herdr config check`, `herdr server reload-config`로 적용한다.

하단에는 활성 pane ID, cwd의 마지막 경로, Git 브랜치와 변경 표시 `*`, 시스템 지표, Dock 알림, CodexBar 사용량, 호스트와 시각을 표시한다. workspace·tab·pane 이름과 agent의 `working/blocked/done/idle/unknown` 상태는 sidebar에서 확인한다. `done`은 Herdr의 관측 상태이며 요청 큐의 완료 상태를 뜻하지 않는다.

- 시스템 지표와 HUD는 5초마다 갱신한다. `CPU~`는 `ps %cpu`의 프로세스 평균 합을 논리 CPU 수로 나눈 근삿값이며 순간 CPU 측정치와 다르다. RAM은 active+wired+compressor 페이지의 GiB, 배터리는 `pmset` 값을 표시한다.
- Dock은 기존 `~/.cache/vibe/dock-badges.raw`만 읽는다. 새 수집기를 시작하지 않는다. 30초가 지난 캐시는 `알림?오래됨`, 없거나 읽지 못하거나 빈 캐시는 `알림?`로 표시한다. 기존 수집기는 성공 표식이 없어 빈 결과를 0건으로 확정하지 않는다.
- CodexBar는 공식 앱의 `Contents/Helpers/CodexBarCLI usage --provider codex --source cli`를 사용한다. 60초마다 최대 8초 조회하며 중복 조회는 파일 잠금으로 막는다. 캐시는 표시 문자열과 시각만 저장한다. 조회 실패 시 최근 성공 값을 최대 5분 동안 `~나이s`와 함께 표시하고, 이후 `CB 오래됨`으로 바꾼다. 성공 이력이 없으면 미설치·시간초과·조회실패를 표시한다. `CODEXBAR_CLI`로 설치 경로를 지정할 수 있다.
- 긴 cwd와 뱃지는 셀 폭으로 줄이고 tmux 서식·제어 문자는 제거한다. 좁은 화면에서는 Herdr가 하단 우측 영역을 숨길 수 있으며 sidebar의 compact 상태 표시는 유지된다.

HUD는 공식 `agent_session`의 전체 native ID와 실제 전경 CLI PID, pane 셸의 프로세스 계보, 시작 시각, terminal ID와 socket inode를 확인한 뒤 읽는다. 제목·cwd·최근 대화로 연결을 추정하지 않는다. 현재 등록된 dashboard 훅 경로 또는 `VIBE_DASHBOARD_HUD_SCRIPT`에서 기존 HUD 모듈을 찾아 `configure(load())`와 기존 Docker 저장소 어댑터를 사용한다. 호스트의 과거 원장으로 우회하지 않는다. 60초가 지난 HUD는 미확인으로 처리한다.

표시 metadata는 의미 상태를 변경하지 않고 15초 후 만료된다. native ID가 없으면 `HUD 미연결`, 연결·PID·저장소 검증이 실패하면 `HUD 연결 미확인`을 표시한다. 실제 관측이 없는 서브·요청 수를 0으로 만들지 않는다. 대화 연결에는 하네스 저장소의 Herdr SessionStart 배포와 사용자 훅 신뢰가 필요하다. 기존 대화에 새 SessionStart가 없으면 연결 여부는 미확인으로 남는다.

검증: `python3 -B tests/test_herdr_display.py`. 실제 설정 검사·reload는 Herdr 안의 기존 제어 셸에서 수행한다. macOS 알림·새 창·tmux 전환은 이 설정의 범위에 포함하지 않는다.
