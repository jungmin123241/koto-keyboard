import SwiftUI
import UIKit

@main
struct TestHostApp: App {
    var body: some Scene { WindowGroup { TestFieldsView() } }
}

struct TestFieldsView: View {
    @State private var single = ""
    @State private var multiline = ""
    @State private var secure = ""
    @State private var phone = ""
    @State private var email = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("일반 입력", text: $single).accessibilityIdentifier("plainField")
                TextEditor(text: $multiline).frame(height: 150).accessibilityIdentifier("multilineField")
                SecureField("보안 입력", text: $secure).accessibilityIdentifier("secureField")
                TextField("전화번호", text: $phone).keyboardType(.phonePad)
                TextField("이메일", text: $email).keyboardType(.emailAddress)
                Button("긴 문맥 넣기") { multiline = String(repeating: "기존 문서는 자동 전송하지 않습니다. ", count: 100) }
                Button("초기화") { single = ""; multiline = ""; secure = ""; phone = ""; email = "" }
            }.navigationTitle("Keyboard Test Host")
        }
    }
}
