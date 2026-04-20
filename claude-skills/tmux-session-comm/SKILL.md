---
name: tmux-session-comm
description: 여러 tmux 세션에서 실행 중인 Claude Code 인스턴스 간 메시지 송수신(위임/완료/진행/질문)이 필요할 때 사용. "세션 B에 알려줘", "다른 세션에 위임해줘", "para에 보고", "배포 세션에 물어봐", "k8s 세션에 알려줘", "shopping-danuri에 전달" 등 세션/패널 간 통신 의도가 조금이라도 보이면 즉시 발동. 또한 git commit, MR/PR 생성, 브랜치 전환, 빌드/테스트 완료 직후에도 관련 세션에 보고할지 사용자에게 제안하기 위해 반드시 이 스킬을 확인할 것.
---

# Tmux 세션 간 Claude Code 통신 (tmux-session-comm)

여러 tmux 세션에 각각 Claude Code가 띄워져 있는 상태에서, 세션 간 **작업 위임/완료 보고/진행 상황 공유/질문**을 일관된 포맷과 신뢰 가능한 전송 경로로 수행하기 위한 스킬.

기존 `vibe-tools` 스크립트(`vibe cast`, `claude-delegate.sh`, `claude-callback.sh`)를 최우선으로 재활용하고, 없을 때만 `tmux send-keys`로 폴백한다.

---

## 1. 언제 이 스킬을 쓰는가

명시적 요청 (즉시 발동):
- "세션 B에 알려줘", "다른 패널에 위임해줘", "para에 보고", "배포 세션에 물어봐"
- "k8s 매니페스트 세션에 알려줘", "ashop에 API 바꿨다고 전달"
- "이거 끝났다고 보고해줘"

암묵적 트리거 (먼저 **제안**하고 사용자 승인 후 발동 — 자동 송신 금지):
- `git commit` / `git push` 직후
- MR/PR 생성 직후
- 브랜치 생성·전환 직후 (특히 배포 연관 브랜치)
- 빌드·테스트 완료, 주요 구현 단계 완료
- 스키마/API 변경 감지 시

> 암묵적 트리거에서는 반드시 한 줄로 물어볼 것. 예:  
> *"배포 연관 세션 `shopping-danuri-k8s-manifest`에도 커밋 소식 전달할까요?"*

---

## 2. 메시지 프로토콜

### 2.1 유형 (4가지)

| 유형 | 이모지 | 용도 |
|------|:-----:|------|
| DELEGATE | 📋 | 작업 위임 + 콜백 요청 |
| DONE | ✅ | 완료 보고 |
| STATUS | 🔄 | 진행 상황 공유 (응답 불필요) |
| ASK | ❓ | 질문/확인 요청 |

### 2.2 포맷

```
[이모지] [FROM → TO] TYPE: 내용
```

- **FROM**: 현재 세션 이름 (또는 패널 라벨 `session:window.pane`)
- **TO**: 타겟 세션/패널 라벨
- **TYPE**: `DELEGATE | DONE | STATUS | ASK`
- **내용**: 한 줄 요약 우선, 필요하면 줄바꿈으로 본문 추가

### 2.3 예시

```
📋 [para → shopping-danuri-k8s-manifest] DELEGATE: manifest의 image tag를 v1.4.2로 올려줘
✅ [shopping-danuri-k8s-manifest → para] DONE: deployment.yaml 수정 및 PR #142 생성 완료
🔄 [BillingSeller-auth → para] STATUS: JWT 리프레시 구현 중 (테스트 작성 단계)
❓ [ashop → BillingMPAdmin] ASK: /api/v2/orders 응답 스키마에서 `taxIncluded` 필드 유지해도 되나요?
```

---

## 3. 통신 구조 (허브 + 직접)

- **`para`** 세션이 기본 허브. 대상이 명시되지 않거나 애매하면 `para`로 보낸다.
- 아래 **관련 프로젝트 쌍**은 허브를 거치지 않고 **직접** 통신해도 좋다. 의도가 명확해 허브에서 한 번 더 라우팅하는 비용이 낭비인 경우.

