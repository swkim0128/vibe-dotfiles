---
name: notion-project-manager
description: 노션 프로젝트 관리 스킬. Projects/Tasks/Sprint 데이터베이스를 통해 프로젝트 생성, 상태 관리, 태스크 관리를 수행합니다. "프로젝트 만들어줘", "프로젝트 상태 변경", "태스크 추가", "스프린트 확인", "태스크 관리" 등의 요청 시 반드시 이 스킬을 사용하세요. 프로젝트, 작업, 스프린트가 언급될 때마다 적극적으로 발동합니다.
---

# 노션 프로젝트 관리

Projects, Tasks, Sprint 데이터베이스를 기반으로 프로젝트와 태스크를 관리하는 스킬입니다.

## 데이터베이스 정보

| DB | Collection URL | 용도 |
|----|---------------|------|
| Projects | `collection://96403fef-b550-4912-bd53-79b9fac19c99` | 프로젝트 목록 |
| Tasks | `collection://e07d34e3-3534-4ddf-95f8-cbdd2c312e43` | 개별 태스크 |
| Sprint | `collection://d1c2758f-9d07-439a-b891-172cb1471393` | 스프린트 |

## 속성 값 참조

### Projects 상태
| 값 | 의미 |
|----|------|
| Planning | 계획 중 |
| In progress | 진행 중 |
| Paused | 일시 중단 |
| Backlog | 백로그 |
| Done | 완료 |
| Canceled | 취소 |

**Priority**: 낮음 / 중간 / 높음 / 긴급

### Tasks 상태
| 값 | 의미 |
|----|------|
| Not started | 시작 전 |
| In progress | 진행 중 |
| Test | 테스트 중 |
| Done | 완료 |
| Cancel | 취소 |
| Archived | 보관 |

**Priority**: 낮음 / 중간 / 높음 / 긴급

### Sprint 상태
`Current` / `Next` / `Future` / `Last` / `Past`

---

## 기능별 처리 흐름

---

### 1. 프로젝트 생성

**트리거**: "프로젝트 만들어줘", "새 프로젝트 추가", "프로젝트 생성"

1. 사용자에게 필요한 정보 수집 (부족한 정보만 짧게 확인)
   - 프로젝트 이름 (필수)
   - 상태 (기본값: `Planning`)
   - Priority (기본값: `중간`)
   - 태그 (선택)

2. `notion-create-pages`로 Projects DB에 생성
   ```json
   {
     "parent": { "data_source_id": "96403fef-b550-4912-bd53-79b9fac19c99" },
     "pages": [{
       "properties": {
         "Name": "프로젝트 이름",
         "Status": "Planning",
         "Priority": "중간",
         "Tags": "[\"태그명\"]"
       }
     }]
   }
   ```

3. 태스크도 함께 추가할지 확인 후, 원하면 **태스크 추가** 흐름으로 이어서 처리

---

### 2. 프로젝트 상태 관리

**트리거**: "프로젝트 상태 변경", "프로젝트 완료했어", "프로젝트 일시 중단"

1. `notion-search`로 Projects DB에서 프로젝트 검색
2. 여러 결과가 나오면 사용자에게 선택 요청
3. `notion-update-page`로 Status 또는 Priority 업데이트

**상태 자동 추론 예시**:
- "완료했어" → `Done`
- "중단했어", "잠깐 멈춰" → `Paused`
- "다시 시작해" → `In progress`
- "취소할게" → `Canceled`

---

### 3. 태스크 추가

**트리거**: "태스크 추가", "할 일 추가", "작업 만들어줘"

1. 어느 프로젝트에 추가할지 확인 (명시 안 된 경우)
   - `notion-search`로 Projects DB에서 검색
2. 현재 스프린트 확인 (태스크를 스프린트에 연결할 경우)
   - `notion-search`로 Sprint DB에서 `Current` 스프린트 검색
3. `notion-create-pages`로 Tasks DB에 생성
   ```json
   {
     "parent": { "data_source_id": "e07d34e3-3534-4ddf-95f8-cbdd2c312e43" },
     "pages": [{
       "properties": {
         "Task name": "태스크 이름",
         "Status": "Not started",
         "Priority": "중간",
         "Project": "[\"프로젝트 URL\"]",
         "Sprint": "[\"스프린트 URL\"]"
       }
     }]
   }
   ```
   - Project, Sprint는 연결할 경우에만 포함
   - 스프린트 연결은 선택 사항 (사용자가 원하는 경우만)

---

### 4. 태스크 상태 관리

**트리거**: "태스크 완료", "태스크 상태 변경", "이거 Done으로 바꿔"

1. `notion-search`로 Tasks DB에서 태스크 검색
2. 여러 결과가 나오면 사용자에게 선택 요청
3. `notion-update-page`로 Status 업데이트

**상태 자동 추론**:
- "완료했어", "끝났어" → `Done`
- "취소할게" → `Cancel`
- "시작할게" → `In progress`
- "테스트 중" → `Test`

---

### 5. 프로젝트/태스크 조회

**트리거**: "프로젝트 목록 보여줘", "진행 중인 프로젝트", "이번 스프린트 태스크"

- `notion-search`로 Projects 또는 Tasks DB 검색
- 결과를 표로 요약하여 보여줌

**현재 스프린트 태스크 조회**:
1. Sprint DB에서 `Current` 상태 스프린트 검색
2. 스프린트 페이지 fetch → Tasks 관계 확인
3. 각 태스크 상태와 함께 표로 정리

---

## 결과 요약 형식

```
✅ 프로젝트 관리 완료

| 구분 | 내용 |
|------|------|
| 프로젝트 생성 | 프로젝트명 (Planning) |
| 태스크 추가 (+N) | 태스크1, 태스크2 |
| 상태 변경 | 프로젝트명 → Done |
```

---

## 에러 처리

| 상황 | 대응 |
|------|------|
| 프로젝트 검색 결과 없음 | "해당 프로젝트를 찾지 못했습니다. 이름을 다시 확인해 주세요." |
| 동일 이름 다수 | 목록으로 보여주고 사용자에게 선택 요청 |
| 현재 스프린트 없음 | 스프린트 연결 없이 태스크만 생성 |
| 필수 정보 누락 | 짧게 확인 후 진행 |
