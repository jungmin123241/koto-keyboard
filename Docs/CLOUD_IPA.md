# 클라우드 Mac에서 빌드하고 Windows에서 설치하기

저장소: https://github.com/jungmin123241/koto-keyboard

이 경로는 GitHub의 macOS 러너에서 **실제 iPhone용 미서명 앱**을 빌드하고, Windows의 Sideloadly에서 무료 Apple 계정으로 서명하여 USB로 설치하는 방식입니다. Apple이 제공하는 직접 설치 절차는 아니며, 이 앱의 실제 설치·키보드 실행 성공은 아직 검증하지 않았습니다.

## 1. GitHub에 프로젝트 업로드

이 폴더의 소스와 숨김 폴더 `.github`를 함께 올립니다. `.env`, API 키, Apple 비밀번호, 인증서, provisioning profile은 올리지 않습니다. 비공개 저장소를 유지해도 됩니다. Git 인증이 요구되면 Git Credential Manager의 GitHub 로그인 화면에서 직접 인증합니다.

## 2. 클라우드 빌드 실행

1. 저장소의 **Actions** 탭을 엽니다.
2. **Build iPhone IPA**를 선택합니다.
3. **Run workflow**에서 업로드한 브랜치를 선택하고 실행합니다.
4. main/master에 소스를 push해도 자동 실행됩니다.

Apple 계정·GitHub Secrets·유료 개발자 인증서는 사용하지 않습니다. 별도의 `iOS and relay verification` 워크플로는 시뮬레이터/UI 검증용이며 IPA는 생성하지 않습니다.

빌드 순서: Node 및 포장 테스트 → Swift 단위 테스트 → FreeDevice/iphoneos/arm64 빌드 → 앱과 키보드 확장 검사 → IPA 포장. 오류가 있으면 결과 파일 생성이 중단됩니다. 실패한 단계의 로그 또는 `ipa-build-logs` artifact로 원인을 확인합니다.

## 3. IPA 다운로드

성공한 실행 페이지 아래의 **Artifacts → KotoKeyboard-FreeDevice-unsigned**를 다운로드합니다. GitHub가 제공하는 ZIP을 Windows에서 한 번 풉니다.

- `KotoKeyboard-FreeDevice-unsigned.ipa`: Sideloadly에 넣을 파일
- `KotoKeyboard-FreeDevice-unsigned.ipa.sha256`: 파일 무결성 확인용 해시

IPA 자체를 다시 풀 필요는 없습니다. 파일을 iPhone의 파일 앱으로 보내서 누르는 것만으로는 설치되지 않습니다. Artifact는 저장소 용량 사용을 줄이기 위해 3일 보관합니다. 만료되면 빌드를 다시 실행합니다.

## 4. Windows에서 서명하고 설치

1. https://sideloadly.io/ 에서 Windows용 프로그램과 안내된 Apple 연결 구성요소를 설치합니다.
2. iPhone을 USB로 연결하고 기기의 ‘이 컴퓨터를 신뢰’를 승인합니다.
3. Sideloadly에 내려받은 IPA를 넣고 연결된 iPhone을 선택합니다.
4. 무료 Apple 계정 로그인과 2단계 인증은 본인이 프로그램에서 직접 진행합니다. 대화나 GitHub에 인증 정보를 입력하지 않습니다.
5. **Remove extensions / Remove PlugIns 옵션은 사용하지 않습니다.** 키보드 확장이 제거되면 앱만 설치되고 키보드가 나타나지 않습니다.
6. 설치를 실행하고, iPhone에서 필요에 따라 개발자 모드 및 개발자 신뢰를 설정합니다.
7. 메인 앱을 한 번 연 뒤 설정 → 일반 → 키보드 → 키보드 → 새 키보드 추가 → 코토 키보드로 추가합니다.

iOS 18 이상이 필요합니다. 무료 계정의 앱 수·App ID 제한과 7일 서명 만료가 적용되며, 앱 확장에도 App ID가 필요할 수 있습니다. 같은 IPA를 PC에서 다시 서명할 수 있으므로 서명 갱신만을 위해 클라우드 빌드를 반복할 필요는 없습니다. 자동 갱신을 사용하면 PC와 iPhone이 연결 가능한 상태여야 합니다.

## 설치본의 범위

현재 `FreeDevice`는 Mock 일본어 후보와 기본 입력·교체 확인용입니다. `안녕하세요`, `감사합니다`, `hello`, `thank you`를 입력해 보세요. 일반 문장 번역 서비스나 App Group 설정 공유가 활성화되는 것은 아닙니다.

빌드 완료와 실기기 설치 성공은 다릅니다. 키보드가 설치 목록에 없거나 서명 오류가 발생하면 앱과 확장 양쪽의 재서명, 확장 보존, 사용 가능한 App ID를 확인해야 합니다.

## 비용과 출처

GitHub의 비공개 저장소는 계정별 무료 Actions 할당량을 사용하며, 초과 사용 시 요금 또는 실행 제한이 발생할 수 있습니다. 비용을 피하려고 저장소를 공개할 필요는 없습니다. 먼저 Billing의 Actions 사용량과 예산을 확인합니다.

- GitHub 러너: https://docs.github.com/en/actions/reference/runners/github-hosted-runners
- GitHub 사용량: https://docs.github.com/en/billing/concepts/product-billing/github-actions
- Sideloadly 설치/갱신: https://sideloadly.io/faq
- 무료 계정 제한: https://developer.apple.com/help/account/basics/about-your-developer-account
