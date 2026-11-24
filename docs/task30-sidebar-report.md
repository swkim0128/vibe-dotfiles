# 작업 보고 — #30 역할별 사이드바

**결과** 소스 구현과 기존 Python 표시 검사 23건 완료. release 빌드 권한 오류로 새 실행기 배포·설정 reload·갱신 후 실제 API 검증은 보류했다. 업무컴 실기와 메인의 해당 판본 확인은 미완료다. 최종 완료로 기록하지 않는다.

**판본·환경** 기준 `f5cd682` → 이 문서를 포함한 Git 커밋. 개인컴 프로필 `personal`, Herdr client/server 0.9.5·protocol 22·endpoint compatible. 테스트 판본은 같은 커밋의 제품·테스트 소스다. 보고 문서만 이후 추가했다.

## 변경 계획

| 변경 ID | 기존 → 목표 동작 | 완료 기준 |
|---|---|---|
| CHG-01 | 같은 cwd의 첫 행이 같은 프로젝트명 → 명시 역할 첫 행과 프로젝트 별도 행 | label 우선, 같은 pane·terminal의 공식 agent name 대체, 미지정 명시 |
| CHG-02 | 작업 행에 유휴/완료 상태 혼합 → 작업 제목과 실제 상태 별도 | 관측 작업 우선, native 작업 제목 대체, 없으면 작업 미확인 |
| CHG-03 | 기기별 반영 차이 불명확 → 공통 설치와 기기별 실기 구분 | 공통 선언·설치 소스 확인, 업무컴 별도 반영·검증 명령 제공 |

## 실제 변경과 diff

`herdr/runtime/src/main.rs`는 기존 프로젝트 metadata 갱신에서 `sidebar_role`을 발행한다. pane label을 우선하고 `agent.list`의 같은 pane·terminal·agent 이름을 대체값으로 사용한다. 역할을 cwd·최근 제목으로 추정하거나 기존 label/name·상태를 변경하지 않는다. Python snapshot에는 native 작업 제목만 추가 전달한다.

