# Thaw 프로필

Thaw 앱에서 내보낸 개인 Mac 메뉴 막대 프로필을 보관한다. Thaw 앱은 `Brewfile`의 `cask "thaw"`로 설치된다(macOS 26 이상). `/Applications`에 쓰기 권한이 없는(관리자 아닌) Mac에서는 `~/Applications`에 설치되므로 관리자 권한이 필요 없다. 프로필은 `install.sh`가 적용하지 않으므로 아래 절차대로 앱에서 직접 가져온다.

- `profiles/Thaw-Profiles-2026-10-18.json`: 배치 변경 전 복구용 `personal-before-2026-10-18` 프로필 1개.
- 복구할 때는 Thaw의 프로필 가져오기에서 JSON을 선택한 뒤 해당 프로필을 적용한다.
- 배치 변경 후에는 앱에서 다시 내보내고 날짜별 파일로 보관한다.

`Thaw-Profiles-2026-10-18.json`은 사용자 배치 선택 전 상태다.

2026-10-18 추가: `profiles/Thaw-Compact-2026-10-18.json`에 간결 배치용 `personal-compact-2026-10-18` 프로필을 보관했다. 의도한 배치는 visible 8개 / hidden 17개다. 가져오기·적용·재시작 후에도 실제 layout 화면의 visible 아이콘이 줄지 않아 실제 배치 적용은 미완료 상태다. 기존 `personal-before-2026-10-18` 복구용 백업은 그대로 유지한다.

## 현재 복원 대상 — 2026-10-19

`profiles/Thaw-Final-2026-10-19.json`의 `personal-final-2026-10-19`를 최신 복원 대상으로 사용한다. 10/18 공식 내보내기 파일은 변경하지 않고 보존한다.

이번 파일은 **앱 UI에서 내보낸 원본이 아니다**. 10/18 공식 프로필의 스키마·타입을 유지하면서 `~/Library/Preferences/com.stonerl.Thaw.plist`의 현재 저장값으로 재구성했다. `MenuBarItemManager.savedSectionOrder`를 배치·순서·항목별 영역에 반영했고, plist에 명시된 일반·고급 설정과 화면별 설정·모양·고정 항목을 반영했다. plist에 없는 기본값은 10/18 프로필 값을 유지했다. 실제 화면 배치나 다른 Mac의 가져오기 성공을 검증한 것으로 해석하지 않는다.

- 보임 8개: Thaw → CodexBar → Notion Calendar → RunCat → 입력 소스 → 배터리 → 제어 센터 → 시계.
- 숨김 12개: ChatGPT → NordVPN → EndpointConnect → Amphetamine → Docker Desktop → OneDrive → Google Drive → JetBrains Toolbox → cmux → 카카오톡 → 암호 → 지금 재생 중.
- 항상 숨김 7개: Catchtype → Raycast → Homerow → Rectangle → PopClip → Karabiner → Logitech G HUB.
- 항상 숨김 열기 제스처 3개 off, 자동 다시 숨기기 on, 마우스 오버 표시 on, 전역 Thaw 바 on.
- 진단 로깅은 현재 on이지만 공식 프로필 스키마에 포함되지 않아 이 JSON으로 이전되지 않는다. 필요 시 각 Mac에서 별도로 조정한다.

아래 적용 절차에서는 파일을 `Thaw-Final-2026-10-19.json`, 프로필을 `personal-final-2026-10-19`로 선택한다. 적용 전 대상 Mac 프로필을 백업하고, 적용 후 앱에서 저장·공식 내보내기로 다시 보관한다.

## 10/18 공식 내보내기 이력과 다른 Mac 적용

`profiles/Thaw-Final-2026-10-18.json`은 사용자가 직접 정렬하고 항상 숨김 동작을 확인한 뒤 공식 Thaw UI에서 내보낸 원본이다. 이 파일에는 이전 before·compact 프로필과 최종 `personal-final-2026-10-18` 프로필, 총 3개가 포함된다. 적용할 때 최종 프로필을 선택한다.

- 보임 8개: Thaw → ChatGPT(Codex 식별자) → Notion Calendar → RunCat → 입력 소스 → 배터리 → 제어 센터 → 시계.
- 숨김 11개: NordVPN → EndpointConnect → Amphetamine → Docker Desktop → OneDrive → Google Drive → JetBrains Toolbox → cmux → 카카오톡 → 암호 → 지금 재생 중.
- 항상 숨김 6개: Raycast → Homerow → Rectangle → PopClip → Karabiner → Logitech G HUB. 각 목록은 왼쪽에서 오른쪽 순서이며, 최종 사용자 정렬을 그대로 보존했다.
- 항상 숨김 표시용 더블 클릭·Option 클릭은 꺼져 있다. 자동 다시 숨기기는 켜져 있다.
- 전역 디스플레이 설정의 Thaw 바 사용(`globalDisplayConfiguration.useIceBar`)은 켜져 있다. 레거시 `generalSettings.useIceBar=false`와 차이가 있으므로 JSON을 임의 수정하지 않는다.

다른 Mac에서 사용자가 진행할 절차:

1. 이 저장소에서 `git pull --ff-only`로 백업 파일을 받는다. 현재 Mac에서 아직 push하지 않았다면 먼저 변경 커밋을 원격에 올려야 한다.
2. 대상 Mac의 현재 Thaw 상태를 별도 이름의 프로필로 저장하고 JSON으로 내보낸다.
3. Thaw 설정의 프로필 불러오기에서 `thaw/profiles/Thaw-Final-2026-10-18.json`을 선택한다.
4. 목록에서 **`personal-final-2026-10-18`**을 선택해 적용한다. before·compact는 복구 및 이전 시도 기록이다.
5. 대상 Mac의 **디스플레이 → 디스플레이별 설정**에서 사용 중인 화면을 선택하고 **Thaw 바 사용**이 켜져 있는지 확인한다. 내보낸 디스플레이 UUID는 원본 Mac 전용이므로 대상 화면에 동일한 오버라이드가 적용된다고 가정하지 않는다.
6. 설치돼 실행 중인 앱의 영역과 순서, 숨김·자동 다시 숨김, 더블 클릭·Option 클릭으로 항상 숨김이 열리지 않는지 확인한다. 대상 Mac에 없는 앱은 나타나지 않는다.

대상 Mac 적용은 아직 수행하지 않았다. 프로필 파일은 앱 배치와 환경 설정을 포함하지만 Thaw 설치·macOS 접근성 권한·로그인 시 실행 등 OS 권한을 자동 이전하지 않는다. 이 저장소의 `install.sh`도 Thaw 프로필을 자동 적용하지 않는다.
