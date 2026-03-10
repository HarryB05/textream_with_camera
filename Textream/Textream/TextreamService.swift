import AppKit
import Combine
import SwiftUI

class TextreamService: NSObject, ObservableObject {
    static let shared = TextreamService()
    let overlayController = NotchOverlayController()
    let store = StorylineStore()
    var onOverlayDismissed: (() -> Void)?

    @Published var selectedStorylineID: UUID?
    @Published var isCreatingNew = false

    @Published var chatMessages: [ChatMessage] = []
    @Published var isReadyToGenerate = false
    @Published var isPresentationActive = false

    var selectedSaved: Binding<SavedStoryline?> {
        Binding<SavedStoryline?>(
            get: {
                guard let id = self.selectedStorylineID else { return nil }
                return self.store.storyline(for: id)
            },
            set: { newValue in
                if let s = newValue {
                    self.store.update(s)
                }
            }
        )
    }

    // MARK: - Save a generated storyline and select it

    @discardableResult
    func saveAndSelect(_ storyline: Storyline) -> UUID {
        let saved = store.save(storyline)
        selectedStorylineID = saved.id
        isCreatingNew = false
        return saved.id
    }

    // MARK: - Presentation

    func startPresentation(with storyline: Storyline) {
        guard !isPresentationActive else { return }
        isPresentationActive = true

        overlayController.show(storyline: storyline) { [weak self] in
            self?.isPresentationActive = false
            self?.onOverlayDismissed?()
        }
    }

    func stopPresentation() {
        overlayController.dismiss()
        isPresentationActive = false
    }

    // MARK: - New session (chat builder)

    func startNewFromChat() {
        selectedStorylineID = nil
        isCreatingNew = true
        chatMessages = []
        isReadyToGenerate = false
        AIService.shared.resetSessions()
    }

    func resetSession() {
        stopPresentation()
        startNewFromChat()
    }
}
