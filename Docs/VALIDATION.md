# 구현 및 완료조건 검증 결과

기록일: 2026-09-18. 실행 환경: Windows, Node v24.19.0. 기존 저장소는 `.git`만 있었으며 수정할 기존 소스는 없었습니다. 원본 `PRODUCT_SPEC.md`는 변경하지 않았습니다.

## 실제 실행 결과

| 검사 | 결과 | 범위 |
|---|---|---|
| `node --test Server/relay.test.mjs Scripts/project.test.mjs` | **21/21 통과** | 로컬 HTTP 서버, 가짜 제공자, 프로젝트 객체 모델 |
| `python -m unittest discover -s Scripts -p 'test_*.py' -v` | **8/8 통과** | 합성 Mach-O/앱 fixture로 IPA 포장·확장 누락·시뮬레이터 차단 검사 |
| `node --check Server/server.mjs` | 통과 | JavaScript 구문 |
| `node --check Scripts/generate-project.mjs` | 통과 | 생성기 구문 |
| 프로젝트 연속 재생성 후 SHA-256 비교 | 동일 | 결정적 프로젝트 생성 확인 |
| plist/entitlements/xcprivacy/xcscheme XML 파싱 | 6개 통과 | XML 문법; Apple 의미 검증은 아님 |
| 입력 로그/저장 코드 검색 및 검토 | 직접 입력·번역 출력 코드 없음 | 서버에는 고정된 시작 오류 문구만 존재 |
| Swift/Xcode 도구 확인 | 미설치 | `swift`, `xcodebuild` 없음, WSL 배포판 없음 |
| Swift 단위 테스트 30개 | **실행 불가** | 컴파일러 필요 |
| Xcode UI 테스트 2개 | **실행 불가** | Mac/Xcode/시뮬레이터 필요 |
| 앱·확장 컴파일/실기기 검사 | **실행 불가** | Mac/Xcode 및 서명 환경 필요 |
| 실제 DeepL 호출 | **미실행** | API 키·서버·사용자 토큰 없음 |

처음 Node 테스트는 샌드박스의 자식 프로세스 생성 제한(EPERM)으로 실행되지 않았습니다. 허용된 재실행에서는 21개 모두 통과했습니다. 이를 테스트 실패 수정으로 오인하지 않습니다. iOS 컴파일을 실행하지 않았으므로 **컴파일 오류가 없다고 확인한 것은 아닙니다**.

## 요구 완료조건별 판정

| 완료조건 | 구현/근거 | 최종 판정 |
|---|---|---|
| 메인 앱과 키보드 확장 모두 빌드 | 두 Target과 Embed App Extensions 설정 생성 | 미검증 — Mac 필요 |
| iPhone 키보드에 추가 가능 | 키보드 extension point/PrincipalClass/활성화 안내 | 미검증 — 설치 필요 |
| 키보드 텍스트 입력 | 두벌식 한글, 영문, 기호, 공백, 삭제, 엔터 | 구현됨, 실기기 미검증 |
| 일본어 번역 후보 표시 | Mock/로컬 예문/실제 원격 인터페이스, 후보 UI | 구현됨, iOS 미검증 |
| 후보 탭 시 삽입 | 접미 검증·단계별 삭제·삽입 전용·중복 적용 차단 | 구현됨, Swift/실기기 미검증 |
| 네트워크 실패에도 기본 입력 유지 | 입력 엔진과 비동기 서비스 분리 | 서버 오류/취소 테스트 통과, iOS 미검증 |
| 비밀번호 필드 번역 비활성화 | 시스템 전환 + 입력 특성 요청 차단 | 실기기 미검증 |
| 중복 요청/오래된 결과 방지 | 정규화 키·Task 취소·세대 확인 | Swift 테스트 작성, 미실행 |
| 원문 로그/디스크 비저장 | 메모리 입력 상태, 설정/오류 코드만 저장, 서버 무본문 로그 | 코드 검토 완료, 운영 환경 점검 필요 |
| 다크 모드/기본 접근성 | 테마, 폰트 크기, 후보 label/value/hint | 구현됨, 시각/VoiceOver 미검증 |
| 테스트 또는 수동 테스트 문서 | 단위/UI/서버/구조 테스트 및 MANUAL_TESTS.md | 문서화 완료, 일부 자동 검사 통과 |
| 실제 API 환경변수/서버 문서 | Server/.env.example, Server/README.md | 문서화 및 어댑터 테스트 완료 |

