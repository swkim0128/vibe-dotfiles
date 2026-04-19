---
name: claude-skills-backup
description: "클로드 스킬을 자동으로 백업하는 스킬입니다. /mnt/skills/user에 있는 모든 사용자 스킬을 타임스탬프와 함께 백업합니다."
---

# 클로드 스킬 백업 자동화

## 개요
사용자가 작성한 클로드 스킬들을 자동으로 백업하는 스킬입니다.

## 백업 경로
- 백업 위치: `/Users/eunsol/Project/para/02.Areas/Claude-Skills/`
- 디렉토리 형식: `[스킬명]_[YYYYMMDD_HHMMSS]`

## 백업 프로세스

### 1단계: 스킬 확인
```bash
view /mnt/skills/user
```

### 2단계: 타임스탬프 생성
```bash
date +%Y%m%d_%H%M%S
```

### 3단계: 백업 실행
각 스킬에 대해:
1. 백업 디렉토리 생성
2. 스킬 파일 읽기
3. 백업 디렉토리에 저장

## 사용 예시
```
사용자: "클로드 스킬 백업해줘"
→ 모든 스킬 백업 및 완료 메시지
```