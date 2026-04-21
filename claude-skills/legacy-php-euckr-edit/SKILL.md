---
name: legacy-php-euckr-edit
description: Use before editing any .php/.inc/.phtml/.tpl file in Korean legacy projects — detects EUC-KR/CP949 encoding and preserves it through read/edit/write cycle via iconv. Triggers on "php 수정", "레거시 php", "php 파일 편집", "euc-kr", "cp949", "인코딩 유지", legacy PHP 코드 편집, 한국어 주석이 깨지는 PHP 수정. Claude 의 Edit/Write 도구는 UTF-8 로 저장하므로 EUC-KR 원본을 그대로 편집하면 한글이 손상된다.
---

# Legacy PHP EUC-KR 안전 편집

레거시 한국 PHP 프로젝트는 파일 인코딩이 `EUC-KR` (또는 `CP949`) 로 저장된 경우가 많다. Claude 의 `Edit` / `Write` 도구는 UTF-8 로 출력하므로, 그대로 편집하면 한글이 깨진다. 이 스킬은 **편집 전 인코딩을 감지**하고, 필요 시 `iconv` 로 변환하여 **원본 인코딩을 유지**한다.

## 적용 대상

- 확장자: `.php`, `.inc`, `.phtml`, `.tpl`
- 사용자가 "EUC-KR", "CP949", "레거시 한국 코드" 로 명시한 파일
- Git 저장소의 기존 PHP 파일이 EUC-KR 로 커밋돼 있는 프로젝트

## 실행 흐름

### 1. 인코딩 감지 (편집 전 필수)

```bash
file -I <file>
```

| 감지 결과 | 판단 |
|----------|------|
| `charset=utf-8` | UTF-8 → 일반 편집 (섹션 2) |
| `charset=us-ascii` | 한글 없는 ASCII → 일반 편집 (UTF-8/EUC-KR 둘 다 호환) |
| `charset=iso-8859-1` / `unknown-8bit` / 기타 | EUC-KR 후보 → 섹션 1-1 교차 검증 |

#### 1-1. Python 기반 교차 검증 (file 출력이 모호할 때)

```bash
python3 -c "
import sys
data = open(sys.argv[1], 'rb').read()
try:
    data.decode('utf-8', errors='strict'); print('utf-8')
except UnicodeDecodeError:
    try:
        data.decode('euc-kr', errors='strict'); print('euc-kr')
    except UnicodeDecodeError:
        print('unknown')
" <file>
```

- `utf-8` → 섹션 2
- `euc-kr` → 섹션 3
- `unknown` → **편집 중단**. 사용자에게 원본 인코딩 확인 요청.

### 2. UTF-8 경로 (일반 편집)

기본 `Read` / `Edit` / `Write` 도구로 바로 편집. 변환 불필요.

### 3. EUC-KR 경로 (변환 편집) — **핵심**

**절대 금지**:
- `Read` → `Edit` 직접 적용: Claude 에는 한글이 mojibake(깨진 바이트) 로 표시되어 문자열 매칭·치환이 모두 손상됨.
- `Write` 로 새 내용 저장: UTF-8 로 기록되어 원본 인코딩이 바뀜.

**허용 워크플로우** — UTF-8 사본 편집 후 EUC-KR 로 재인코딩:

```bash
FILE="<원본 경로>"
TMP="${FILE}.utf8.tmp"

# 3-1. UTF-8 사본 생성 (실패 시 중단 — 깨진 채로 진행 금지)
iconv -f EUC-KR -t UTF-8 "$FILE" > "$TMP" \
  || { echo "iconv 실패: 원본이 EUC-KR 이 아닐 수 있음 — 인코딩 재확인"; rm -f "$TMP"; exit 1; }
```

이후 Claude 의 `Read` / `Edit` 도구로 `$TMP` 파일을 편집한다 (원본 `$FILE` 에는 접근 금지).

편집 완료 후:

```bash
# 3-2. EUC-KR 로 재인코딩해 원본 덮어쓰기
#      '//TRANSLIT', '//IGNORE' 미사용: 매핑 불가능한 문자는 즉시 실패하는 편이 안전
iconv -f UTF-8 -t EUC-KR "$TMP" > "$FILE" \
  || { echo "재인코딩 실패 — EUC-KR 로 매핑 불가능한 문자(이모지/확장 한자 등) 포함"; exit 1; }

# 3-3. 임시 파일 정리
rm -f "$TMP"
```

### 4. 사후 검증

```bash
file -I "$FILE"                              # charset 이 변경 전후 동일해야 함
git diff --stat -- "$FILE"                   # 의도한 변경만 보여야 함
```

한글이 제대로 보존됐는지 빠른 확인:

```bash
iconv -f EUC-KR -t UTF-8 "$FILE" | grep -E "<수정한 한글 문자열>"
```

## 안전 가드

- **iconv 실패 시 편집 중단** — 깨진 파일을 원본에 덮어쓰지 않는다.
- **`//TRANSLIT` / `//IGNORE` 옵션 금지** — 문자 손실을 은폐하므로 매핑 실패를 그대로 드러내는 편이 안전.
- **임시 파일 정리** — `$TMP` 가 git 워크트리에 남아 커밋에 섞이지 않도록 반드시 `rm`.
- **신규 파일 생성** — 프로젝트 컨벤션이 EUC-KR 이면 새 `.php` 도 EUC-KR 로 저장 (`Write` 로 UTF-8 작성 → 즉시 섹션 3-2 재인코딩).
- **BOM 주입 금지** — iconv 자체는 BOM 을 추가하지 않지만, `sed` / `awk` 파이프로 우회 편집 시 실수 가능. 편집은 UTF-8 사본에서만.
- **대량 변환 금지** — 이 스킬은 "편집 대상 파일" 에만 적용. 프로젝트 전체 일괄 EUC-KR → UTF-8 변환은 별도 마이그레이션 태스크.
- **부분 실패 대비** — 섹션 3-2 가 실패해도 `$TMP` 는 유지 (수동 복구용). 에러 메시지에 `$TMP` 경로 명시.

## 예시

### 예시 1: EUC-KR 파일의 한글 주석 수정

```
사용자: legacy/bill/proc_order.php 의 "주문 처리" 주석을 "주문 생성" 으로 바꿔줘
스킬:
  - file -I proc_order.php → charset=unknown-8bit
  - python3 decode 검증 → euc-kr 확정
  - iconv -f EUC-KR -t UTF-8 proc_order.php > proc_order.php.utf8.tmp
  - Edit: proc_order.php.utf8.tmp 에서 "주문 처리" → "주문 생성"
  - iconv -f UTF-8 -t EUC-KR proc_order.php.utf8.tmp > proc_order.php
  - rm proc_order.php.utf8.tmp
  - 검증: file -I → unknown-8bit (원본과 동일)
          git diff --stat → 1 file changed
```

### 예시 2: UTF-8 파일은 그대로 편집

```
사용자: src/Order/Controller.php 에 validateOrder() 메서드 추가
스킬:
  - file -I Controller.php → charset=utf-8
  - 일반 Edit 도구 사용 (변환 불필요)
```

### 예시 3: 매핑 불가능한 문자로 실패

```
사용자: 이 EUC-KR PHP 파일에 "🎯 중요" 주석 추가해줘
스킬:
  - iconv -f UTF-8 -t EUC-KR 시도 → '🎯' 는 EUC-KR 에 없음 → 실패
  - 사용자에게 보고: "EUC-KR 에서 지원하지 않는 문자(🎯). 텍스트만 사용하거나 파일을 UTF-8 로 먼저 마이그레이션해야 합니다."
  - 원본 미수정
```

## 연관 스킬

- `backend:migrate` — 프로젝트 전체 EUC-KR → UTF-8 일괄 마이그레이션 시 사용
- `legacy:legacy-scan` — 레거시 코드 안티패턴 탐지 (PHP 구버전 함수 등)