**전체 완료 판정: 보류.** 소스와 개발용 실행 구성을 작성했지만, iOS 컴파일 및 실기기 조건을 충족했다고 주장하지 않습니다.

## 이번 검토에서 반영한 수정

- Package의 iOS 배포 버전을 문자열로 선언해 manifest API 버전 종속성 완화
- 504/408 응답을 타임아웃으로 분류
- 결합 문자·문맥 변화·선택 영역에 대해 원문 삭제 제한
- 동일 문장 뒤 공백 추가 시 중복 번역 억제 및 교체 문맥 갱신
- 미완성 한글 자모·너무 짧은 ASCII 입력 제외
- 마지막 입력 문장만 번역하도록 세션 구간 제한
- Dynamic Type 키/후보 크기를 키보드 높이에 맞춰 제한
- 원격 클라이언트/제공자 리디렉션 거부
- iOS/macOS 클라이언트는 응답을 스트리밍으로 읽어 64KB를 넘으면 중단
- 잘못된 JSON·언어·추가 필드·과대 요청·제공자 과대 응답 검증
- 무료 Personal Team용 `FreeDevice` 구성 추가: App Group·공유 Keychain 제외, Mock 실기기 흐름 유지
- `Build iPhone IPA` 워크플로 및 미서명 arm64 IPA 포장 추가. 클라우드 실행은 GitHub 인증·업로드 후 필요
- FreeDevice의 Profile/Archive도 동일한 구성 사용, standard UserDefaults용 개인정보 사유 추가
- MainActor XCTest를 비동기 진입점으로 통일해 테스트 실행기가 actor로 전환할 수 있도록 수정

## 주요 변경 파일

- 앱: `App/AppEntry/KotoKeyboardApp.swift`, `App/Features/HomeView.swift`
- 키보드: `KeyboardExtension/KeyboardViewController.swift`, `Input/TextDocumentProxyAdapter.swift`, `UI/KeyboardLayout.swift`
- 공통: `Shared/Core/{HangulComposer,DocumentEditing,Translation,TranslationCoordinator,Settings}.swift`, `Shared/Platform/SharedConfiguration.swift`
- 프로젝트: `KotoKeyboard.xcodeproj`, `Package.swift`, `Config/`, 각 Info.plist, `Shared/Resources/PrivacyInfo.xcprivacy`
- 검증: `Tests/Core/`, `UITests/`, `TestHost/`, `Scripts/`, `.github/workflows/ios.yml`
- 서버: `Server/server.mjs`, `relay.test.mjs`, `.env.example`, `package.json`
- 문서: `README.md`, `Docs/`, `Server/README.md`

## 이어서 실행할 작업

1. Mac에서 `swift test`를 실행하고 실제 Swift 컴파일/테스트 실패를 수정합니다.
2. `Scripts/verify-macos.sh`로 앱·확장 빌드와 XCTest를 실행합니다.
3. 개발자 팀/식별자 설정 후 실기기 수동 테스트를 수행합니다.
4. 실제 서버와 API 계정으로 일반 문장 번역을 검증합니다.
5. `MANUAL_TESTS.md`의 출시 차단 항목을 완료합니다.

앱 아이콘, 실제 문의 채널/정책, 공용 서비스용 사용자 인증은 아직 출시 수준으로 완료되지 않았습니다. Apple 온디바이스 일반 번역과 고급 입력 기능은 후속 범위입니다.
