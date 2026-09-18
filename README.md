# 코토 키보드 — iPhone 일본어 번역 키보드

한국어/영어를 입력하고 상단의 일본어 후보를 눌러 원문을 교체하는 Custom Keyboard Extension입니다. 메인 앱은 활성화 안내와 설정을 제공합니다.

**현재 상태: 구현된 개발용 MVP, iOS 빌드 및 실기기 검증 대기.** Windows에서 서버·프로젝트 테스트 21개를 실행해 통과했습니다. Swift 단위 테스트 30개와 UI 테스트 2개는 작성되어 있으나 이 환경에 Swift/Xcode가 없어 실행하지 못했습니다. 출시 가능한 완성품으로 표시하지 않습니다.

Mac이 없으면 [클라우드 빌드 → Windows 설치 안내](Docs/CLOUD_IPA.md)를 사용하세요. `Build iPhone IPA` 워크플로가 키보드 확장을 포함한 미서명 iPhone용 IPA를 만듭니다. IPA 포장 검사 8개도 로컬에서 통과했습니다. GitHub에 업로드하고 워크플로가 성공해야 실제 앱 파일이 생깁니다.

## 바로 실행하기 — Mac

요구 환경: Xcode 16 이상(선택한 iOS SDK에 맞는 버전), iOS 18 이상 iPhone 또는 시뮬레이터. Swift 언어 모드는 5.0이며 Swift Concurrency를 사용합니다.

1. `KotoKeyboard.xcodeproj`를 엽니다. 별도 패키지 다운로드나 XcodeGen은 필요 없습니다.
2. `Config/Project.xcconfig`의 `APP_BUNDLE_IDENTIFIER`, `APP_GROUP_IDENTIFIER`, `KEYCHAIN_GROUP_IDENTIFIER`, `DEVELOPMENT_TEAM`을 본인 계정 값으로 바꿉니다. 현재 값은 개발용 예시입니다.
3. 앱과 확장 Target의 Signing & Capabilities에서 동일한 App Group 및 Keychain 공유 그룹을 확인합니다. 개발자 계정에 실제로 등록된 값이어야 합니다.
4. `KotoKeyboard` Scheme과 iPhone을 선택해 실행합니다.
5. 설정 → 일반 → 키보드 → 키보드 → 새 키보드 추가 → 코토 키보드.
6. 메모 앱의 지구본 키로 전환하고 `안녕하세요`를 입력합니다.
7. 약 550ms 이후 표시되는 `こんにちは`를 누릅니다. 기본값은 네트워크를 사용하지 않는 Mock입니다.

유료 개발자 계정이 없다면 `KotoKeyboard-FreeDevice` Scheme을 사용하세요. App Group과 공유 Keychain을 제외한 무료 실기기 검증 구성입니다. 자세한 순서는 [무료 계정 실기기 테스트](Docs/FREE_DEVICE_TESTING.md)에 있습니다.

문맥이 확인되지 않는 입력창에서는 `번역문만 삽입`으로 표시하며 원문을 지우지 않습니다. 문맥이 바뀌면 이전 후보는 무효화됩니다.

## 포함된 기능

- 두벌식 한글 조합, 받침·겹받침·복합 모음, 물리 자모 단계별 삭제
- 영문, 숫자·기호, 한/영, Shift, 공백, 엔터, 다음 키보드 및 숨기기
- 400~700ms debounce, 중복 억제, 작업 취소, 오래된 응답 차단
- 단일 번역 후보, 로딩·실패·권한 안내, 수동 번역 및 재시도
- 안전한 접미 구간 교체, 선택 영역 보호, 다중 Unicode scalar 문자에 대한 삽입 전용 처리
- App Group 설정 공유, 서버 토큰 Keychain 저장, 테마·VoiceOver·Dynamic Type
- 실제 API 연동용 HTTPS 클라이언트와 DeepL 중계 서버
- 입력 텍스트를 저장하지 않는 테스트 입력 화면과 별도 테스트 호스트 앱

