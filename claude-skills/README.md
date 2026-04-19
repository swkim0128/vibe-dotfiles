# Claude Skills 백업 디렉토리

## 개요
이 디렉토리는 사용자가 작성한 클로드 스킬들의 백업을 저장합니다.

## 디렉토리 구조
```
Claude-Skills/
├── README.md              # 이 파일
├── backup-guide.md        # 백업 가이드
└── backups/               # 백업 파일들
    ├── notion-weekly-schedule/
    │   ├── SKILL.md                    # 최신 버전
    │   └── SKILL_20260201_063854.md    # 히스토리
    ├── notion-weekly-retrospective/
    │   ├── SKILL.md                    # 최신 버전
    │   ├── SKILL_20260125_082632.md    # 히스토리
    │   └── SKILL_20260125_091807.md    # 히스토리
    └── notion-weekly-schedule_20251219_145005/  # 레거시 백업
        └── SKILL.md
```

## 백업 명명 규칙
- 폴더: `[스킬명]/`
- 최신 버전: `SKILL.md`
- 히스토리: `SKILL_[YYYYMMDD_HHMMSS].md`

## 백업된 스킬 목록

| 스킬명 | 설명 | 등록 상태 | 최신 백업 |
|--------|------|----------|----------|
| notion-weekly-schedule | 주간 일정 관리 | ✅ 등록됨 | 2026-02-01 |
| notion-weekly-retrospective | 주간 회고 작성 | ⏸️ 미등록 | 2026-01-25 |

## 백업 방법
1. "클로드 스킬 백업해줘" 라고 요청
2. 현재 등록된 스킬을 백업 경로에 최신화

## 복원 방법
백업된 스킬을 복원하려면:
1. backups 디렉토리에서 원하는 스킬 선택
2. SKILL.md 내용 확인
3. 필요시 /mnt/skills/user/[skill-name]/SKILL.md로 복사

## 참고
- 정기적으로 백업하는 것을 권장합니다
- 스킬 변경 전후에 백업을 진행하세요
- SKILL.md가 최신 버전이며, 히스토리 파일은 참조용입니다

---
*마지막 업데이트: 2026-02-01*