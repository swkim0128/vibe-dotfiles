# 작업 보고 — #32 큐 TUI 요청·분류·목표 분리

**결과** `요청 | 분류 | 작업 목표` 소스 구현과 Python 표시 회귀 23건, Rust 제품·테스트 소스의 `cargo check --tests`를 마쳤다. Rust 테스트 실행은 archive 임시 디렉터리 삭제 권한 오류로 실행 전에 중단됐다. 새 Rust 실행기 빌드·교체·TUI 재실행·화면 실기 검증은 미완료다. 검증 완료나 최종 완료로 기록하지 않는다.

**판본·환경** dotfiles 기준 `b33d541` → 이 보고서를 포함하는 커밋. API 계약은 설정 저장소 `b19d0c3`의 `docs/2026-11-25-queue-classification-report.md`와 사용자 배포 완료 전달을 회수했다. 개인컴 `personal`·Herdr 0.9.5. 기존 보이는 dotfiles 실행 셸에서 검사했다. 업무컴은 실기 미검증이다.

## 변경 계획

| 변경 ID | 기존 → 목표 동작 | 완료 기준 |
|---|---|---|
| CHG-32-01 | 경로·key·Slack 출처로 추정한 분류를 목표 앞에 부착 → API의 text/classification/goal 독립 전달 | 원문 보존, personal/work/null·누락, 추정·접두사 없음 |
| CHG-32-02 | 요청 ID·목표·상태·단계 목록 → 요청 원문·분류·작업 목표 세 열 | 개인/업무/미설정과 긴 한글·emoji를 셀 폭 안에서 표시 |
| CHG-32-03 | 기존 조회·정렬·선택·권한 유지 | 기존 회귀와 신규 폭/페이지/조회 전용 검증, 승인된 실행 반영 |

## 실제 변경과 diff

`herdr/hud.py`의 `task_record`가 `text`, 최상위 `classification`, `request_data.goal`을 별도로 전달한다. 분류 추정 함수와 목표 접두사·512자 선행 잘림을 제거했다. 목표가 비어 있어도 요청 원문으로 대체하지 않는다. 구형 API에 분류가 없으면 null로 전달한다.

`herdr/runtime/src/main.rs`는 `personal → 개인`, `work → 업무`, null·누락 → `미설정`을 독립 열로 표시한다. 24열 이상에서 분류는 6셀이고 요청과 목표는 나머지 폭을 나눈다. 24열 미만은 같은 필드 순서로 전체 행을 자른다. 한글·emoji 폭 계산과 제어 문자 제거는 기존 `plain`을 사용한다. 요청 ID를 요청 원문 앞에 두어 선택 대상을 구분한다. 원문·목표·분류·큐 상태·배정·단계 흐름은 상세에서 각각 읽는다.

기존 `task_page`, 선택 강조·ID, 클릭/키 입력 처리, `selection_owned`, `completed_selection`, 큐 정렬과 완료 확인 숨김 로직은 변경하지 않았다. 상태·단계 목록 열은 요청한 세 열로 대체했고 해당 정보는 상세에 유지했다. `docs/herdr-display.md`를 같은 계약으로 갱신했다.

```diff
- goal: "[추정 분류] 목표", 요청 원문과 분류 필드 없음
+ text: API text, classification: API 최상위 값, goal: request_data.goal
- 요청ID | 목표 | 상태 | 단계
+ 요청ID·원문 | 개인/업무/미설정 | 작업 목표
```

전체 diff는 이 문서를 포함한 커밋의 `git show`를 따른다. 설정 저장소의 스키마·API·CLI·운영 DB는 수정하지 않았다. 운영 요청에 테스트용 분류를 쓰거나 기존 행을 일괄 분류하지 않았다.

## 테스트와 결과

| 테스트·SCN-ID | 조건과 기대값 | 관측값·판정 |
|---|---|---|
| SCN-32-01 Python | personal/work/null과 긴 목표 → text/goal 원문·독립 필드 유지 | 통과. 접두사·선행 잘림 없음 |
| SCN-32-02 Python | 구형 응답 누락·personal/업무 key·노트 경로·제목 → null, 빈 goal은 빈 값 | 통과. 출처/제목 추정과 text fallback 없음 |
| 기존 Python 회귀 | 요청 신원·관측·정렬·완료 확인·조회 전용 경계 | 위 두 사례 포함 전체 23건 OK, 0.012초 |
| SCN-32-03 Rust | 분류 3종·누락·한글/emoji 긴 목표·폭 0~240 → 셀 폭 제한·분류·말줄임 | 작성, 미실행. 의존 라이브러리 빌드 단계 권한 오류 |
| SCN-32-04 Rust | 세 열 header·순서·선택 강조·페이지·read_only → 원래 선택/권한 유지 | 작성, 미실행. 같은 빌드 차단 |
| Rust 제품·테스트 컴파일 검사 | archive 생성·실행 없이 새 코드의 타입·이름 검증 | `cargo check --tests` 성공, 1.00초. incremental 캐시 finalize EPERM 안내는 남음 |
| 공개 배포 API 읽기 | `list --all`의 #34에 최상위 classification과 text/goal 존재 | classification:null 및 독립 원문·목표 관측. DB 쓰기 없음 |
| 등록 구문 검사·공백 | Python 구문과 diff 유효 | quick receipt passed, `git diff --check` 종료 0 |
| 실행본·실기 | 새 Rust 실행기로 세 열 표시·입력·기존 프로세스 보존 | 미실행. 바이너리 교체·TUI 재시작 안 함 |

