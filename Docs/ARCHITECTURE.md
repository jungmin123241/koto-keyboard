# 설계 및 확인된 한계

## 책임 분리

`KeyboardViewController`는 키 입력 및 UI만 조율합니다. 실제 입력창 접근은 `TextDocumentProxyAdapter`, 자모 조합은 `HangulComposer`, 삭제는 `DeletionStrategy`, 번역 비동기 처리는 `TranslationCoordinator`가 담당합니다. 메인 앱은 SwiftUI, 키보드는 UIKit을 사용합니다. 앱과 확장은 공통 Swift 소스를 각 프로세스에서 빌드합니다.

번역 모델은 `TranslationResult`, 상태는 idle/translating/translated/empty/failed이며 `MainActor`에서 갱신합니다. 서비스는 Sendable 프로토콜로 주입됩니다. 후보가 현재 하나이지만 UI와 결과 타입이 입력 로직과 분리되어 있어 추후 후보 목록으로 확장할 수 있습니다.

## 현재 입력만 번역

전체 문서를 읽어 자동 전송하지 않습니다. 이번 키보드 세션에서 입력한 최대 500자의 마지막 문장만 메모리에 둡니다. 제공되는 프록시 문맥은 소유 구간 확인에 사용합니다. 엔터·입력창 변경·키보드 종료·설정 변경은 상태와 작업을 초기화합니다. 문장부호 후 다음 문장을 시작하면 이전 문장은 번역 대상에서 제외됩니다. 약어·소수점의 고급 문장 경계 판별은 후속 개선 대상입니다.

550ms 기본 debounce(400~700ms 설정), 동일 정규화 텍스트·언어 중복 억제, Task 취소, 세대 번호 검증을 함께 사용합니다. 공백만 바뀌면 번역 결과를 재사용하되 삭제용 문맥은 최신으로 갱신합니다. 실패 시 재시도를 허용합니다. 긴 문맥을 가진 입력창을 열었다는 이유만으로 요청하지 않습니다. 현재 미완성 한글 자모, 문자 없는 입력, 한 글자 ASCII 입력은 번역하지 않습니다.

## 교체 안전성

요청 당시 문서 식별자·앞뒤 문맥·선택 영역을 보관합니다. 후보 적용 직전 상태가 달라지면 거부합니다. 원문이 현재 커서 바로 앞에 있고 UTF-16 코드 단위까지 일치하는지 확인합니다. Swift의 정규화 동등성만으로 삭제하지 않습니다.

단일 scalar로 이루어진 문자는 grapheme 단위로 하나씩 삭제하고 매 단계 문맥을 비교합니다. UTF-16 길이를 삭제 호출 수로 쓰지 않습니다. 결합 악센트·가족 이모지·국기·분해 한글처럼 여러 scalar로 이루어진 문자가 있으면 삭제하지 않고, UI에 ‘번역문만 삽입’을 표시합니다. 선택 영역이 있으면 삽입도 거부합니다. 문맥이 nil일 때에는 직접 입력한 구간의 후보만 삽입할 수 있습니다.

삭제 도중 호스트가 예상과 다르게 동작하면 즉시 멈추고 사용자 확인을 안내합니다. 프록시에는 원자적 교체/rollback API가 없으므로 이미 수행된 부분 삭제를 자동 복구하지 않습니다. 매우 긴 문서에서 문맥 창이 이동하는 경우도 안전하게 중단될 수 있습니다. 이 동작은 실기기 앱별 검증이 필요합니다.

정확한 절대 커서 좌표는 알 수 없습니다. 문서 식별자·주변 문맥을 사용하므로 동일한 문맥이 반복되는 위치 이동을 완벽하게 구분할 수 없다는 플랫폼 한계가 있습니다.

## iOS 기능과 권한

- `UIInputViewController`와 `textDocumentProxy`를 사용합니다. Apple 시스템 키보드를 수정하지 않습니다.
- 보안 입력창과 phonePad/namePhonePad는 시스템 키보드로 전환됩니다. 번역 요청도 입력 특성으로 추가 차단합니다.
- 앱이 서드파티 키보드를 거부할 수 있어 모든 앱 지원을 보장하지 않습니다.
- `RequestsOpenAccess=true`는 사용자가 허용할 수 있도록 선언하는 것이며 권한 자체가 아닙니다. 실제 요청 전 `hasFullAccess`를 확인합니다.
- 전체 접근 없이 기본 입력과 Mock/로컬 예문이 동작하도록 합니다. 공유 설정 읽기가 불가능하면 안전한 기본값을 사용합니다. 확장 쪽 공유 저장소 쓰기는 전체 접근 때만 수행합니다.
- 설정 이동은 메인 앱의 공개 `UIApplication.openSettingsURLString`만 사용합니다.
- Wi-Fi 전용 설정은 NWPathMonitor의 Wi-Fi 확인과 URLSession의 셀룰러·비싼 연결 차단을 함께 적용합니다.
- 키보드 Dynamic Type은 제한된 높이 안에서 최대 폰트 크기를 두고 행 높이를 늘립니다. 실기기 접근성 검증이 남아 있습니다.

근거: [Apple 커스텀 키보드](https://developer.apple.com/documentation/uikit/configuring-a-custom-keyboard-interface), [전체 접근](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard), [텍스트 프록시](https://developer.apple.com/documentation/uikit/uitextdocumentproxy).

## Apple Translation 검토

[Translation 프레임워크](https://developer.apple.com/documentation/Translation)는 번역 세션과 언어 가용성·다운로드를 관리합니다. [설치된 언어용 세션 생성 API](https://developer.apple.com/documentation/translation/translationsession/init(installedsource:target:))도 있으나 타깃 SDK의 정확한 가용성과 키보드 확장 sandbox에서의 실제 동작을 검증해야 합니다.

현재 Windows 환경에서는 해당 검증을 수행할 수 없어 Apple 구현을 사용 가능한 서비스로 노출하지 않았습니다. 요구사항의 대안인 로컬 예문 구현과 실제 원격 서비스가 제공됩니다. 이후 Mac 실기기에서 검증한 뒤 factory에 Apple 서비스를 추가하고, 모델 다운로드는 메인 앱에서 처리해야 합니다. 로컬 실패를 원격 전송으로 조용히 전환하지 않습니다.

## 다음 단계의 범위

고급 한글 조합 및 커서 편집, 자동 띄어쓰기, 일반 온디바이스 번역, 여러 후보, 가로 화면 최적화는 포함하지 않았습니다. 영구 입력 이력은 개인정보 요구사항과 충돌하므로 도입하지 않습니다. 문의 URL·법적 운영 주체·앱 아이콘은 실제 출시 정보가 필요합니다.
