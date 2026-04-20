---
name: tmux-session-manager
description: Use when creating, listing, or cleaning up tmux sessions for work tasks, or when the user says "세션 만들어줘", "세션 생성", "세션 정리", "세션 현황", "session create", "session cleanup"
---

# Tmux Session Manager

이슈별 tmux 세션의 생성, 현황 조회, 정리를 관리한다. `tmux-sessionizer.sh` 스크립트를 통해 세션을 생성한다.

## 세션 생성

**반드시 `tmux-sessionizer.sh`를 사용한다.** `tmux new-session` 직접 호출 금지.

```bash
~/.config/vibe-tools/tmux-sessionizer.sh --project <프로젝트경로> --task <세션명>
```

- `--project`: 프로젝트 절대 경로 (필수)
- `--task`: 세션에 붙일 이름 (선택 — 이슈ID, 작업명 등 자유 입력)
- 세션 이름 결과: `{프로젝트basename}_{task값}`

스크립트가 자동 처리하는 것:
- 윈도우 1 (`develop`): nvim 70% + claude 30%
- 윈도우 2 (`task명`): 작업용 zsh
- git: task명으로 브랜치 체크아웃 (원격 있으면 checkout, 없으면 origin/develop 기준 생성)
- git lock 파일 자동 제거
- CLI 모드: 세션 생성만, 현재 화면 전환 없음

### 프로젝트 경로 확인

경로를 모르면 기존 세션에서 확인:
```bash
tmux display-message -t {세션명} -p '#{pane_current_path}'
```

## 세션 현황 조회

```bash
# 전체 세션
tmux list-sessions -F '#{session_name}'

# 이슈 세션만 (언더스코어로 구분된 세션)
tmux list-sessions -F '#{session_name}' | grep '_'
```

현황 표시 형식:

| 세션 | 윈도우 | 상태 |
|------|--------|------|

## 세션 정리

1. 브랜치 머지 여부 확인 (필요 시)
2. `tmux kill-session -t {세션명}`

## Common Mistakes

| 실수 | 올바른 방법 |
|------|------------|
| `tmux new-session` 직접 호출 | `tmux-sessionizer.sh --project --task` 사용 |
| 브랜치명에 `feature/` 접두사 추가 | task 값 그대로 사용 (스크립트가 처리) |
| 프로젝트 경로 추측 | 기존 세션에서 `pane_current_path` 확인 |
| 세션 이름 임의 지정 | 사용자가 입력한 값을 그대로 --task에 전달 |
