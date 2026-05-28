# kb_buyer_log

buyer(빌링) 운영 로그 수집·분석 방법. billing1~4 분산 로그를 sftp로 일괄 수집하고, 무이자할부 카드사목록 조회(이니시스 getcardlist) 장애를 분석한다. (출처: para 세션 buyer 장애 조사 2026-05-28)

## 현상
- buyer(빌링) 운영 로그가 **billing1~4 4대에 분산** 저장되어, 장애 조사 시 4대를 각각 뒤져야 함.
- 일별 로그 경로: `/home/danawa/DanawaBilling/buyer/logs/log-YYYY-MM-DD.php` (UTF-8, CodeIgniter `ERROR - ...` 라인).
- 계기: 2026-05-28 무이자할부 카드사목록 조회(이니시스 getcardlist) 장애 조사.

## 원인
- 로그가 4대(billing1~4)에 분산 → 단일 수집 수단 부재.
- `lftp` 는 현재 환경에서 접속 불가 → `sftp` 사용 필요. (구버전 수집기 `~/.bin/ci_buyer.sh` 가 lftp 기반)
- 무이자 할부 카드사목록 조회 장애 자체의 원인: `OrderFormController.php` 의
  `simplexml_load_file('http://relay.inicis.com/relay/getcardlist.jsp?mid=...')` 가
  이니시스가 **비-XML 응답**을 반환할 때 `parser error : Start tag expected, '<' not found` 로 실패.

## 해결 코드
**수집 스크립트** (현재 위치 `~/.bin/buyerlog.sh`, 버전관리 미적용 — 아래 주의사항 참조):
```bash
# billing1~4 일괄 수집 → /tmp/buyer-billing1~4.log
~/.bin/buyerlog.sh [YYYY-MM-DD] [출력dir]   # 날짜 기본=오늘, 출력 기본=/tmp
# 비번: 공통 접두사 1회 입력 → 서버별 접미사 billing1~4 자동 부착(expect). 자격증명 미저장.
```

**단건 sftp** (스크립트 없이):
```bash
sftp danawa@billingN.danawa.com:/home/danawa/DanawaBilling/buyer/logs/log-YYYY-MM-DD.php /tmp/buyer-billingN.log
```

**tp4 미러로 단일 세션 수집** (비번 1회):
- `buyer-t.danawa.com`(user `danawa`)에 4대 로그가 `/Billing_Log_Storage/svm_billing1~4/` 로 미러됨
- → tp4 한 세션만 접속해도 4대 로그 전부 수집 가능.

**분석 grep 예**:
```bash
grep -ainE 'inicis|getcardlist|simplexml|실패' /tmp/buyer-billing*.log
```

## 향후 주의사항
- **운영 비번은 대화형 입력 → 사용자가 직접 실행.** 자격증명 저장 / SSH 키 등록 / keychain 셋업 **금지**. (스크립트도 비번을 메모리에서만 사용하고 `unset` 처리)
- `lftp` 대신 `sftp` 사용 (현재 환경 lftp 접속 불가). 다수 서버 비번은 expect로 자동화하되 **접두사 값 자체를 파일/스크립트에 하드코딩 금지**.
- **버전관리 검토 결과**: `~/.bin` 은 git 레포가 아니어서 `buyerlog.sh` 는 현재 **미버전관리**(유실 단일점). 백업 권장. 단, 스크립트가 내부 호스트명(`billingN.danawa.com`)·경로(`/home/danawa/...`)·비번 접미사 규칙(`${prefix}billing${n}`)을 포함하므로:
  - **공개 레포(vibe-dotfiles 등)에 그대로 커밋 금지** — 운영 환경 정보 노출.
  - 백업하려면 (a) 비공개 위치(사설 레포/PARA), 또는 (b) 호스트명·경로를 env/설정 파일로 외부화해 민감정보 제거 후 vibe-tools 편입.
- tp4 미러 경로(`/Billing_Log_Storage/svm_billing*`)는 운영팀 정책에 따라 변경될 수 있으니 수집 실패 시 경로 우선 확인.
