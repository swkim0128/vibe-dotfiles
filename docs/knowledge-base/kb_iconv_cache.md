# kb_iconv_cache

EUC-KR/CP949 ↔ UTF-8 인코딩 변환 캐싱 패턴.

## 현상
레거시 PHP/텍스트 파일 분석 시 매번 `iconv` 로 UTF-8 변환 → 분석 후 삭제 → 다음 작업에서 같은 파일 또 변환. 같은 변환을 반복 수행해 시간/디스크 I/O 낭비, 변환 직후 결과 재활용 기회 손실.

## 원인
- 변환 결과를 임시 파일로만 다루고 캐시 정책 부재
- "사용 후 삭제"가 안전한 관행으로 굳어져 동일 파일 재분석 시 재사용 불가
- 변환 명령(`iconv -f CP949 -t UTF-8 src > tgt`)이 항상 무조건 실행

## 해결 코드 (2026-05-26 갱신 — 스킬로 일원화)

**진실 공급원**: `analyze:file-encoding-converter` 스킬
- 스크립트: `${CLAUDE_PLUGIN_ROOT}/skills/file-encoding-converter/scripts/check-encoding.sh`
- 캐시 경로 (고정): `/tmp/iconv-cache/<basename(SRC)>.<to_lower_nohyphen>`
- 오버라이드: `ICONV_CACHE_DIR=<dir>` 환경변수
- 보존 정책: 캐시 삭제 금지 — 다음 호출에서 재사용. SRC > 캐시 mtime 시 자동 재변환.

⚠️ **`vibe-tools/smart_iconv.sh` 는 2026-05-26 제거되었습니다.** 기능은 `analyze:file-encoding-converter` 스킬로 완전 이관. 과거 호출 형태(`smart_iconv.sh <SRC> <TGT> [FROM] [TO]`)는 더 이상 지원되지 않으므로 아래 스킬 경유 호출로 대체할 것.

### 사용 예시 (스킬 경유)
```bash
# 1) 기본 (자동 감지, → utf-8)
bash "${CLAUDE_PLUGIN_ROOT}/skills/file-encoding-converter/scripts/check-encoding.sh" \
  ./original.php --convert
# → /tmp/iconv-cache/original.php.utf8 생성/재사용

# 2) 명시적 인코딩
bash "${CLAUDE_PLUGIN_ROOT}/skills/file-encoding-converter/scripts/check-encoding.sh" \
  ./legacy.txt --convert --from euc-kr --to utf-8
# → /tmp/iconv-cache/legacy.txt.utf8 생성/재사용

# 3) 동일 인자 재실행 시 캐시 hit
# → "=== Cache hit: /tmp/iconv-cache/original.php.utf8 (재사용, 삭제 금지) ==="

# 4) 캐시 디렉토리 변경
ICONV_CACHE_DIR=~/.cache/iconv \
  bash "${CLAUDE_PLUGIN_ROOT}/skills/file-encoding-converter/scripts/check-encoding.sh" \
  ./original.php --convert
```

## 향후 주의사항
**파일 분석 작업 시 변환된 인코딩 파일을 절대로 임의 삭제하지 말 것. 스킬이 자동 캐싱.**

- 캐시 경로는 `<basename>` 기반이므로 다른 디렉토리에 동명 파일이 있으면 충돌. 충돌 시 SRC mtime 비교로 자동 재변환되지만, 충돌이 잦은 환경은 `ICONV_CACHE_DIR` 로 프로젝트별 분리.
- `rm` 으로 캐시 일괄 삭제 금지. 디스크 압박 시 LRU 기반 cleanup 스크립트 별도 작성.
- SRC 가 수정되면 자동 재변환 (`-nt` 비교). 강제 재변환은 해당 캐시 파일 1개만 삭제 후 재호출.
- 변환 실패 시 부분 산출물은 스크립트 내부에서 `rm` 처리 — 캐시 hit 위험 차단.