### 번역 서비스 구분

| 서비스 | 범위 | 네트워크 |
|---|---|---|
| Mock | 안녕하세요 / 감사합니다 / hello / thank you → 일본어 | 없음 |
| 로컬 예문 | 인사·감사·사과·작별 예문 4개, 한국어·영어·일본어·중국어 | 없음 |
| 원격 | DeepL의 실제 일반 문장 번역 | 사용자 동의 + 전체 접근 + 설정한 서버 필요 |

로컬 예문은 일반 번역 모델이 아닙니다. Apple Translation은 확장 호환성 및 언어 다운로드 흐름을 이 환경에서 확인할 수 없어 탑재하지 않았습니다. 원격 실패 시 임의로 Mock 결과를 반환하지 않습니다.

## 검증 명령

Windows/macOS, Node 22 이상:

```sh
node --test Server/relay.test.mjs Scripts/project.test.mjs
```

Mac, 순수 Swift 코어:

```sh
swift test
```

Mac, 앱+확장 빌드:

```sh
xcodebuild -project KotoKeyboard.xcodeproj -scheme KotoKeyboard \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

시뮬레이터 검사까지 실행하려면 `xcrun simctl list devices available`에서 iOS 18 이상 iPhone UDID를 선택합니다.

```sh
SIMULATOR='platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' bash Scripts/verify-macos.sh
```

스크립트는 빌드/테스트 실패 시 중단하며 `artifacts/`에 결과를 남깁니다. 시뮬레이터를 지정하지 않으면 UI 테스트를 생략하고 종료 코드 2로 미완료를 알립니다. GitHub Actions 파일도 포함되어 있지만 원격 저장소 연결이나 CI 실행은 이번 작업에서 수행하지 않았습니다.

## 구조

```text
App/                    SwiftUI 온보딩·설정·사용법·입력 테스트
KeyboardExtension/      UIInputViewController·키 배열·프록시 어댑터
Shared/Core/            조합·입력·안전 삭제·번역 상태·서비스·설정
Shared/Platform/        App Group·Keychain·서비스 선택
Shared/Resources/       개인정보 매니페스트
Config/                 식별자·서명 설정·entitlements
Tests/Core/             Swift 단위 테스트 30개
UITests/                메인 앱 UI 테스트 2개
TestHost/               다양한 텍스트 입력창을 가진 검증용 앱
Server/                 인증·제한·취소가 있는 DeepL 중계 서버
Scripts/                프로젝트 생성·구조 검사·Mac 검증
Docs/                   설계·검증 상태·수동 검사·출시 점검
```

공통 코드를 최상위 `Shared`로 분리하여 앱과 확장이 같은 구현을 빌드합니다. `Package.swift`는 UIKit 없이 코어만 테스트하는 용도이며, Xcode Target은 동일한 Swift 파일을 직접 포함합니다.

Swift 파일을 추가/삭제하면 `node Scripts/generate-project.mjs`로 프로젝트를 재생성합니다. 생성기는 프로젝트 파일을 결정적으로 다시 쓰므로 Xcode에서 직접 바꾼 프로젝트 설정은 생성기에도 반영해야 합니다. 제품 식별자와 서명은 보존되는 `Config/Project.xcconfig`에서 수정합니다.

## 상세 문서

- [완료조건별 검증 결과](Docs/VALIDATION.md)
- [무료 계정 실기기 테스트](Docs/FREE_DEVICE_TESTING.md)
- [수동 테스트 및 출시 점검](Docs/MANUAL_TESTS.md)
- [아키텍처·제약·설계 결정](Docs/ARCHITECTURE.md)
- [서버 실행과 실제 API 연동](Server/README.md)

현재 남은 외부 의존성은 Mac/Xcode 검증, Apple 서명 계정, 실제 번역 서버와 제공자 계정, 출시용 브랜드·정책·문의 정보입니다.
