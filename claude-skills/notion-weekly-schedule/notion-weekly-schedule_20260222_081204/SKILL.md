---
name: notion-weekly-schedule
description: "노션 '일지 및 회고' 데이터베이스에서 이번 주 일정 페이지를 찾아 조회하고, 사용자가 입력한 일정 내용을 해당 페이지의 적절한 위치에 추가합니다. 자연어 입력을 분석하여 날짜, 시간, 카테고리(WORK/LIFE)를 자동으로 판단하여 일정을 추가합니다."
---

# 노션 주간 일정 관리 스킬

## 개요

'일지 및 회고' 데이터베이스에서 주간 일정 페이지를 찾아 일정을 추가하는 스킬입니다.

일정 추가는 두 가지 방법을 사용합니다:
- **방법 A (우선)**: `notion-update-page`로 페이지 내용 직접 수정
- **방법 B (폴백)**: 방법 A가 실패하면 `notion-create-pages`로 하위 페이지를 만들어 일정 기록

방법 A가 `data` 파라미터 타입 에러로 실패하는 경우가 있으므로, 실패 시 즉시 방법 B로 전환하세요.

---

## 데이터베이스 정보

- **데이터베이스 이름**: 일지 및 회고
- **데이터베이스 URL**: https://www.notion.so/aac8a84fa7c4416ab7c517f3ed6d7fca
- **Data Source ID**: `d4c94e28-6040-45f4-a4ae-69b74a6b26b4`
- **페이지 명명 규칙**: `[week XX] @YYYY/MM/DD → YYYY/MM/DD 일지`
- **Quarter 매핑**: 1~3월 → 1 분기, 4~6월 → 2 분기, 7~9월 → 3 분기, 10~12월 → 4 분기

---

## 페이지 구조 이해

주간 일정 페이지는 두 영역으로 구성됩니다:

### Week List (상단 요약)
```
## Week List
<columns>
  <column>
    ### `WORK` 이번 주 업무 목록
    **협력사**
    **Billing**
    **Other**
  </column>
  <column>
    ### `LIFE` 이번 주 일상 목록
    **Sport**
    **Housework**
    **Side Project**
    **Study**
    **Other**
  </column>
</columns>
```

### Week Things (일별 시간 블럭)
```
<columns>
  <column>
    ### 월요일
    `LIFE1`
    `WORK1`
    `WORK2`
    `WORK3`
    `LIFE2`
    `LIFE3`
  </column>
  <column>
    ### 화요일
    ...
  </column>
</columns>
```

**시간 블럭 매핑** (각 슬롯은 3시간 단위):
| 블럭 | 시간대 | 평일 슬롯 | 주말 슬롯 |
|------|--------|----------|----------|
| BLOCK1 | 06 - 09 | LIFE1 | LIFE1 |
| BLOCK2 | 09 - 12 | WORK1 | LIFE2 |
| BLOCK3 | 12 - 15 | WORK2 | LIFE3 |
| BLOCK4 | 15 - 18 | WORK3 | LIFE4 |
| BLOCK5 | 18 - 21 | LIFE2 | LIFE5 |
| BLOCK6 | 21 - 24 | LIFE3 | LIFE6 |

종일 일정은 가장 적합한 슬롯 하나에 넣습니다 (평일 LIFE → LIFE2, 주말 LIFE → LIFE1).
시간 범위가 여러 블럭에 걸치면 해당 블럭들 모두에 기록합니다 (예: 14:00~18:00 → BLOCK3, BLOCK4).

---

## 워크플로우

### 1단계: 주간 일정 페이지 찾기

주차 번호를 계산하여 검색합니다.

```
notion-search:
  query: "week XX YYYY 일지"
  data_source_url: "collection://d4c94e28-6040-45f4-a4ae-69b74a6b26b4"
```

결과에서 연도와 주차가 일치하는 페이지를 선택합니다. 못 찾으면 3단계(페이지 생성)로 이동합니다.

### 2단계: 페이지 내용 조회

```
notion-fetch:
  id: "찾은-페이지-id"
```

현재 내용을 확인하여 어디에 일정을 넣을지 파악합니다.

### 3단계: 일정 추가

#### 방법 A: notion-update-page (우선 시도)

`insert_content_after` 또는 `replace_content_range` 커맨드로 해당 슬롯에 직접 일정을 추가합니다.

```json
{
  "page_id": "페이지-id",
  "command": "replace_content_range",
  "selection_with_ellipsis": "`LIFE2` ...",
  "new_str": "`LIFE2` 생일"
}
```

