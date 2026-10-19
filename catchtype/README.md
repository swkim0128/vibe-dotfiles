# Catchtype

한/영 키를 누르지 않아도 단어 단위로 한글·영문 입력을 자동 전환하는 macOS 입력 보조 앱. 입력 내용은 기기 밖으로 전송되지 않는다.

Homebrew cask가 없으므로 `Brewfile`에 넣지 않는다. 대신 레포 `install.sh`가 [install.sh](install.sh)를 호출해 아래 수동 절차와 같은 검증을 게이트로 설치한다(홈페이지의 dmg 링크 사용 → dmg 서명 → 복사 → 앱 서명·번들 ID, 불일치면 중단·삭제). 이미 `/Applications/Catchtype.app`이 있으면 건너뛴다. 단독 실행: `bash catchtype/install.sh`. `/Applications` 쓰기 권한이 없는 Mac에서는 복사 단계가 실패하므로 관리자 계정에서 실행한다. 손쉬운 사용 권한은 자동화할 수 없으므로 아래 「권한」을 직접 한다.

## 수동 설치

2026-10-18 기준 버전은 `0.3.0-beta.6`, 요구 사항은 macOS 13 이상이다.

1. https://catchtype.com 에서 dmg를 내려받는다.
2. 설치 전에 dmg 서명을 확인한다.

   ```bash
   spctl -a -vvv -t open --context context:primary-signature ~/Downloads/<Catchtype dmg 파일>
   ```

3. dmg를 열고 `Catchtype.app`을 `/Applications`로 옮긴다.
4. 설치 후 앱 서명을 확인한다.

   ```bash
   spctl -a -vv /Applications/Catchtype.app
   ```

두 명령 모두 아래 값이 나와야 한다. 다르면 설치하지 않거나 즉시 제거한다.

- 판정: `accepted`, `source=Notarized Developer ID`
- 팀 ID: `8L5WFHS4F9`
- 번들 ID: `com.hebbianai.catchtype` (설치 후 `mdls -name kMDItemCFBundleIdentifier /Applications/Catchtype.app`로 확인)

## 권한

**시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용**에서 Catchtype을 허용한다.

## 동작 확인

한/영 키를 누르지 않고 `test 테스트 응 yes`를 입력해 그대로 나오는지 확인한다.

## 주의

- Karabiner-Elements에 한/영 전환 키 설정이 있으면 충돌할 수 있다. 이상하면 그 규칙부터 끈다.
- Typescript 입력기와 동시에 설치하지 않는다.

## 제거

`/Applications/Catchtype.app`을 휴지통으로 옮긴다.