| 관계 | 목적 |
|------|------|
| `shopping-danuri` ↔ `shopping-danuri-k8s-manifest` | 코드 변경 → 매니페스트/배포 |
| `BillingSeller` / `BillingMPAdmin` ↔ `ashop` | API 계약 확인/변경 통지 |

> 위 표는 **예시**다. 세션 이름 매칭이 확실하지 않거나 관계가 애매하면 묻지 말고 `para`로 보낸다. 허브가 항상 안전한 선택지다.

대상 세션을 특정할 수 없을 때는 사용자에게 되묻는다:  
*"이 보고를 어디로 보낼까요? (기본값: `para`)"*

---

## 4. 전송 방법 선택 (우선순위)

전송 직전 `~/.config/vibe-tools/` 아래 스크립트 존재 여부를 빠르게 확인하고, **존재하는 가장 높은 우선순위**를 선택한다.

```bash
# 존재 확인은 한 번에
ls ~/.config/vibe-tools/vibe.sh ~/.config/vibe-tools/claude-delegate.sh ~/.config/vibe-tools/claude-callback.sh 2>/dev/null
```

### 4.1 선택 규칙

| 순위 | 도구 | 쓸 때 | 명령 |
|:---:|------|-------|------|
| 1 | `vibe cast` | STATUS/ASK/DONE 등 일반 세션 전달. **세션 이름**으로 타겟 가능 | `~/.config/vibe-tools/vibe.sh cast <session> "<포맷된 메시지>"` |
| 2 | `claude-delegate.sh` | **DELEGATE 전용.** 타겟 Claude에게 작업 위임 + 완료 시 콜백 자동 지시 삽입 | `~/.config/vibe-tools/claude-delegate.sh <pane_id|session:win.pane> "<포맷된 메시지>"` |
| 3 | `claude-callback.sh` | DELEGATE 받은 측이 **완료 보고(DONE)** 올릴 때 | `~/.config/vibe-tools/claude-callback.sh <caller_pane_id> "<포맷된 메시지>"` |
| 4 | `tmux send-keys` | 위 스크립트가 없는 환경의 폴백 | `tmux send-keys -t <target> "<포맷된 메시지>" Enter` |

### 4.2 결정 트리

```
메시지 유형은?
├─ DELEGATE → 2번 (claude-delegate.sh). 없으면 1번 또는 4번
├─ DONE (콜백 지시를 받은 상황) → 3번 (claude-callback.sh). 없으면 1번 또는 4번
├─ DONE/STATUS/ASK (자발적) → 1번 (vibe cast). 없으면 4번
└─ 어떤 스크립트도 없음 → 4번 (tmux send-keys 폴백)
```

### 4.3 타겟 식별

- **세션 이름 기준** (`vibe cast`, `send-keys -t <session>`): `tmux list-sessions -F '#{session_name}'`
- **패널 ID 기준** (`claude-delegate.sh`, `claude-callback.sh`): 
  ```bash
  tmux list-panes -a -F '#{pane_id} #{session_name}:#{window_index}.#{pane_index} #{pane_current_command}'
  ```
- **현재 패널 ID** (FROM 라벨/콜백 주소용): `tmux display-message -p '#{pane_id}'`
- **현재 세션 이름**: `tmux display-message -p '#{session_name}'`

### 4.4 주의

- `claude-delegate.sh`/`claude-callback.sh`는 자체 래퍼 접두어(`🔔 [sender] ...` 등)를 붙인다. 프로토콜 포맷(`[📋] [FROM → TO] DELEGATE: ...`)을 그대로 넘기면 래퍼 바깥에 노출되어 여전히 읽힌다 — 문제 없음.
- `vibe cast`는 호출자 패널 ID가 있으면 콜백 지시를 자동 삽입한다. 순수 STATUS 공유처럼 **응답이 필요 없으면** 메시지 본문에 `(응답 불필요)`를 명시해 혼선 방지.
- `tmux send-keys`로 폴백할 때 메시지에 작은따옴표가 들어가면 셸 이스케이프가 깨진다. 가능하면 큰따옴표로 감싸고, 본문의 큰따옴표는 `\"`로 이스케이프.

---