`herdr/config.toml`은 역할 행을 첫 줄에 추가했다. `herdr/hud.py`는 요청 관측이 없을 때 상태 대신 native 작업 제목 또는 `작업 미확인`을 사용한다. 기존 검사에서 미관측 작업의 기대값 3개를 이에 맞췄다. `docs/herdr-display.md`에 work/personal 공통 반영 경로를 추가했다. [전체 diff](https://github.com/swkim0128/vibe-dotfiles/compare/f5cd682...master)는 이후 커밋을 포함할 수 있으므로 이 문서를 포함한 커밋의 파일 diff를 기준으로 확인한다.

```diff
- tokens: project_path
+ tokens: project_path, sidebar_role (명시 label → 공식 agent name → 역할 미지정)
- 첫 행: project_name
+ 첫 행: sidebar_role / 다음 행: project_name
- 작업 미관측: 유휴·대기·응답 완료
+ 작업 미관측: native 작업 제목 또는 작업 미확인
```

## 테스트와 결과

| 테스트·검사 | 조건과 기대값 | 관측값·판정 |
|---|---|---|
| 기존 `tests/test_herdr_display.py` | 요청 신원·만료·모호함·소유권 등 기존 회귀 | 23건, 0.014초, OK |
| 등록 quick 검사 | Python 2파일·TOML 1파일 구문 유효 | receipt의 세 명령 모두 exit 0 / passed |
| `cargo clippy -- -D warnings` | 엄격 lint 통과 | 실패. 기존 bar.rs 인자 과다/중첩조건, main.rs render_view 인자 과다 3건. 변경 외 코드 보존 |
| 기본 release build | 설치 링크의 실행기 갱신 | 실패. 임시 archive 디렉터리 삭제 EPERM |
| 별도 임시 target release build | 기존 target 영향 없이 같은 sandbox에서 빌드 | 실패. `/private/tmp/vibe-herdr-role-build` 생성 EPERM. 반복 중단 |
| 실제 API 변경 전 | 역할 원본과 상태 보존 여부 | 기존 여섯 label/name 존재. 일정·식단·예산 idle, 메인·설정 작업 working 관측 |
| 실제 API 변경 후·주기 유지 | 역할 token과 terminal ID 유지 | 미검증. release 빌드 실패로 reload하지 않음 |
| 업무컴 실기 | 버전·링크·실행기·주기 갱신 확인 | 접근 근거 없음 / 미검증 |

**실행 근거** 보이는 `CLI 실행` 작업공간의 기존 dotfiles 실행 셸에서 다음 명령을 각각 제출·실행했다. 읽은 실행 출력에 Python `OK`, clippy와 build의 실제 오류가 남아 있다. 캡처 셸에서 빌드를 실행하지 않았다.

```bash
codex sandbox -P vibe-workspace --include-managed-config -C <dotfiles> -- python3 -B tests/test_herdr_display.py
codex sandbox -P vibe-workspace --include-managed-config -C <dotfiles> -- mise exec -- cargo clippy --locked --manifest-path herdr/runtime/Cargo.toml -- -D warnings
codex sandbox -P vibe-workspace --include-managed-config -C <dotfiles> -- mise exec -- cargo build --locked --release --manifest-path herdr/runtime/Cargo.toml
codex sandbox -P vibe-workspace --include-managed-config -C <dotfiles> -- mise exec -- cargo build --locked --release --manifest-path herdr/runtime/Cargo.toml --target-dir /private/tmp/vibe-herdr-role-build
```

등록 검사 원본: `/var/folders/tm/7_nsz6_n0r7cwp342h51rnx80000gn/T/vibe-automatic-checks-501/44808a685413a9cb068e801b6e9c0b4cb5a8a6a921cc8f40f508fc22ac0cc54b/c24d3360abdfe17f53ae1bb865096b8e016db00f97c4032f367e28e9d07a0a72.receipt.json` (`status=passed`, 명령별 exit 0)。`git diff --check`도 exit 0이다. 이 기기 임시 경로는 검증 근거이며 공용 실행 코드에서 사용하지 않는다.

## 확인할 사항

- 배포 준비: 공통 manifests와 두 프로필이 같은 `herdr_config` 선언을 사용함을 확인했다. 두 프로필 파일은 공통 목록을 변경하지 않는다.
- 설정 배포: 개인컴 config/hud/release 링크는 기존 실제 레포를 가리킨다. Python 소스는 링크로 노출됐으나 새 Rust 바이너리 배포는 실패했다.
- 실행 반영: 새 역할 token을 발행할 release 바이너리를 빌드하지 못해 설정 reload를 수행하지 않았다. 기존 대화·TUI·pane·프로세스는 재시작·종료하지 않았다.
- Git 동기화는 이 문서가 포함된 커밋과 원격 차이를 별도 결과로 보고한다. Git push 성공을 실행 반영으로 간주하지 않는다.
- 업무컴에서는 [반영 명령](herdr-display.md#workpersonal-사이드바-반영-확인)을 실제 기기 프로필·경로에서 수행하고 5초 갱신 전후를 확인해야 한다. 업무컴 정보와 성공을 추정하지 않았다.
- 재개 조건: 승인된 sandbox에서 Cargo가 결과 디렉터리를 생성·삭제할 수 있는 실행 환경 확보. 이후 release 빌드 → 설정 검사/reload → 역할 token·프로젝트·작업 제목·실제 상태·terminal 보존 API 비교. 기존 lint 3건은 별도 범위 판단이 필요하다.

**사용자 판단** 검토 전 · CHG-01~03 / 이 보고서를 포함한 커밋. PARA 메인의 해당 판본 실제 확인 전 최종 done·확인값을 기록하지 않는다.
