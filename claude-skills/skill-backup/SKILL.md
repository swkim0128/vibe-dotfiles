---
name: skill-backup
description: "Claude 스킬을 생성하거나 업데이트한 후 반드시 백업을 수행합니다. 스킬 생성, 스킬 업데이트, 스킬 수정, 스킬 백업 요청 시 이 스킬을 사용하세요. skill-creator 스킬로 스킬을 만들거나 수정한 직후에도 자동으로 실행되어야 합니다."
---

# 스킬 백업 관리

## 경로 정보

- **스킬 활성 경로**: `~/.claude/skills/<skill-name>/SKILL.md`
- **백업 경로**: `/Users/eunsol/Project/para/02.Areas/Claude-Skills/<skill-name>/`

---

## 백업 규칙

`SKILL_날짜.md`는 항상 **업데이트 이전의 구버전**을 저장합니다.
`SKILL.md`는 항상 **현재 최신 버전**입니다.
백업 디렉토리의 스킬 파일은 Claude 또는 다른 AI CLI 툴에서 직접 적용 가능한 상태여야 합니다.

---

## 신규 스킬 백업 (처음 생성)

```bash
SKILL_NAME="<skill-name>"
BACKUP_DIR="/Users/eunsol/Project/para/02.Areas/Claude-Skills/${SKILL_NAME}"
SKILL_SRC="${HOME}/.claude/skills/${SKILL_NAME}/SKILL.md"

mkdir -p "${BACKUP_DIR}"
cp "${SKILL_SRC}" "${BACKUP_DIR}/SKILL.md"
echo "✅ 신규 백업 완료: ${BACKUP_DIR}/SKILL.md"
```

---

## 기존 스킬 업데이트 백업 (수정 시)

```bash
SKILL_NAME="<skill-name>"
BACKUP_DIR="/Users/eunsol/Project/para/02.Areas/Claude-Skills/${SKILL_NAME}"
SKILL_SRC="${HOME}/.claude/skills/${SKILL_NAME}/SKILL.md"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

# 1단계: 현재 백업의 구버전 보존 (업데이트 전에 먼저 실행)
if [ -f "${BACKUP_DIR}/SKILL.md" ]; then
  cp "${BACKUP_DIR}/SKILL.md" "${BACKUP_DIR}/SKILL_${TIMESTAMP}.md"
  echo "📦 구버전 보존: SKILL_${TIMESTAMP}.md"
fi

# 2단계: 최신 스킬로 교체
cp "${SKILL_SRC}" "${BACKUP_DIR}/SKILL.md"
echo "✅ 업데이트 완료: ${BACKUP_DIR}/SKILL.md"
```

---

## 복원 방법

```bash
# 최신 버전으로 복원
cp /Users/eunsol/Project/para/02.Areas/Claude-Skills/<skill>/SKILL.md \
   ~/.claude/skills/<skill>/SKILL.md

# 특정 이전 버전으로 복원
cp /Users/eunsol/Project/para/02.Areas/Claude-Skills/<skill>/SKILL_20260201_063854.md \
   ~/.claude/skills/<skill>/SKILL.md
```

---

## 전체 워크플로우

스킬 생성/수정 완료 후 아래 체크리스트를 따릅니다:

1. `~/.claude/skills/<skill-name>/SKILL.md` 작성 완료 확인
2. 백업 디렉토리 존재 여부 확인
   - 없으면 → **신규 백업** 실행
   - 있으면 → **업데이트 백업** 실행 (구버전 보존 후 교체)
3. `02.Areas/Claude-Skills/README.md`의 스킬 목록 업데이트

---

## README 스킬 목록 업데이트

`/Users/eunsol/Project/para/02.Areas/Claude-Skills/README.md`의 등록 스킬 목록에서
해당 스킬의 최신 백업 날짜를 업데이트합니다.
