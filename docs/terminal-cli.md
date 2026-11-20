# 일반 터미널과 AI 하네스의 경계

`vibe-terminal`은 dotfiles가 제공하는 일반 터미널 CLI다. 터미널 선택, 작업공간과 셸 탭 준비, 프로젝트 경로 목록을 소유한다. AI 지침·위임·큐·모델 실행·AI 용어 지도는 별도 하네스의 `vibe`가 소유한다. 두 설치기는 자기 소유 경로만 배포하며 상대 저장소의 소스를 링크하거나 읽지 않는다.

## 실행과 설치

소스에서 직접 호출할 수 있다.

```bash
bash <dotfiles>/vibe-tools/vibe-terminal.sh status
```

dotfiles 설치기는 `~/.local/bin/vibe-terminal`을 같은 진입점으로 연결한다. `~/.config/vibe-tools`는 dotfiles의 설정·실행 코드만 보관한다. 하네스는 별도 설치 경로를 사용한다. 소스 수정과 설치·실행 중 반영은 각각 확인해야 한다.

| 명령 | 동작·응답 |
|---|---|
| `vibe-terminal status` 또는 `settings` | 저장 선택·현재 문맥·도구 경로를 JSON으로 반환 |
| `vibe-terminal backend` | dotfiles가 소유한 일반 provider 정의를 JSON으로 반환 |
| `vibe-terminal use herdr\|tmux` | 필수 도구 확인 후 선택 파일을 갱신 |
| `vibe-terminal check` | 설정과 실행 파일 존재 확인. 창·서비스 변경 없음 |
| `vibe-terminal open` | Herdr 접속용 Ghostty 새 화면 준비 |
| `vibe-terminal project-path TARGET` | 실제 디렉터리 또는 등록 이름을 절대경로로 해석 |
| `vibe-terminal select-project` | 검색 경로 목록으로 fzf 선택. 취소는 빈 stdout·종료코드 0 |
| `vibe-terminal commands common\|main\|sub` | 해당 사용자 명령 목록 원문 반환 |
| `vibe-terminal start NAME PATH` | 작업공간 생성·재사용. AI는 자동 시작하지 않음 |
| `vibe-terminal peek PATH [run COMMAND]` | 별도 실행 셸 준비. run 응답은 제출 결과이며 명령 완료 증명이 아님 |
| `vibe-terminal fzf [--window]` | 프로젝트 선택. Herdr는 `--window`만 지원 |
| `vibe-terminal helper project\|issue ...` | dotfiles가 소유한 기존 cmux 런처 호출 |
| `vibe-terminal native OP --params JSON [--timeout N]` | 정의된 일반 provider 동작만 실행. AI agent 동작은 포함하지 않음 |

기존 `terminal status`처럼 앞에 `terminal`을 붙여도 동일하게 처리한다. 일반 진입점의 미지원 동작·설정 오류는 종료코드 2, cmux 런처의 기존 tmux 경로 재개는 내부 종료코드 10을 사용한다. 변경 명령 실패를 자동 재시도하지 않는다.

## 데이터와 선택 연동

- 선택 파일은 `vibe-tools/terminal-runtime.json`, 일반 provider 정의는 `vibe-tools/terminal-backends.json`이다. 실행 코드는 `vibe-tools/terminal_runtime.py`이며 새 계층을 거치지 않고 같은 위치의 정의를 읽는다.
- `VIBE_TERMINAL_CONFIG`, `VIBE_TOOLS_DIR`, `VIBE_RUNTIME_STATE_DIR`, `XDG_CONFIG_HOME`, `XDG_STATE_HOME`은 기존 경로 계약을 유지한다. 일반 provider 정의의 명시적 대체 경로는 `VIBE_TERMINAL_BACKENDS`다.
- 프로젝트 목록·터미널 선택은 dotfiles 데이터다. 목록에 하네스 저장소 경로를 등록하는 것은 열 대상 등록이며 코드 의존이 아니다.
- cmux 런처는 `vibe`가 있으면 `vibe terminal launch TOOL`로 AI를 시작하고, 없으면 설치된 `TOOL`을 직접 실행한다. Zsh의 `codex`도 같은 선택 연동을 사용한다.
- 개인 허브 최신화는 `vibe sync --hub-path PATH`와 `vibe sync --startup SESSION PATH`로 연결한다. 하네스가 없으면 일반 작업공간 준비만 수행한다.
- tmux의 AI 메뉴·스킬·치트시트·작업 종료는 `vibe menu`, `vibe skills`, `vibe cheatsheet`, `vibe done`을 호출한다. Herdr의 AI 용어 지도 팝업은 `vibe terminal map`을 호출한다.
- Rust·Python 버전 설치는 dotfiles의 `mise/config.toml`과 `install_mise_config`가 맡는다. 하네스는 준비된 도구를 사용해 자기 실행기를 빌드한다.

## 2026-11-20 반영 범위

일반 실행기와 공개 명령 연결을 소스에 분리했다. 설치·빌드·린트·테스트와 실제 Herdr/tmux 연동은 실행하지 않았다. 기존 하네스 테스트의 경로·설정 fixture는 새 공개 CLI 계약에 맞춰 별도로 조정해야 한다. 실행 중인 작업공간·대화는 중단하거나 재시작하지 않았다.
