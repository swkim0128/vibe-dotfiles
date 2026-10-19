# Thaw 프로필

Mac 메뉴 막대 배치용 Thaw 프로필을 기기별로 보관한다. Thaw 앱은 `Brewfile`의 `cask "thaw"`로 설치된다(macOS 26 이상). `/Applications`에 쓰기 권한이 없는(관리자 아닌) Mac에서는 `~/Applications`에 설치되므로 관리자 권한이 필요 없다. 프로필은 `install.sh`가 적용하지 않으므로 아래 절차대로 앱에서 직접 가져온다.

## 기기별 복원 대상 — 2026-10-19

| 기기 | 파일 | 프로필 |
|---|---|---|
| 개인 Mac | `profiles/Thaw-Final-2026-10-19.json` | `personal-final-2026-10-19` |
| 업무 Mac | `profiles/Thaw-Work-2026-10-19.json` | `work-final-2026-10-19` |

두 파일 모두 **앱 UI에서 내보낸 원본이 아니라 재구성본**이다. 형식은 앱 내보내기와 같다(`{version: 1, entries: [{profile}]}`). 실제 화면 배치나 다른 Mac에서의 가져오기 성공을 검증한 것으로 해석하지 않는다.

### 개인 Mac — `personal-final-2026-10-19`

10/18 공식 프로필의 스키마·타입을 유지하면서 `~/Library/Preferences/com.stonerl.Thaw.plist`의 현재 저장값으로 재구성했다. `MenuBarItemManager.savedSectionOrder`를 배치·순서·항목별 영역에 반영했고, plist에 명시된 일반·고급 설정과 화면별 설정·모양·고정 항목을 반영했다. plist에 없는 기본값은 10/18 프로필 값을 유지했다.

- 보임 8개: Thaw → CodexBar → Notion Calendar → RunCat → 입력 소스 → 배터리 → 제어 센터 → 시계.
- 숨김 12개: ChatGPT → NordVPN → EndpointConnect → Amphetamine → Docker Desktop → OneDrive → Google Drive → JetBrains Toolbox → cmux → 카카오톡 → 암호 → 지금 재생 중.
- 항상 숨김 7개: Catchtype → Raycast → Homerow → Rectangle → PopClip → Karabiner → Logitech G HUB.
- 항상 숨김 열기 제스처 3개 off, 자동 다시 숨기기 on, 마우스 오버 표시 on, 전역 Thaw 바 on.
- 진단 로깅은 현재 on이지만 공식 프로필 스키마에 포함되지 않아 이 JSON으로 이전되지 않는다. 필요 시 각 Mac에서 별도로 조정한다.

### 업무 Mac — `work-final-2026-10-19`

업무 Mac에서 사용자가 배치를 정리한 뒤, `personal-final-2026-10-19`를 틀로 `menuBarLayout`의 `itemOrder`·`savedSectionOrder`·`itemSectionMap`·`newItemsPlacement`만 업무 Mac plist의 현재 값으로 교체해 만들었다. 일반·고급·모양·화면 설정은 개인 프로필과 같다. 개인 Mac과 달리 **Catchtype은 보임, 입력 소스는 숨김**이고, 업무 앱이 추가돼 있다.

- 보임 8개: Thaw → CodexBar → Notion Calendar → RunCat → Catchtype → 배터리 → 제어 센터 → 시계.
- 숨김 19개: Docker Desktop → OneDrive → Google Drive → cmux → JetBrains Toolbox → PC 필터(jirandata) → Figma → Kaspersky → Rancher Desktop → Siri → 입력 소스 → NAVER WORKS → 카카오톡 → 암호 → 지금 재생 중 → ChatGPT(Codex 식별자) → NordVPN → EndpointConnect → Amphetamine.
- 항상 숨김 9개: Raycast(My Stats) → Karabiner → Logitech G HUB → 신도리코 IPS → Time Machine → Raycast → Homerow → Rectangle → PopClip.
- 새 항목 배치: 항상 숨김 영역, Raycast(My Stats) 왼쪽.

## 적용 절차 (다른 Mac)

