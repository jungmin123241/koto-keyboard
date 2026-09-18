import UIKit
import Network

@MainActor
final class KeyboardViewController: UIInputViewController {
    private lazy var document = TextDocumentProxyAdapter(self)
    private let coordinator = TranslationCoordinator()
    private var settings = KeyboardSettings()
    private var input = InputState()
    private var composer = HangulComposer()
    private var knownSnapshot: DocumentSnapshot?
    private var requestSnapshot: DocumentSnapshot?
    private var requestSource = ""
    private var applying = false
    private var korean = true
    private var shifted = false
    private var symbols = false
    private var wifiAvailable = false
    private let monitor = NWPathMonitor()
    private let stack = UIStackView()
    private let keys = UIStackView()
    private let candidate = UIButton(type: .system)
    private let status = UILabel()
    private var heightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        stack.axis = .vertical; stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -4)
        ])
        status.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 12), maximumPointSize: 18)
        status.adjustsFontForContentSizeCategory = true
        status.textAlignment = .center
        status.numberOfLines = 2
        stack.addArrangedSubview(status)
        candidate.titleLabel?.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 17), maximumPointSize: 26)
        candidate.titleLabel?.adjustsFontForContentSizeCategory = true
        candidate.titleLabel?.numberOfLines = 2
        candidate.titleLabel?.lineBreakMode = .byTruncatingTail
        candidate.backgroundColor = .secondarySystemGroupedBackground
        candidate.layer.cornerRadius = 10
        candidate.heightAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
        candidate.addAction(UIAction { [weak self] _ in self?.candidateTapped() }, for: .touchUpInside)
        stack.addArrangedSubview(candidate)
        keys.axis = .vertical; keys.spacing = 6
        stack.addArrangedSubview(keys)
        heightConstraint = view.heightAnchor.constraint(equalToConstant: 340)
        heightConstraint?.priority = .defaultHigh
        heightConstraint?.isActive = true
        coordinator.onStateChange = { [weak self] state in
            self?.render(state)
            if case .failed(let error) = state {
                SharedConfiguration.store(writable: self?.hasFullAccess == true).record(error: error)
            }
        }
        monitor.pathUpdateHandler = { [weak self] path in
            let allowed = path.status == .satisfied && path.usesInterfaceType(.wifi) && !path.isExpensive
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.wifiAvailable = allowed
                if self.settings.wifiOnly && self.settings.service == .remote {
                    self.coordinator.reset()
                    self.schedule()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "keyboard.network-path"))
        reloadSettings()
        buildKeys()
        render(.idle)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadSettings()
        resetInput()
        buildKeys()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        resetInput()
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if isViewLoaded && previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            buildKeys()
        }
    }
    deinit { monitor.cancel() }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        guard isViewLoaded, !applying else { return }
        reloadSettings()
        if knownSnapshot?.matches(document) != true { resetInput() }
        if restricted { resetInput(); status.text = "이 입력창에서는 번역을 사용하지 않습니다." }
    }

    private var restricted: Bool {
        let proxy = textDocumentProxy
        return proxy.isSecureTextEntry == true || proxy.keyboardType == .phonePad || proxy.keyboardType == .namePhonePad
    }

    private func reloadSettings() {
        let next = SharedConfiguration.store(writable: false).load()
        if next != settings { settings = next; resetInput() }
        overrideUserInterfaceStyle = settings.theme == .dark ? .dark : settings.theme == .light ? .light : .unspecified
        view.backgroundColor = .systemGroupedBackground
    }

    private func resetInput() {
        composer.reset(); input.reset(); coordinator.reset()
        requestSnapshot = nil; requestSource = ""
        knownSnapshot = DocumentSnapshot(document)
    }

    private func keyButton(_ title: String, label: String? = nil, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.accessibilityLabel = label ?? title
        button.titleLabel?.font = UIFontMetrics(forTextStyle: .title3).scaledFont(for: .systemFont(ofSize: 20), maximumPointSize: 24)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.backgroundColor = .secondarySystemGroupedBackground
        button.layer.cornerRadius = 6
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.reloadSettings()
            if self.knownSnapshot?.matches(self.document) != true { self.resetInput() }
            if self.settings.hapticFeedback && self.hasFullAccess { UISelectionFeedbackGenerator().selectionChanged() }
            action()
        }, for: .touchUpInside)
        return button
    }

    private func row(_ buttons: [UIButton]) {
        let row = UIStackView(arrangedSubviews: buttons)
        row.axis = .horizontal; row.distribution = .fillEqually; row.spacing = 4
        row.heightAnchor.constraint(equalToConstant: traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? 52 : 46).isActive = true
        keys.addArrangedSubview(row)
    }

    private func buildKeys() {
        keys.arrangedSubviews.forEach { keys.removeArrangedSubview($0); $0.removeFromSuperview() }
        let rows = KeyboardLayout.rows(korean: korean, shifted: shifted, symbols: symbols)
        for (index, titles) in rows.enumerated() {
            var buttons = titles.map { title in keyButton(title) { [weak self] in self?.type(title) } }
            if index == 2 {
                buttons.insert(keyButton(shifted ? "⇧●" : "⇧", label: "대문자 또는 쌍자음 전환") { [weak self] in
                    guard let self else { return }; self.shifted.toggle(); self.buildKeys()
                }, at: 0)
                buttons.append(keyButton("⌫", label: "한 글자 삭제") { [weak self] in self?.backspace() })
            }
            row(buttons)
        }
        let globe = keyButton("🌐", label: "다음 키보드") {}
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        var bottom = [keyButton(symbols ? "ABC" : "123") { [weak self] in
            guard let self else { return }; self.composer.reset(); self.symbols.toggle(); self.buildKeys()
        }]
        if needsInputModeSwitchKey { bottom.append(globe) }
        bottom.append(keyButton(korean ? "한→영" : "영→한") { [weak self] in
            guard let self else { return }; self.composer.reset(); self.korean.toggle(); self.symbols = false; self.buildKeys()
        })
        bottom.append(keyButton("공백") { [weak self] in self?.type(" ") })
        bottom.append(keyButton("↵", label: "줄바꿈 또는 보내기") { [weak self] in self?.type("\n") })
        bottom.append(keyButton("⌄", label: "키보드 숨기기") { [weak self] in self?.dismissKeyboard() })
        row(bottom)
        heightConstraint?.constant = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? 400 : 340
    }

    private func type(_ value: String) {
        guard !applying else { return }
        applying = true
        defer { applying = false; knownSnapshot = DocumentSnapshot(document); schedule() }
        if value == "\n" {
            document.insertText(value); composer.reset(); input.reset(); return
        }
        if korean && !symbols && value.count == 1 && !value.trimmingCharacters(in: .whitespaces).isEmpty {
            if composer.text.count >= 40 { composer.reset() }
            let old = composer.text
            composer.append(value.first!)
            if !replaceComposition(old: old, new: composer.text) {
                composer.reset(); input.reset(); document.insertText(value); input.set(value)
            }
        } else {
            composer.reset(); document.insertText(value); input.set(input.typed + value)
        }
        if shifted { shifted = false; buildKeys() }
    }

    private func replaceComposition(old: String, new: String) -> Bool {
        // This is an owned, actively composing run. Replacing the whole run is
        // more reliable than asking the host to delete only a changed suffix:
        // documentContextBeforeInput can briefly lag behind insertText on iOS.
        // Falling back to insertText in that window would expose raw jamo.
        if !old.isEmpty, let before = document.before,
           !DocumentSnapshot.exact(String(before.suffix(old.count)), old) {
            return false
        }
        for _ in old { document.deleteBackward() }
        document.insertText(new)
        let base = old.isEmpty ? input.typed : String(input.typed.dropLast(old.count))
        input.set(base + new)
        return true
    }

    private func backspace() {
        applying = true
        if !composer.isEmpty {
            let old = composer.text
            composer.backspace()
            if !replaceComposition(old: old, new: composer.text) { composer.reset(); input.reset() }
        } else {
            document.deleteBackward()
            input.set(input.typed.isEmpty ? "" : String(input.typed.dropLast()))
        }
        applying = false
        knownSnapshot = DocumentSnapshot(document)
        schedule()
    }

    private func schedule(force: Bool = false) {
        guard settings.translationEnabled, !restricted else { coordinator.reset(); render(.idle); return }
        guard !input.candidate.isEmpty else { coordinator.reset(); render(.empty); return }
        if let before = document.before, !before.hasSuffix(input.typed) {
            // A host autocorrection or external edit invalidated our owned segment.
            resetInput(); return
        }
        guard settings.automaticTranslation || force else { coordinator.reset(); render(.idle); return }
        if settings.service == .remote && settings.wifiOnly && !wifiAvailable {
            coordinator.reset(); status.text = "Wi-Fi 연결을 기다리는 중 · 기본 입력 가능"; return
        }
        do {
            let service = try TranslationServiceFactory.make(settings: settings, fullAccess: hasFullAccess)
            requestSnapshot = DocumentSnapshot(document)
            requestSource = input.typed
            coordinator.request(text: input.candidate, target: settings.targetLanguage, contextVersion: input.version,
                                delayMilliseconds: force ? 0 : settings.delayMilliseconds, service: service, force: force)
        } catch {
            coordinator.reset()
            render(.failed((error as? TranslationError) ?? .configuration))
        }
    }

    private func render(_ state: TranslationState) {
        let mode = settings.service == .remote ? "네트워크 번역" : settings.service == .mock ? "Mock · 예제 문장만 지원" : "오프라인 · 예문 4개만 지원"
        status.text = settings.translationEnabled ? mode : "번역 꺼짐 · 기본 입력 가능"
        candidate.accessibilityValue = nil
        candidate.accessibilityLabel = "번역"
        candidate.accessibilityHint = "탭하여 번역 요청"
        candidate.isEnabled = settings.translationEnabled && !restricted
        switch state {
        case .idle, .empty:
            candidate.setTitle(input.candidate.isEmpty ? "입력하면 번역 후보가 표시됩니다" : "탭하여 번역", for: .normal)
        case .translating:
            candidate.setTitle("번역 중…", for: .normal)
            candidate.isEnabled = false
        case .failed(let error):
            candidate.setTitle(error.message + " · 재시도", for: .normal)
        case .translated(let result):
            guard let snapshot = requestSnapshot else { return }
            let replace = DeletionStrategy.canReplace(source: requestSource, snapshot: snapshot, document: document)
            candidate.setTitle(result.translatedText + (replace ? "  ↗" : "  · 번역문만 삽입"), for: .normal)
            let name = ["ja": "일본어", "ko": "한국어", "en": "영어", "zh": "중국어"][settings.targetLanguage] ?? ""
            candidate.accessibilityLabel = name + " 번역"
            candidate.accessibilityValue = result.translatedText
            candidate.accessibilityHint = replace ? "탭하여 원문을 번역문으로 교체" : "원문은 유지됩니다. 탭하여 번역문만 삽입"
        }
    }

    private func candidateTapped() {
        reloadSettings()
        guard !applying, !restricted, settings.translationEnabled else { return }
        if settings.service == .remote && !hasFullAccess { resetInput(); render(.failed(.permission)); return }
        guard case .translated(let result) = coordinator.state else { schedule(force: true); return }
        guard let snapshot = requestSnapshot, snapshot.matches(document), result.originalText == input.candidate else {
            resetInput(); return
        }
        let source = requestSource
        let suffix = input.trailingWhitespace
        let prefix = String(input.typed.prefix(while: { $0.isWhitespace }))
        applying = true
        coordinator.reset() // Consume first: a second tap can never delete again.
        let outcome = DeletionStrategy.apply(source: source, replacement: prefix + result.translatedText + suffix,
                                              snapshot: snapshot, document: document, allowInsertionOnly: true)
        resetInput()
        applying = false
        if outcome == .interrupted { status.text = "입력창이 변경되어 교체를 중단했습니다. 내용을 확인하세요." }
    }
}
