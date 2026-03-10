import SwiftUI

struct ContentView: View {
    @ObservedObject private var service = TextreamService.shared
    @State private var showSettings = false
    @State private var showAbout = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            StorylineListView(
                store: service.store,
                selectedID: $service.selectedStorylineID,
                isCreatingNew: $service.isCreatingNew,
                onImportGenerated: { storyline in
                    service.saveAndSelect(storyline)
                }
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } content: {
            if service.isCreatingNew {
                StorylineBuilderView(
                    chatMessages: $service.chatMessages,
                    isReadyToGenerate: $service.isReadyToGenerate,
                    onStorylineGenerated: { storyline in
                        service.saveAndSelect(storyline)
                    }
                )
                .navigationSplitViewColumnWidth(min: 280, ideal: 360, max: 480)
            } else {
                builderPlaceholder
            }
        } detail: {
            if let binding = savedBinding {
                StorylineEditorView(
                    saved: binding,
                    onSave: { updated in
                        service.store.update(updated)
                    },
                    onStartPresenting: { startPresenting() }
                )
            } else if service.isCreatingNew {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("Your storyline will appear here")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                    Text("Answer the questions in the chat to build your presentation outline.")
                        .font(.system(size: 12))
                        .foregroundStyle(.quaternary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding(16)
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("Select a storyline or create a new one")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(16)
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .background(.ultraThinMaterial)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 8) {
                    if service.isPresentationActive {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.red)
                                .frame(width: 8, height: 8)
                            Text("Presenting")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.red)
                        }

                        Button {
                            service.stopPresentation()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 10))
                                Text("Stop")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: NotchSettings.shared)
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAbout)) { _ in
            showAbout = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            service.isPresentationActive = service.overlayController.isShowing
        }
    }

    // MARK: - Helpers

    private var savedBinding: Binding<SavedStoryline>? {
        guard let id = service.selectedStorylineID,
              service.store.storyline(for: id) != nil else { return nil }
        return Binding(
            get: { service.store.storyline(for: id)! },
            set: { service.store.update($0) }
        )
    }

    private var builderPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Chat builder")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
            Text("Use \"New from Chat\" to build a storyline interactively.")
                .font(.system(size: 11))
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(16)
    }

    private func startPresenting() {
        guard let id = service.selectedStorylineID,
              let saved = service.store.storyline(for: id) else { return }

        service.onOverlayDismissed = {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }

        service.startPresentation(with: saved.storyline)
    }
}

// MARK: - About View

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0"
    }

    var body: some View {
        VStack(spacing: 16) {
            if let icon = NSImage(named: "AppIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }

            VStack(spacing: 4) {
                Text("Textream")
                    .font(.system(size: 20, weight: .bold))
                Text("Presentation Coach")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text("Version \(appVersion)")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }

            Text("AI-powered presentation coaching that listens to you present and reminds you of your storyline in real-time.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Button("OK") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 320)
        .background(.ultraThinMaterial)
    }
}

#Preview {
    ContentView()
}
