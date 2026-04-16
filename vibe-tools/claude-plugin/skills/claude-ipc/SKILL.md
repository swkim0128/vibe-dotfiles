---
name: claude-ipc
description: tmux 멀티패널 환경에서 클로드 인스턴스 간 작업 위임 및 완료 보고(IPC)가 필요할 때 사용. "다른 패널에 위임", "패널 B에게 시켜줘", "IPC", "작업 위임" 키워드에 반응.
---

# Claude IPC — tmux 패널 간 작업 위임

## 도구 위치

| 스크립트 | 역할 |
|----------|------|
| `~/.config/vibe-tools/claude-delegate.sh` | 타겟 패널 클로드에게 작업 위임 + 콜백 지시 |
| `~/.config/vibe-tools/claude-callback.sh` | 작업 완료 후 지휘관 패널에 결과 보고 |

## 사용 방법

### 1. 패널 ID 확인

```bash
tmux list-panes -a -F '#{pane_id} #{session_name}:#{window_index}.#{pane_index} #{pane_current_command}'
```

### 2. 작업 위임 (패널 A → 패널 B)

```bash
~/.config/vibe-tools/claude-delegate.sh '%3' '작업 내용을 여기에 입력'
```

- 패널 B의 클로드에게 작업 내용과 함께 **완료 후 콜백 지시**가 자동으로 전송됩니다.

### 3. 작업 완료 보고 (패널 B → 패널 A)

패널 B의 클로드가 작업을 마치면 터미널에서 실행:

```bash
~/.config/vibe-tools/claude-callback.sh '%1' '작업 결과 요약'
```

패널 A에 다음 형식으로 보고가 도착합니다:

```
🔔 [main:1.2] 작업 완료 보고: 작업 결과 요약
```

## 주의사항

- 타겟 패널에 클로드가 실행 중이어야 합니다.
- 패널 ID(`%숫자`)는 tmux 세션이 재시작되면 바뀝니다.
- `세션명:창번호.패널번호` 형식(예: `main:1.2`)으로도 타겟 지정 가능합니다.
