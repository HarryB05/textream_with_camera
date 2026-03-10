import SwiftUI

struct ContentView: View {
    @ObservedObject private var service = TextreamService.shared
    @State private var showSettings = false
    @State private var showAbout = false

    var body: some View {
        NavigationSplitView {
            StorylineBuilderView(
                chatMessages: $service.chatMessages,
                storyline: $service.currentStoryline,
                isReadyToGenerate: $service.isReadyToGenerate,
                onStartPresenting: startPresenting
            )
        } detail: {
            StorylineOutlineView(
                storyline: $service.currentStoryline,
                onStartPresenting: startPresenting
            )
        }
        .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 500)
        .frame(minWidth: 700, minHeight: 500)
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
                        service.resetSession()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10))
                            Text("New")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(service.isPresentationActive)

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

    private func startPresenting() {
        guard let storyline = service.currentStoryline else { return }

        service.onOverlayDismissed = {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }

        service.startPresentation(with: storyline)
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
