---
name: notion-weekly-schedule
description: "노션 '일지 및 회고' 데이터베이스에서 이번 주 일정 페이지를 찾아 조회하고, 사용자가 입력한 일정 내용을 해당 페이지의 적절한 위치에 추가합니다. 자연어 입력을 분석하여 날짜, 시간, 카테고리(WORK/LIFE)를 자동으로 판단하여 일정을 추가합니다. 주간 일정 추가, 일정 기록, 노션 다이어리 업데이트 요청 시 반드시 이 스킬을 사용하세요. '프로젝트 태스크를 일정에 추가', '이번 주 할 일 목록 업데이트', '진행 중인 프로젝트 일정 반영' 요청 시에도 이 스킬을 사용하세요."
---

# 노션 주간 일정 관리 스킬

## 데이터베이스 정보

- **데이터베이스 URL**: https://www.notion.so/aac8a84fa7c4416ab7c517f3ed6d7fca
- **Data Source ID**: `d4c94e28-6040-45f4-a4ae-69b74a6b26b4`

---

## 1단계: 주간 페이지 찾기

현재 날짜로 주차를 계산하여 검색합니다.

```json
{ "query": "week 10 2026", "query_type": "internal" }
```

검색 결과에서 **"일지"** 페이지만 선택 (식단 페이지 제외).
찾은 페이지를 반드시 `notion-fetch`로 조회하여 실제 구조를 확인한 후 편집하세요.

---

## 2단계: 실제 페이지 구조 이해 (중요)

페이지는 `<columns>` 레이아웃 기반이며, 슬롯은 백틱 인라인 코드 형식입니다.

```
## Week List
<columns>
  <column>
    ### `WORK` 이번 주 업무 목록
    **협력사**
    - [ ] 업무 항목
    **Billing**
    **Other**
  </column>
  <column>
    ### `LIFE` 이번 주 일상 목록
    **Sport**
    - [ ] 클라이밍
    **Housework**
    **Side Project**
    **Study**
    **Other**
  </column>
</columns>
---
## Week Things
<columns>
  <column>
    ### 월요일
    `LIFE1`
    `WORK1` 업무 내용
    `WORK2` 업무 내용
    `WORK3` 업무 내용
    `LIFE2`
    `LIFE3`
  </column>
  <column>
    ### 화요일
    `LIFE1`
    `WORK1`
    `WORK2`
    `WORK3`
    `LIFE2`
    `LIFE3`
  </column>
</columns>
...
<columns>
  <column>
    ### 일요일
    `LIFE1`
    `LIFE2`
    `LIFE3`
    `LIFE4`
    `LIFE5`
    `LIFE6`
  </column>
  <column>
    ### 블럭
    `BLOCK1` 06 - 09
    `BLOCK2` 09 - 12
    `BLOCK3` 12 - 15
    `BLOCK4` 15 - 18
    `BLOCK5` 18 - 21
    `BLOCK6` 21 - 24
  </column>
</columns>
---
<span color="blue">**Copyright ⓒ swkim0128**</span>
```

### 블럭 시간대 참고
| 슬롯 | 시간 |
|------|------|
| LIFE1 / BLOCK1 | 06 - 09 (이른 아침) |
| WORK1 / BLOCK2 | 09 - 12 (오전 업무) |
| WORK2 / BLOCK3 | 12 - 15 (점심 후) |
| WORK3 / BLOCK4 | 15 - 18 (오후 업무) |
| LIFE2 / BLOCK5 | 18 - 21 (저녁) |
| LIFE3 / BLOCK6 | 21 - 24 (밤) |

**주말(토·일)**: WORK 슬롯 없이 LIFE1~LIFE6만 존재.

---

## 3단계: 업데이트 방법 (핵심)

### 패턴 A: Week List LIFE 항목 추가

