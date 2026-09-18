import SwiftUI
import UIKit

struct HomeView: View {
    @State private var settings = SharedConfiguration.store().load()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "character.bubble.ja").font(.largeTitle).foregroundStyle(.indigo)
                        Text("입력하는 순간,\n일본어로 이어지는 대화.")
                            .font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                        Text("키보드로 입력한 내용을 일본어로 바로 번역하세요")
                            .foregroundStyle(.secondary)
                    }.padding(.vertical)
                    NavigationLink("키보드 활성화하기") { KeyboardSetupView() }
                        .accessibilityIdentifier("setupLink")
                    NavigationLink("사용 방법") { UsageView() }
                }
                Section("나의 키보드") {
                    NavigationLink("번역 및 키보드 설정") { SettingsView(settings: $settings) }
                        .accessibilityIdentifier("settingsLink")
                    NavigationLink("입력 테스트") { InputTestView() }
                    Label("기본 입력은 전체 접근 권한 없이 작동합니다", systemImage: "keyboard")
                    Label("현재 기본값은 Mock 예제 번역입니다", systemImage: "hammer")
                        .font(.footnote)
                    #if FREE_DEVICE_BUILD
                    Label("무료 실기기 구성: 앱 설정 공유와 서버 번역은 사용할 수 없습니다", systemImage: "iphone.gen3")
                        .font(.footnote).foregroundStyle(.orange)
                    #endif
                }
                Section("개인정보와 도움말") {
                    Text("입력 원문과 번역문은 앱에 저장하지 않습니다. 네트워크 번역을 켜면 현재 입력한 구간을 설정한 서버와 번역 제공자에 전송합니다.")
                    NavigationLink("개인정보 처리 안내") { PolicyView(kind: .privacy) }
                    NavigationLink("이용 안내") { PolicyView(kind: .terms) }
                    NavigationLink("문제 해결 및 앱 정보") { HelpView() }
                }
            }
            .navigationTitle("코토 키보드")
        }
        .preferredColorScheme(settings.theme == .dark ? .dark : settings.theme == .light ? .light : nil)
        .onChange(of: settings) { _, value in SharedConfiguration.store().save(value) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { settings = SharedConfiguration.store().load() } }
    }
}

struct KeyboardSetupView: View {
    private let steps = ["설정 앱을 엽니다", "일반 → 키보드 → 키보드를 선택합니다", "새 키보드 추가를 누릅니다",
                         "코토 키보드를 선택합니다", "네트워크 번역을 쓸 경우에만 전체 접근 허용을 켭니다", "입력창에서 지구본 키를 길게 눌러 코토 키보드를 선택합니다"]
    var body: some View {
        List {
            Section("설정 순서") {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    Label(step, systemImage: "\(index + 1).circle")
                }
            }
            Section {
                Button("설정 앱 열기") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }.accessibilityIdentifier("openSettings")
                Text("앱 설정이 열립니다. 키보드 메뉴가 없다면 위 순서로 직접 이동하세요.")
                Text("전체 접근은 서버 통신에 필요합니다. 예제 번역과 기본 입력에는 필요하지 않습니다. 활성화 여부는 실제 입력창에서 확인하세요.")
            }
        }.navigationTitle("키보드 활성화")
    }
}

struct UsageView: View {
    var body: some View {
        List {
            Text("1. 메모 앱에서 코토 키보드로 ‘안녕하세요’를 입력하세요.")
            Text("2. 잠시 후 상단에 ‘こんにちは’ 후보가 나타납니다.")
            Text("3. 후보를 탭하면 원문을 일본어로 바꿉니다.")
            Text("‘번역문만 삽입’이 표시되면 원문은 남고 번역문만 추가됩니다. 커서를 옮기면 이전 후보는 사라집니다.")
            Text("Mock은 안녕하세요, 감사합니다, hello, thank you만 일본어로 바꿉니다. 오프라인 예문은 인사·감사·사과·작별 예문만 지원합니다. 일반 문장에는 네트워크 번역 서버가 필요합니다.")
            Text("자동 번역을 끄면 입력 후 후보 영역의 ‘탭하여 번역’을 눌러 요청하세요.")
        }.navigationTitle("사용 방법")
    }
}

