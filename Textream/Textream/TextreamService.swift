import AppKit
import Combine
import SwiftUI

class TextreamService: NSObject, ObservableObject {
    static let shared = TextreamService()
    let overlayController = NotchOverlayController()
    var onOverlayDismissed: (() -> Void)?

    @Published var currentStoryline: Storyline?
    @Published var chatMessages: [ChatMessage] = []
    @Published var isReadyToGenerate = false
    @Published var isPresentationActive = false

    func startPresentation(with storyline: Storyline) {
        guard !isPresentationActive else { return }
        currentStoryline = storyline
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

    func resetSession() {
        stopPresentation()
        currentStoryline = nil
        chatMessages = []
        isReadyToGenerate = false
        AIService.shared.resetSessions()
    }
}