Week List의 **LIFE** 컬럼에 체크박스를 추가할 때는 `replace_content_range`를 사용합니다.
`**Sport**`는 LIFE 컬럼에만 존재하므로 고유한 시작점이 됩니다.

```json
{
  "page_id": "페이지-id",
  "command": "replace_content_range",
  "selection_with_ellipsis": "**Sport**...**Other**",
  "new_str": "**Sport**\n\t\t- [ ] 클라이밍\n\t\t**Housework**\n\t\t- [ ] 집안일\n\t\t**Side Project**\n\t\t**Study**\n\t\t- [ ] 스터디 모임\n\t\t**Other**\n\t\t- [ ] 카페 - 생각정리"
}
```

> **주의**: new_str 안의 들여쓰기는 탭(`\t\t`) 두 개를 사용합니다 (columns 내부 기준).

### 패턴 B: 요일 컬럼 슬롯 내용 수정

요일 컬럼 내부의 LIFE/WORK 슬롯을 수정할 때는 **해당 요일의 전체 컬럼 내용**을 교체합니다.
백틱 슬롯을 부분적으로 replace하면 다른 슬롯이 삭제될 위험이 있습니다.

**평일 (월~금) 예시 - 화요일 LIFE3에 "카페" 추가:**
```json
{
  "page_id": "페이지-id",
  "command": "replace_content_range",
  "selection_with_ellipsis": "### 화요일\n\t\t`LIFE1`...`LIFE3` \n",
  "new_str": "### 화요일\n\t\t`LIFE1` \n\t\t`WORK1` \n\t\t`WORK2` \n\t\t`WORK3` \n\t\t`LIFE2` \n\t\t`LIFE3` 카페 - 생각정리\n"
}
```

**주말 (토·일) 예시 - 일요일 LIFE3에 "클라이밍" 추가:**
```json
{
  "page_id": "페이지-id",
  "command": "replace_content_range",
  "selection_with_ellipsis": "### 일요일\n\t\t`LIFE1`...\n\t\t`LIFE6` \n",
  "new_str": "### 일요일\n\t\t`LIFE1` \n\t\t`LIFE2` \n\t\t`LIFE3` 클라이밍\n\t\t`LIFE4` 클라이밍\n\t\t`LIFE5` \n\t\t`LIFE6` \n"
}
```

> **핵심 원칙**: 요일 컬럼 슬롯 편집 시, fetch로 확인한 해당 요일의 **전체 슬롯 목록**을 new_str에 빠짐없이 포함하세요. 수정할 슬롯만 포함하고 나머지를 생략하면 다른 슬롯이 삭제됩니다.

### 패턴 C: 페이지 하단에 내용 추가 (회고 등)

마지막 컬럼 블록 뒤(Copyright 앞)에 내용을 삽입할 때:

```json
{
  "page_id": "페이지-id",
  "command": "insert_content_after",
  "selection_with_ellipsis": "`BLOCK6` 2...\n</columns>",
  "new_str": "\n\n## 추가할 내용"
}
```

---

## 4단계: 날짜·카테고리 판단

### 시간 → 슬롯 매핑
- 오전(06-09): LIFE1
- 오전(09-12): WORK1
- 점심·오후(12-15): WORK2
- 오후(15-18): WORK3
- 저녁(18-21): LIFE2
- 밤(21-24): LIFE3

### WORK vs LIFE 자동 분류
- **WORK**: 회의, 미팅, 업무, 작업, 배포, 코드리뷰 등
- **LIFE**: 운동, 스터디, 카페, 약속, 가족 행사, 개인 학습 등

### Week List 카테고리
- **Sport**: 클라이밍, 헬스, 러닝 등 운동
- **Housework**: 청소, 장보기 등 집안일
- **Side Project**: 개인 프로젝트
- **Study**: 스터디 모임, 강의 수강 등
- **Other**: 기타 개인 일정

---

## 5단계: 전체 워크플로우