**실행 근거** 다음 명령을 각각 실행했다. 검사 제출 응답만으로 통과를 판정하지 않고 기존 실행 셸의 완료 출력을 읽었다.

```bash
codex sandbox -P vibe-workspace --include-managed-config -C <dotfiles> -- python3 -B tests/test_herdr_display.py
codex sandbox -P vibe-workspace --include-managed-config -C <dotfiles> -- mise exec -- cargo test --locked --manifest-path herdr/runtime/Cargo.toml queue_display_tests
codex sandbox -P vibe-workspace --include-managed-config -C <dotfiles> -- mise exec -- cargo check --locked --tests --manifest-path herdr/runtime/Cargo.toml
vibe queue list --all --json
git diff --check
```

Python 출력은 `Ran 23 tests ... OK`다. Cargo test는 `itoa`, `bitflags`, `zmij`, `memchr`, `libc`, `regex-syntax`, `serde_core` 등의 `.temp-archive` 삭제에서 `Operation not permitted (os error 1)`로 실패했다. 이 명령은 새 테스트 실행까지 도달하지 않았다. archive를 만들지 않는 별도 `cargo check --tests`는 `Finished dev ... 1.00s`로 제품·테스트 소스의 컴파일 검사를 마쳤으나 동작 테스트 통과를 대신하지 않는다. #30 때의 동일 archive 권한 실패를 해결됐다고 추정하거나 추가 release 빌드로 반복하지 않았다.

등록 구문 receipt: `/var/folders/tm/7_nsz6_n0r7cwp342h51rnx80000gn/T/vibe-automatic-checks-501/44808a685413a9cb068e801b6e9c0b4cb5a8a6a921cc8f40f508fc22ac0cc54b/949c7027c06adb34e645053f93d29f9d80d14e86ae5d9bd604a0bd2330d979bd.receipt.json`. `status=passed`이고 Python 두 파일·기존 TOML의 명령별 exit 0이다. 이 경로는 기기별 실행 근거이며 공용 코드 상수가 아니다.

## 확인할 사항

- **API 배포**: config #34의 SQL 선택 배포는 사용자 전달·계약 문서를 회수했고, 실제 공개 조회의 새 필드를 확인했다. TUI 배포 성공을 뜻하지 않는다.
- **설정 노출**: 기존 `hud.py` 심링크가 소스를 가리키므로 Python 데이터 전달 변경은 기존 소비자가 읽을 수 있다. 새 Rust 세 열 renderer는 아직 설치·실행되지 않았다.
- **TUI 배포·실행 반영**: Rust 검사·빌드가 가능한 승인 환경이 필요하다. 새 바이너리 교체·설정 reload·기존 TUI 재실행을 하지 않았다. 기존 대화·프로세스·사용자 세션은 종료하지 않았다.
- **소스 Git**: 관련 파일만 커밋하고 기존 `personal-git-sync.sh --no-install`로 origin 확인·fetch·양쪽 보존 통합 판단·일반 push·0/0 확인한다. 실제 결과는 메인 회신의 커밋과 로그에서 확인한다. 소스 동기화와 운영 반영은 별개다.
- **후속**: 사용자 또는 메인이 승인 환경에서 위 Cargo 검사를 실행한 뒤 release 빌드·선택 배포와 실제 TUI 세 열·긴 원문·선택·조회 전용을 확인해야 한다. 같은 오류를 임의 재시도하거나 sandbox를 해제하지 않는다.
- **기존 #30**: 소스·보고서·verify 근거를 보존한 채 공식 `fail`로 검증 실패를 기록하고 자원을 반납했다. 완료·사용자 확인으로 바꾸지 않았으며 별도 재개 조건을 유지한다.

검증 보고서는 #32의 verify 근거에 포함하며 별도 보고 단계나 새 큐를 만들지 않는다. 기존 고정 정의·과거 근거는 변경하지 않았다. 필수 Rust 검사가 남아 있으므로 verify와 요청을 완료하지 않는다.

**사용자 판단** 검토 전 · CHG-32-01~03 / 이 보고서를 포함하는 소스 판본. 운영 반영 미완료.