1. 이 저장소에서 `git pull --ff-only`로 파일을 받는다.
2. 대상 Mac의 현재 Thaw 상태를 별도 이름의 프로필로 저장하고 JSON으로 내보낸다(백업).
3. Thaw 설정의 프로필 불러오기에서 위 표의 기기별 파일을 선택하고, 해당 프로필을 적용한다.
4. **디스플레이 → 디스플레이별 설정**에서 사용 중인 화면을 선택하고 **Thaw 바 사용**이 켜져 있는지 확인한다. 내보낸 디스플레이 UUID는 원본 Mac 전용이므로 대상 화면에 동일한 오버라이드가 적용된다고 가정하지 않는다.
5. 설치돼 실행 중인 앱의 영역과 순서, 숨김·자동 다시 숨김, 더블 클릭·Option 클릭으로 항상 숨김이 열리지 않는지 확인한다. 대상 Mac에 없는 앱은 나타나지 않는다.
6. 적용 후 앱에서 저장·공식 내보내기로 다시 보관한다.

프로필 파일은 앱 배치와 환경 설정을 포함하지만 Thaw 설치·macOS 접근성 권한·로그인 시 실행 등 OS 권한을 자동 이전하지 않는다.

## 프로필 생성 방법

### 권장 — 앱 UI 저장·내보내기

배치를 정리한 뒤 Thaw 설정의 프로필에서 현재 상태를 새 프로필로 저장하고, JSON으로 내보내 `profiles/`에 날짜별 파일로 보관한다. 이것이 유일한 공식 경로이며, 내보낸 파일은 원본으로 취급한다.

### 대안 — 파일 직접 기록

Thaw가 제공하는 자동화 수단은 세 가지뿐이고, **어느 것으로도 프로필을 새로 만들 수 없다.**

- `thaw://` URL 스킴: 설정 토글만 가능.
- 단축어(Shortcuts): 이미 있는 프로필을 적용만 가능.
- CLI: 없음.

그래서 UI 없이 만들어야 할 때는 프로필 저장소에 파일을 직접 기록한다(`work-final-2026-10-19`를 이 방식으로 만들었다).

1. Thaw를 완전히 종료한다(실행 중에 기록하면 앱이 덮어쓴다).
2. `~/Library/Application Support/Thaw/Profiles/`에 `<UUID>.json` 프로필 파일을 기록한다. 기존 프로필을 틀로 복사하고 `id`·`name`·`createdAt`·`modifiedAt`과 필요한 필드(예: `menuBarLayout`)만 바꾼다.
3. 같은 디렉터리의 `profiles.json` 목록에 `{id, name, createdAt, modifiedAt}` 항목을 추가한다.
4. Thaw를 다시 실행한다.
5. 프로필 목록에 새 프로필이 보이는지, 기존 프로필이 유지되는지, 실행 중 배치가 바뀌지 않았는지 확인한다.

저장소에 보관할 때는 단일 프로필을 `{version: 1, entries: [{profile: <프로필 JSON>}]}`으로 감싸 내보내기 형식에 맞춘다. 이렇게 만든 파일은 **앱 UI 내보내기 원본이 아닌 재구성본**임을 README에 명시한다.

## 이력

- `profiles/Thaw-Profiles-2026-10-18.json`: 배치 변경 전 복구용 `personal-before-2026-10-18` (공식 내보내기).
- `profiles/Thaw-Compact-2026-10-18.json`: 간결 배치 시도 `personal-compact-2026-10-18` (보임 8 / 숨김 17 의도). 적용 후에도 실제 화면 보임 아이콘이 줄지 않아 미완료로 끝났다.
- `profiles/Thaw-Final-2026-10-18.json`: 사용자가 직접 정렬한 뒤 공식 UI로 내보낸 원본. before·compact·`personal-final-2026-10-18` 3개 포함. 전역 디스플레이의 Thaw 바 사용(`globalDisplayConfiguration.useIceBar`)은 켜져 있고 레거시 `generalSettings.useIceBar=false`와 차이가 있으므로 JSON을 임의 수정하지 않는다.
