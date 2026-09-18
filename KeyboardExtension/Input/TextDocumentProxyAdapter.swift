import UIKit

@MainActor
final class TextDocumentProxyAdapter: TextDocument {
    private unowned let controller: UIInputViewController
    init(_ controller: UIInputViewController) { self.controller = controller }
    var before: String? { controller.textDocumentProxy.documentContextBeforeInput }
    var after: String? { controller.textDocumentProxy.documentContextAfterInput }
    var selected: String? { controller.textDocumentProxy.selectedText }
    var identifier: UUID { controller.textDocumentProxy.documentIdentifier }
    func deleteBackward() { controller.textDocumentProxy.deleteBackward() }
    func insertText(_ text: String) { controller.textDocumentProxy.insertText(text) }
}