## 5. 실행 절차 (표준 플로우)

1. **의도 파악**: 유형(DELEGATE/DONE/STATUS/ASK)과 타겟(세션명 또는 패널) 확정
2. **타겟 확인**: 위 4.3 명령으로 존재 여부 확인, 없으면 사용자에게 후보 제시
3. **메시지 조립**: `[이모지] [FROM → TO] TYPE: 내용`
4. **전송 경로 선택**: 4.2 결정 트리
5. **실행 후 보고**: 어떤 경로로 누구에게 무엇을 보냈는지 한 줄로 요약

### 최소 예시 (DELEGATE)

```bash
FROM=$(tmux display-message -p '#{session_name}')
TARGET_PANE='%5'   # tmux list-panes -a 로 확인
MSG="📋 [${FROM} → shopping-danuri-k8s-manifest] DELEGATE: deployment.yaml의 image tag를 v1.4.2로 변경하고 커밋까지"
~/.config/vibe-tools/claude-delegate.sh "$TARGET_PANE" "$MSG"
```

### 최소 예시 (STATUS, 응답 불필요)

```bash
FROM=$(tmux display-message -p '#{session_name}')
MSG="🔄 [${FROM} → para] STATUS: 로그인 API 리팩터링 50% 진행 (응답 불필요)"
~/.config/vibe-tools/vibe.sh cast para "$MSG"
```

### 폴백 예시 (스크립트 없음)

```bash
FROM=$(tmux display-message -p '#{session_name}')
MSG="❓ [${FROM} → ashop] ASK: /api/v2/orders taxIncluded 필드 유지 여부 확인 부탁"
tmux send-keys -t ashop "$MSG" Enter
```

---

## 6. 자동 제안 템플릿

암묵적 트리거 감지 시 **한 줄로** 물어본다. 과도한 반복은 피로감을 주므로 같은 단계에서 두 번 제안하지 않는다.

- 커밋/푸시 후:  
  *"방금 커밋을 `para`에 STATUS로 보고할까요? (y/대상 지정)"*
- MR/PR 생성 후:  
  *"PR 링크를 `para`와 관련 배포 세션에 전달할까요?"*
- 배포 연관 브랜치 전환:  
  *"`shopping-danuri-k8s-manifest`에도 이 브랜치 소식을 알릴까요?"*
- 빌드/테스트 완료:  
  *"테스트 결과를 위임자 세션에 DONE으로 보고할까요?"*

사용자가 "아니"라고 하면 이 세션 동안은 같은 트리거로 다시 묻지 않는다.

---

## 7. 흔한 실수와 방지

- ❌ 프로토콜 헤더(`[emoji] [FROM → TO] TYPE:`) 생략 → 수신 측이 누구에게서 온 무슨 유형 메시지인지 판단 불가
- ❌ 스크립트 존재 확인 없이 `vibe cast` 호출 → `command not found` 가능. 4.1의 `ls`로 선확인
- ❌ DELEGATE를 보내면서 수신 측에 콜백 방법을 안 알려줌 → `claude-delegate.sh`가 자동 삽입하므로 **반드시 이 스크립트 사용** (송신 내용에 콜백 지시를 직접 쓰지 말 것, 중복됨)
- ❌ 대상 불명확한데 임의로 추측해 송신 → 반드시 되묻거나 `para`로 보낼 것
- ❌ 모든 커밋/테스트마다 자동 발송 → **제안만** 하고 사용자 승인 후 발송

---

## 8. 요약 참조표

| 상황 | 유형 | 권장 전송 |
|------|:---:|-----------|
| "세션 B에 이거 해줘" | 📋 DELEGATE | `claude-delegate.sh` |
| 위임받은 작업 완료 | ✅ DONE | `claude-callback.sh` (호출자 패널 ID로) |
| 자발적 완료 통지 | ✅ DONE | `vibe cast` |
| 진행 상황 공유 | 🔄 STATUS | `vibe cast` (+ "응답 불필요") |
| 질문/확인 | ❓ ASK | `vibe cast` |
| 스크립트 없음 | 어떤 유형이든 | `tmux send-keys` 폴백 |
