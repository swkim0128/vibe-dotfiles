---
name: git-commit
description: Use when the user asks to commit staged git changes — generates a commit message following the project's convention and commits only after user approval. Triggers on "커밋해줘", "커밋 메시지 작성해줘", "커밋 메시지 생성", "이대로 커밋", "commit", "commit this". 우선순위는 `commit.template` → 최근 git log 컨벤션 → vibe-dotfiles 기본값. `git add` 와 `git push` 는 이 스킬 범위 밖 (수행 금지).
---

# Git Commit

Staged 상태의 변경사항에 대해 저장소 컨벤션에 맞는 커밋 메시지를 생성하고, 사용자 승인 후 `git commit` 을 실행한다.

## 범위

| 포함 | 제외 |
|------|------|
| staged diff 분석 · 메시지 생성 · 승인 후 커밋 | `git add` (사용자가 수동 스테이징) |
| 템플릿 감지 · 로그 기반 컨벤션 탐지 | `git push` (사용자가 별도 지시) |
| pre-commit hook 실행 (실패 시 중단) | `--amend` / `reset` / `force push` |

## 실행 흐름

### 0. 사전 체크

```bash
git diff --cached --stat
```

- 출력이 비어 있으면 → 중단. `"staged 파일이 없습니다. git add <파일> 후 다시 호출해주세요"` 안내 후 종료.
- 민감 파일 필터:
  ```bash
  git diff --cached --name-only | grep -E '\.(env|key|pem)$|credentials|secret'
  ```
  매칭되면 경고 후 사용자의 명시적 확답 전까지 보류.

### 1. 템플릿 감지 (우선순위 1)

```bash
TEMPLATE_PATH=$(git config --get commit.template)
```

- 설정됨 + 파일 존재 → **템플릿 모드** (섹션 2)
- 아니면 → **로그 기반 컨벤션 탐지** (섹션 3)

### 2. 템플릿 모드

1. 템플릿 파일을 읽는다. 주석 라인(`#` 시작)은 미리보기에서 제거.
2. 플레이스홀더 탐지:
   - `<[^>]+>` — `<type>`, `<subject>`, `<body>`, `<footer>`
   - `\[[A-Z]+-?\d*\]` — `[JIRA]`, `[PROJ-123]` 등 티켓 마커
3. **플레이스홀더가 0개인 경우** (주석만 있는 style-guide 템플릿) → 템플릿 모드를 중단하고 **섹션 3으로 폴백**. 단, 템플릿 주석에 명시된 허용 type 목록(`feat/fix/refactor/...`)이 있으면 섹션 3-1 prefix 탐지 시 허용 목록으로 사용.
4. 치환 규칙:

   | 플레이스홀더 | 치환 값 |
   |--------------|---------|
   | `<type>` | 섹션 3-1 prefix 탐지 결과 |
   | `<subject>` | diff 요약 ≤ 72자 (body 언어 따름) |
   | `<body>` | "- " bullet 본문 (무엇을·왜) |
   | `<footer>` | 섹션 3-3 footer 탐지 결과 |
   | `[TICKET]` / `[JIRA-XXX]` | 현재 브랜치명에서 `[A-Z]+-\d+` 추출, 실패 시 `<?>` 로 두고 사용자에게 값 요청 |

5. 템플릿의 **구조(섹션 순서·구분자·빈 줄) 유지**. 섹션 추가·삭제·순서 변경 금지.
6. 최종 메시지 → 섹션 4 승인 단계.

### 3. 로그 기반 컨벤션 탐지 (우선순위 2)

#### 3-1. Prefix

```bash
git log -30 --pretty=%s | awk -F: 'NF>1 {print $1}' | sort | uniq -c | sort -rn | head -1
```

- 최빈 prefix 가 `feat|fix|chore|refactor|docs|style|test|perf|build|ci|backup` 중 하나면 채택.
- 아니면 → fallback (3-4).

#### 3-2. Body 언어

최근 10개 커밋 본문에서 한글(`가-힣`) 문자 비율 > 30% → `ko`, 아니면 `en`.

#### 3-3. Footer

```bash
git log -10 --pretty=%B | grep -E '^Co-Authored-By:' | head -1
```

- 존재하면 가장 최근 footer 재사용 (`git log` 는 최신 → 과거 순이므로 `head -1` 이 최신). 아니면 footer 없이.

#### 3-4. Fallback (우선순위 3)

탐지 실패 시 vibe-dotfiles 기본값:

- Prefix: `feat`
- Body: 한국어 "- " bullet
- Footer: `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`

### 4. 사용자 승인

최종 메시지를 포맷해 제시:

```
아래 메시지로 커밋할까요?

---
<type>: <subject>

- <body bullet 1>
- <body bullet 2>

<footer>
---
```

- **승인** → 섹션 5 실행
- **수정 요청** → 요청 반영 후 재확인 (재확인 없이 바로 커밋 금지)
- **중단** → 커밋하지 않고 종료

### 5. 커밋 실행

```bash
git commit -m "$(cat <<'EOF'
<type>: <subject>

- <body bullet 1>
- <body bullet 2>

<footer>
EOF
)"
```

- pre-commit hook 실패 → 원인 보고 후 **중단**. 재시도·hook 우회 금지.
- 성공 시 `git log -1 --stat` 결과를 사용자에게 보여주고 종료.

## 안전 가드

- **`git add` 자동 실행 금지** — staged 된 것만 처리.
- **`git push` 자동 실행 금지** — push 는 사용자가 별도 지시.
- **`--no-verify` / `--amend` / `reset` / `force push` 금지** — 시스템 프롬프트의 Git Safety Protocol 과 일치.
- **민감 파일 staged 경고** — `.env`, `*.key`, `credentials*`, `secret*` 패턴 감지 시 사용자 확답 필수.
- **빈 커밋 금지** — staged 없으면 섹션 0 에서 중단.
- **수정 요청 시 반드시 재확인** — 수정본을 즉시 커밋하지 않고 재승인 필요.

## 사용 예시

### 예시 1: 템플릿 없음 (vibe-dotfiles)

```
사용자: 커밋해줘
스킬:
  - staged 확인 → 3 files changed
  - commit.template 없음 → 로그 탐지
  - prefix=feat (최빈), body=ko, Co-Authored-By 탐지됨
  - 미리보기:
      feat: git-commit 스킬 추가

      - staged diff 기반 메시지 생성 & 사용자 승인 후 커밋
      - commit.template → git log → 기본값 순으로 컨벤션 탐지

      Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
사용자: 좋아
스킬: git commit 실행 → git log -1 --stat 결과 표시
```

### 예시 2: 템플릿 있음 (회사 레포)

```
사용자: 커밋해줘
스킬:
  - commit.template=.gitmessage 발견
  - 템플릿: "[<type>] [PROJ-<?>] <subject>\n\n<body>"
  - 현재 브랜치: feature/PROJ-842-login → PROJ-842 추출
  - 치환 후 미리보기 제시
사용자: subject 를 "로그인 실패 로깅 추가" 로 바꿔줘
스킬: 수정본 제시 → 사용자 승인 → git commit
```
