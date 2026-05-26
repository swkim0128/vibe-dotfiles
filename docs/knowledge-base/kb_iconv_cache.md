# kb_iconv_cache

EUC-KR/CP949 ↔ UTF-8 인코딩 변환 캐싱 패턴.

## 현상
레거시 PHP/텍스트 파일 분석 시 매번 `iconv` 로 UTF-8 변환 → 분석 후 삭제 → 다음 작업에서 같은 파일 또 변환. 같은 변환을 반복 수행해 시간/디스크 I/O 낭비, 변환 직후 결과 재활용 기회 손실.

## 원인
- 변환 결과를 임시 파일로만 다루고 캐시 정책 부재
- "사용 후 삭제"가 안전한 관행으로 굳어져 동일 파일 재분석 시 재사용 불가
- 변환 명령(`iconv -f CP949 -t UTF-8 src > tgt`)이 항상 무조건 실행

## 해결 코드
`/Users/eunsol/Project/vibe-dotfiles/vibe-tools/smart_iconv.sh`

타임스탬프 기반 캐시 래퍼. TGT 가 없거나 SRC 가 더 새로울 때만 iconv 실행.

### 사용 예시
```bash
# 1) 기본 (CP949 -> UTF-8)
smart_iconv.sh ./original.php /tmp/converted/original.utf8.php

# 2) 명시적 인코딩
smart_iconv.sh ./legacy.txt /tmp/converted/legacy.utf8.txt EUC-KR UTF-8

# 3) 동일 인자 재실행 시 캐시 재사용
smart_iconv.sh ./original.php /tmp/converted/original.utf8.php
# => "기존 변환 파일을 재사용합니다: /tmp/converted/original.utf8.php"
```

## 향후 주의사항
**앞으로 파일 분석 작업을 할 때 변환된 인코딩 파일을 절대로 임의로 삭제하지 말고, 이 스크립트를 통해 캐시를 유지하며 작업할 것.**

- 변환 결과 보존 경로 패턴 (권장):
  - 프로젝트 외부: `/tmp/iconv-cache/<프로젝트명>/<상대경로>.utf8.<ext>`
  - 프로젝트 내부 분석 캐시: `.claude/cache/iconv/<상대경로>.utf8.<ext>` (gitignore 처리)
- `rm` 으로 변환 결과를 일괄 삭제하지 말 것. 디스크 압박 시 LRU 기반 cleanup 스크립트 별도 작성.
- 스크립트 호출 예시:
  ```bash
  smart_iconv.sh ./original.php /tmp/iconv-cache/myproj/original.utf8.php
  ```
- SRC 가 수정되면 자동 재변환되므로(`-nt` 비교) 캐시 stale 우려 없음. 강제 재변환이 필요하면 TGT 삭제 후 재실행.
- 변환 실패는 `set -e` 로 즉시 종료 — 부분 변환된 TGT 가 남으면 다음 실행에서 캐시 hit 위험. 실패 시 TGT 수동 삭제 권장.
