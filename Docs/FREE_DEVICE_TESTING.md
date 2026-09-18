# 유료 계정 없이 iPhone에서 테스트하기

개인 Mac이 없어도 **클라우드 macOS에서 빌드 → Windows의 Sideloadly에서 무료 계정으로 서명·설치**하는 경로를 시도할 수 있습니다. [클라우드 IPA 안내](CLOUD_IPA.md)를 참고하세요. 설치 도구를 포함한 실제 동작은 검증이 남아 있습니다. 무료 서명은 7일 후 만료됩니다.

아래는 Apple의 Xcode를 사용해 Mac에 연결한 iPhone에 직접 설치하는 별도 경로입니다.

이 프로젝트에는 무료 계정 전용 `KotoKeyboard-FreeDevice` Scheme이 있습니다. 무료 서명에서 문제가 될 수 있는 App Group과 공유 Keychain entitlement를 제거합니다.

## 이 구성에서 확인할 수 있는 것

- 메인 앱과 키보드 확장 설치
- 키보드 추가 및 전환
- 한국어·영어·숫자·기호 입력
- 한글 조합과 삭제
- Mock 및 제한된 로컬 예문 번역
- 후보 표시, 원문 교체, 삽입 전용 안전 동작
- 보안·전화번호 입력창 전환
- 다크 모드와 VoiceOver

## 확인할 수 없는 것

- 메인 앱에서 변경한 설정을 키보드 확장과 공유
- App Group 자체의 동작
- 공유 Keychain 토큰
- 실제 원격 번역 서버
- TestFlight 및 App Store 배포

무료 구성에서는 앱과 확장이 각자의 `UserDefaults.standard`를 사용합니다. 키보드는 안전한 기본값인 Mock, 일본어, 자동 번역 550ms로 시작합니다. 메인 앱의 설정 화면에서 값을 바꿔도 키보드에는 전달되지 않습니다.

## 필요한 것

- 잠시 빌릴 수 있는 Mac 또는 직접 조작 가능한 Mac
- 현재 iOS SDK를 지원하는 Xcode
- 본인의 iPhone과 데이터 통신 가능한 USB 케이블
- 무료 Apple Account
- 인터넷 연결: 최초 Xcode 로그인과 서명 생성에 필요

원격 클라우드 Mac에 로컬 iPhone을 USB로 연결할 필요는 없습니다. 클라우드 빌드 결과를 Windows에서 재서명하는 경로는 위의 별도 안내를 따릅니다. 아래 Xcode 직접 설치 경로에는 물리적으로 접근 가능한 Mac이 필요합니다.

## 설치 순서

1. 이 프로젝트 폴더를 Mac으로 복사하거나 Git 저장소에서 받습니다.
2. Xcode에서 `KotoKeyboard.xcodeproj`를 엽니다.
3. Xcode → Settings → Accounts에서 본인의 Apple Account를 추가합니다. 계정이 `Personal Team`으로 표시됩니다.
4. `Config/Project.xcconfig`의 `APP_BUNDLE_IDENTIFIER`를 전 세계에서 고유할 만한 값으로 바꿉니다. 예: `com.yourname.KotoKeyboardDev`. 확장 ID는 자동으로 `.keyboard`가 붙습니다.
5. Scheme을 `KotoKeyboard-FreeDevice`로 선택합니다. 일반 `KotoKeyboard` Scheme에는 App Group·Keychain entitlement가 있어 무료 서명용이 아닙니다.
6. 프로젝트 설정에서 `KotoKeyboard` Target → Signing & Capabilities → Automatically manage signing을 켜고 본인의 Personal Team을 선택합니다.
7. `KotoKeyboardExtension` Target에도 같은 Personal Team을 선택합니다. App Groups 또는 Keychain Sharing을 다시 추가하지 마세요.
8. iPhone을 Mac에 연결하고 “이 컴퓨터를 신뢰”를 승인합니다. iPhone에서 개발자 모드를 요구하면 설정 → 개인정보 보호 및 보안 → 개발자 모드를 켜고 재시동합니다.
9. Xcode 상단 실행 기기로 연결한 iPhone을 선택하고 Run을 누릅니다.
10. iPhone에서 앱을 한 번 실행한 후 설정 → 일반 → 키보드 → 키보드 → 새 키보드 추가 → 코토 키보드를 선택합니다.
11. 전체 접근 허용은 끈 상태로 먼저 테스트합니다. Mock에는 네트워크 권한이 필요하지 않습니다.
12. 메모 앱에서 지구본 키로 코토 키보드를 선택하고 `안녕하세요` → `こんにちは` 후보 → 탭 교체를 확인합니다.

서명 오류가 나면 먼저 선택한 Scheme이 `KotoKeyboard-FreeDevice`인지 확인하고, 앱과 확장이 같은 Personal Team인지, Bundle ID가 고유한지 확인합니다. Xcode가 무료 프로필을 다시 만들도록 Signing의 Team을 잠시 `None`으로 바꿨다가 Personal Team으로 다시 선택할 수도 있습니다.

무료 Personal Team에서는 App ID, 기기, 설치 앱 수 제한이 있으며 provisioning profile은 7일 후 만료됩니다. 만료되면 같은 Mac/Xcode에서 다시 Run해야 합니다. Apple 공식 제한은 [Developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account)에서 확인할 수 있습니다.

Apple은 iOS capability 사용 가능 범위가 멤버십에 따라 달라진다고 안내합니다. App Group은 등록된 그룹이 필요한 기능이므로 무료 실기기 구성에서는 제거했습니다. [지원 capability 안내](https://developer.apple.com/help/account/reference/supported-capabilities-ios), [App Group 구성](https://developer.apple.com/documentation/xcode/configuring-app-groups)
