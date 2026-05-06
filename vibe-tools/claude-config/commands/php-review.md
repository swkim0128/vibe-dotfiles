---
description: PHP 레거시 파일 커밋 전 코드 리뷰. legacy-suite:php-code-review 스킬의 6개 항목을 순서대로 검토합니다.
---

# /php-review

커밋 전 변경된 PHP 파일에 대해 `legacy-suite:php-code-review` 스킬을 실행합니다.

## 체크리스트

1. **Include 체인** — 호출 함수·클래스 정의 존재 여부, require_once 경로 확인
2. **CLI 스크립트 필수 설정** — include_path, DOCUMENT_ROOT 포함 여부
3. **exec() / shell_exec() 보안** — escapeshellarg() 적용 여부
4. **배치·비동기 파라미터** — action 필드 포함 여부
5. **EUC-KR 재변환** — 수정 후 원본 인코딩 복원 여부
6. **괄호·세미콜론** — 구문 균형 확인

## 실행 방법

```
/php-review
대상: <파일 경로 또는 git diff 범위>
```

6개 항목 모두 통과 시 커밋 진행. 이슈 발견 시 수정 후 재검토.