1. 주차 계산 → Notion Search ("week XX 연도")
2. "일지" 페이지 선택 → notion-fetch로 내용 확인
3. 업데이트 대상 파악:
   - Week List 항목 추가 → **패턴 A**
   - 요일 슬롯 내용 기입 → **패턴 B** (전체 컬럼 교체)
   - 진행 중 프로젝트 태스크 반영 → **6단계** 수행
4. 업데이트 실행 (병렬 가능)
5. fetch로 결과 확인

---

## 6단계: 진행 중인 프로젝트 태스크 동기화 (선택)

**트리거**: 사용자가 "프로젝트 태스크도 추가해줘", "진행 중인 업무 반영해줘" 등을 요청하거나,
주간 일정 기록 시 WORK 항목이 없을 때 자동으로 제안합니다.

### 처리 흐름

```
1. Projects DB에서 "In progress" 프로젝트 조회
2. 각 프로젝트의 Tasks 목록 fetch
3. 미완료 태스크 필터링
4. Week List WORK 항목에 추가
```

### 1. 진행 중 프로젝트 조회

`notion-search`로 Projects DB(`collection://96403fef-b550-4912-bd53-79b9fac19c99`)에서 검색합니다.

```json
{ "query": "In progress", "data_source_id": "96403fef-b550-4912-bd53-79b9fac19c99" }
```

결과에서 Status가 `In progress`인 프로젝트만 선택합니다.

### 2. 프로젝트별 태스크 fetch

각 프로젝트 페이지를 `notion-fetch`하여 Tasks 관계 목록(URL 배열)을 가져옵니다.

### 3. 미완료 태스크 필터링

각 태스크 URL을 `notion-fetch`하여 아래 기준으로 필터링합니다.

| 상태 | 포함 여부 |
|------|----------|
| Not started | ✅ 포함 |
| In progress | ✅ 포함 |
| Test | ✅ 포함 |
| Done | ❌ 제외 |
| Cancel | ❌ 제외 |
| Archived | ❌ 제외 |

> 태스크가 많으면 병렬 fetch로 처리합니다.

### 4. Week List WORK 항목 업데이트

수집된 태스크를 **패턴 A**를 사용하여 Week List WORK 컬럼에 추가합니다.

- **협력사**: 외부 협력 관련 태스크
- **Other**: 그 외 프로젝트 태스크 (기본값)
- 프로젝트 이름을 볼드로 그룹 레이블로 표시합니다.

```
**Other**
- [ ] [프로젝트A] 태스크 이름1
- [ ] [프로젝트A] 태스크 이름2
- [ ] [프로젝트B] 태스크 이름3
```

기존 Week List에 항목이 이미 있으면 뒤에 append합니다 (덮어쓰지 않음).

### 주의사항

- 태스크가 10개 이상이면 Priority 기준으로 상위 항목만 추가하고, 나머지는 사용자에게 알립니다.
- 진행 중인 프로젝트가 없으면 "현재 진행 중인 프로젝트가 없습니다"라고 안내합니다.

---

## 에러 처리

| 상황 | 원인 | 해결 |
|------|------|------|
| Selection 매칭 실패 | fetch 이후 페이지가 변경됨 | 다시 fetch 후 재시도 |
| 슬롯 내용 사라짐 | 부분 replace로 다른 슬롯 삭제 | 해당 요일 전체 슬롯을 new_str에 포함 |
| 페이지 없음 | 해당 주차 미생성 | 새 페이지 생성 (Data Source ID 사용) |

### 새 페이지 생성 (페이지 없을 때)
```json
{
  "parent": { "data_source_id": "d4c94e28-6040-45f4-a4ae-69b74a6b26b4" },
  "pages": [{
    "properties": {
      "Title": "[week XX] @YYYY/MM/DD → YYYY/MM/DD 일지",
      "Year": "2026",
      "Quarter": "1 분기",
      "Tags": "[\"일상\"]"
    }
  }]
}
```