struct SettingsView: View {
    @Binding var settings: KeyboardSettings
    @State private var token = ""
    @State private var savedMessage = ""
    var body: some View {
        Form {
            Section("번역") {
                Toggle("번역 사용", isOn: $settings.translationEnabled).accessibilityIdentifier("translationToggle")
                Picker("목표 언어", selection: $settings.targetLanguage) {
                    Text("일본어").tag("ja"); Text("한국어").tag("ko"); Text("영어").tag("en"); Text("중국어").tag("zh")
                }
                Toggle("자동 번역", isOn: $settings.automaticTranslation)
                Stepper("입력 후 \(settings.delayMilliseconds)ms", value: $settings.delayMilliseconds, in: 400...700, step: 50)
                Picker("번역 서비스", selection: $settings.service) {
                    Text("Mock · 개발 예제").tag(ServiceKind.mock)
                    Text("오프라인 · 예문 4개").tag(ServiceKind.local)
                    #if !FREE_DEVICE_BUILD
                    Text("네트워크 · 개인 서버").tag(ServiceKind.remote)
                    #endif
                }
                Toggle("Wi-Fi에서만 번역", isOn: $settings.wifiOnly)
                Text("입력 언어는 자동 감지합니다. Apple 기기 내 일반 번역은 확장 호환성 검증 전까지 제공하지 않습니다.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            #if FREE_DEVICE_BUILD
            Section("무료 실기기 구성") {
                Text("키보드 확장과 메인 앱이 설정을 공유하지 않습니다. 키보드는 Mock 기본값으로 실행됩니다. 실제 서버 번역과 App Group 검증은 유료 개발자 구성에서 확인하세요.")
                    .font(.footnote)
            }
            #endif
            #if !FREE_DEVICE_BUILD
            if settings.service == .remote {
                Section("네트워크 번역 연결") {
                    TextField("https://서버주소/v1/translate", text: $settings.remoteEndpoint)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("서버 접근 토큰", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("접근 토큰 저장") {
                        savedMessage = TokenStore.save(token.trimmingCharacters(in: .whitespacesAndNewlines)) ? "저장했습니다." : "저장 실패: 서명과 Keychain 공유 설정을 확인하세요."
                        token = ""
                    }
                    Button("저장된 토큰 삭제", role: .destructive) { savedMessage = TokenStore.save("") ? "삭제했습니다." : "삭제하지 못했습니다." }
                    if !savedMessage.isEmpty { Text(savedMessage).font(.footnote) }
                    Toggle("현재 입력 구간을 서버에 전송하는 데 동의", isOn: $settings.networkConsent)
                    Text("서버가 번역 제공자에 입력을 전달합니다. 서버 운영자와 제공자의 데이터 보관 정책을 확인하세요. API 키는 앱에 입력하지 않습니다.")
                        .font(.footnote)
                }
            }
            #endif
            Section("키보드 모양") {
                Toggle("진동 피드백", isOn: $settings.hapticFeedback)
                Text("진동은 권한과 기기 지원 여부에 따라 작동하지 않을 수 있습니다.").font(.footnote)
                Picker("화면 모드", selection: $settings.theme) {
                    Text("시스템 설정").tag(KeyboardTheme.system)
                    Text("라이트").tag(KeyboardTheme.light)
                    Text("다크").tag(KeyboardTheme.dark)
                }
            }
            Section {
                NavigationLink("개인정보 처리방침") { PolicyView(kind: .privacy) }
                NavigationLink("이용약관") { PolicyView(kind: .terms) }
                NavigationLink("문의하기") { HelpView() }
            }
        }
        .navigationTitle("설정")
        .onChange(of: settings.remoteEndpoint) { _, _ in settings.networkConsent = false }
        .onDisappear { token = "" }
    }
}

struct InputTestView: View {
    @State private var text = ""
    @State private var password = ""
    @State private var phone = ""
    var body: some View {
        Form {
            Section("기본 입력") {
                TextEditor(text: $text).frame(minHeight: 160).accessibilityLabel("키보드 테스트 입력창")
                Text("이 화면의 텍스트는 저장하지 않습니다.").font(.footnote)
            }
            Section("시스템 키보드 전환 확인") {
                SecureField("테스트용 보안 입력", text: $password)
                TextField("테스트용 전화번호", text: $phone).keyboardType(.phonePad)
            }
        }.navigationTitle("입력 테스트")
            .onDisappear { text = ""; password = ""; phone = "" }
    }
}

enum PolicyKind { case privacy, terms }
struct PolicyView: View {
    let kind: PolicyKind
    var body: some View {
        List {
            if kind == .privacy {
                Text("앱과 키보드는 원문·번역문을 파일, 사용자 설정, 로그에 기록하지 않습니다. 입력 구간과 번역 후보는 실행 중 메모리에만 유지하며 입력창 전환과 키보드 종료 시 비웁니다.")
                Text("설정과 오류 코드는 App Group에, 서버 접근 토큰은 이 기기의 Keychain에 저장합니다. 토큰은 설정에서 삭제할 수 있습니다.")
                Text("네트워크 번역은 동의와 전체 접근 권한이 있을 때 작동합니다. 원문·입력 언어(자동 감지 시 생략)·목표 언어를 개인 서버로 보내며, 서버는 번역 제공자에 전달합니다. 응답은 캐시에 보관하지 않습니다.")
                Text("동봉된 서버는 요청 본문을 저장하지 않습니다. 실제 서버의 프록시·호스팅 로그와 번역 제공자 보관 정책은 운영자가 별도로 확인해야 합니다.")
                Text("개발 버전 안내입니다. 배포 전 운영자 정보, 문의 주소, 실제 제공자 정책을 반영한 공개 개인정보 처리방침이 필요합니다.")
            } else {
                Text("번역 결과에는 오류가 있을 수 있습니다. 후보를 확인하고 입력하세요.")
                Text("이 개발 버전의 Mock과 오프라인 예문은 일반 문장 번역 기능이 아닙니다. 네트워크 서비스의 이용 조건과 비용은 해당 서버 운영 정책을 따릅니다.")
                Text("배포 전 운영 주체와 이용 조건을 확정해야 합니다.")
            }
        }.navigationTitle(kind == .privacy ? "개인정보 처리 안내" : "이용 안내")
    }
}

struct HelpView: View {
    var body: some View {
        List {
            Text("후보가 없나요? 번역 ON, 자동 번역, 선택한 서비스의 지원 문장, 네트워크 동의, 전체 접근 권한을 확인하세요.")
            Text("키보드가 보이지 않나요? 일부 앱과 보안·전화번호 입력창은 시스템 키보드만 허용합니다.")
            Text("교체가 중단됐나요? 입력창 문맥이 달라지거나 일부 문자 삭제를 확인하지 못하면 추가 삭제를 중단합니다. 원문을 확인하고 다시 입력하세요.")
            Text("서버 오류가 있어도 기본 입력은 계속 사용할 수 있습니다.")
            Text("코토 키보드 · 개발 버전 0.1.2 (빌드 3)")
            Text("문의 채널은 출시 전 등록 예정입니다. 현재는 프로젝트 관리자에게 재현 단계와 오류 코드만 전달하세요. 입력 원문이나 접근 토큰은 포함하지 마세요.")
        }.navigationTitle("도움말")
    }
}