> **주의**: 이 도구가 `Invalid arguments: expected object, received string` 에러를 반환하면 방법 B로 즉시 전환하세요. 재시도해도 동일한 에러가 발생합니다.

#### 방법 B: notion-create-pages 하위 페이지 (폴백)

방법 A 실패 시 사용합니다. 주간 페이지 아래에 하위 페이지를 만들어 일정을 기록합니다.

```json
notion-create-pages:
  parent: { "page_id": "주간-페이지-id" }
  pages: [{
    "properties": { "title": "📅 일정 업데이트 (MM/DD)" },
    "content": "아래 내용을 메인 페이지에 반영해주세요.\n\n## 추가할 일정\n| 요일 | 슬롯 | 내용 | 카테고리 |\n|------|------|------|----------|\n| 금요일 | LIFE2 | 생일 | LIFE |\n| 토요일 | LIFE1 | 외할머니 생신 | LIFE |\n| 일요일 | LIFE3~4 | 클라이밍 14:00~18:00 | LIFE/Sport |\n\n## Week List 업데이트\n- **Sport**: 클라이밍\n- **Other**: 생일, 외할머니 생신"
  }]
```

하위 페이지를 만든 뒤 사용자에게 결과를 알려줍니다:
- 하위 페이지 URL 제공
- 메인 페이지 슬롯별로 어떤 내용을 넣어야 하는지 테이블로 안내
- 사용자가 나중에 수동으로 메인 페이지에 반영할 수 있도록

### 4단계: 주간 페이지가 없는 경우 새로 생성

```json
notion-create-pages:
  parent: { "data_source_id": "d4c94e28-6040-45f4-a4ae-69b74a6b26b4" }
  pages: [{
    "properties": {
      "Title": "[week XX] @YYYY/MM/DD → YYYY/MM/DD 일지",
      "Year": "YYYY",
      "Quarter": "X 분기",
      "Tags": "[\"일상\"]"
    },
    "content": "<전체 템플릿 내용 - 아래 템플릿 참고>"
  }]
```

---

## 페이지 생성 템플릿

새 주간 페이지를 만들 때 사용합니다. 날짜와 일정을 채워서 사용합니다.

```
## Week List
<columns>
	<column>
		### `WORK` 이번 주 업무 목록
		**협력사**
		**Billing**
		**Other**
	</column>
	<column>
		### `LIFE` 이번 주 일상 목록
		**Sport**
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
		`WORK1`
		`WORK2`
		`WORK3`
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
<columns>
	<column>
		### 수요일
		`LIFE1`
		`WORK1`
		`WORK2`
		`WORK3`
		`LIFE2`
		`LIFE3`
	</column>
	<column>
		### 목요일
		`LIFE1`
		`WORK1`
		`WORK2`
		`WORK3`
		`LIFE2`
		`LIFE3`
	</column>
</columns>
<columns>
	<column>
		### 금요일
		`LIFE1`
		`WORK1`
		`WORK2`
		`WORK3`
		`LIFE2`
		`LIFE3`
	</column>
	<column>
		### 토요일
		`LIFE1`
		`LIFE2`
		`LIFE3`
		`LIFE4`
		`LIFE5`
		`LIFE6`
	</column>
</columns>
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

---

## 카테고리 분류 기준

| 카테고리 | 키워드 |
|---------|--------|
| **WORK** | 회의, 미팅, 업무, 작업, 발표, 보고, 배포, 코드리뷰, 협력사, Billing |
| **LIFE/Sport** | 운동, 클라이밍, 헬스, 러닝, 수영 |
| **LIFE/Housework** | 집안일, 청소, 빨래, 장보기 |
| **LIFE/Study** | 공부, 스터디, 학습, 독서 |
| **LIFE/Side Project** | 사이드 프로젝트, 개인 개발 |
| **LIFE/Other** | 약속, 병원, 생일, 기념일, 카페, 여행 |

---

## 사용 예시

```
"오늘 오후 3시에 팀 미팅 추가해줘"
→ 오늘 요일 확인 → 해당 요일 WORK3(15-18시) 슬롯에 추가

"토요일에 클라이밍 14시~18시"
→ 토요일 LIFE3(12-15), LIFE4(15-18) 슬롯에 추가
→ Week List Sport에도 추가

"다음 주 일정 업데이트해줘" + 캘린더 연동
→ Google Calendar에서 다음 주 일정 조회
→ 각 일정을 요일/시간에 맞춰 배치
```
