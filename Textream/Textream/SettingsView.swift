import SwiftUI
import Speech

// MARK: - Settings Tabs

enum SettingsTab: String, CaseIterable, Identifiable {
    case overlay, coaching

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overlay:  return "Overlay"
        case .coaching: return "Coaching"
        }
    }

    var icon: String {
        switch self {
        case .overlay:  return "macwindow"
        case .coaching: return "mic.badge.xmark"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Bindable var settings: NotchSettings
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab = .overlay
    @State private var availableMics: [AudioInputDevice] = []
    @State private var overlayScreens: [NSScreen] = []

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)

                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 16)
                            Text(tab.label)
                                .font(.system(size: 13, weight: .regular))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                        .foregroundStyle(selectedTab == tab ? Color.accentColor : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(12)
            .frame(width: 140)
            .frame(maxHeight: .infinity)
            .background(Color.primary.opacity(0.04))

            Divider()

            VStack(spacing: 0) {
                switch selectedTab {
                case .overlay:
                    overlayTab
                case .coaching:
                    coachingTab
                }

                Divider()

                HStack {
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 460, height: 340)
        .background(.ultraThinMaterial)
    }

    // MARK: - Overlay Tab

    private var overlayTab: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("", selection: $settings.overlayMode) {
                    ForEach(OverlayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(settings.overlayMode.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if settings.overlayMode == .pinned {
                    Divider()

                    Text("Display")
                        .font(.system(size: 13, weight: .medium))

                    Picker("", selection: $settings.notchDisplayMode) {
                        ForEach(NotchDisplayMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if settings.notchDisplayMode == .fixedDisplay {
                        displayPicker
                    }
                }

                Divider()

                Text("Dimensions")
                    .font(.system(size: 13, weight: .medium))

                VStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Width")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(settings.notchWidth))px")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        Slider(value: $settings.notchWidth, in: NotchSettings.minWidth...NotchSettings.maxWidth, step: 10)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Height")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(settings.textAreaHeight))px")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        Slider(value: $settings.textAreaHeight, in: NotchSettings.minHeight...NotchSettings.maxHeight, step: 10)
                    }
                }

                Divider()

                Toggle(isOn: $settings.hideFromScreenShare) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hide from Screen Sharing")
                            .font(.system(size: 13, weight: .medium))
                        Text("Hide the overlay from screen recordings and video calls.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            .padding(16)
        }
        .onAppear { overlayScreens = NSScreen.screens }
    }

    // MARK: - Coaching Tab

    private var coachingTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Speech Language")
                    .font(.system(size: 13, weight: .medium))
                Picker("", selection: $settings.speechLocale) {
                    ForEach(SFSpeechRecognizer.supportedLocales().sorted(by: { $0.identifier < $1.identifier }), id: \.identifier) { locale in
                        Text(Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                            .tag(locale.identifier)
                    }
                }
                .labelsHidden()
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Microphone")
                    .font(.system(size: 13, weight: .medium))
                Picker("", selection: $settings.selectedMicUID) {
                    Text("System Default").tag("")
                    ForEach(availableMics) { mic in
                        Text(mic.name).tag(mic.uid)
                    }
                }
                .labelsHidden()
            }

            Spacer()
        }
        .padding(16)
        .onAppear { availableMics = AudioInputDevice.allInputDevices() }
    }

    // MARK: - Display Picker

    private var displayPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(overlayScreens, id: \.displayID) { screen in
                Button {
                    settings.pinnedScreenID = screen.displayID
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "display")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(settings.pinnedScreenID == screen.displayID ? Color.accentColor : .secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(screen.displayName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(settings.pinnedScreenID == screen.displayID ? Color.accentColor : .primary)
                            Text("\(Int(screen.frame.width))x\(Int(screen.frame.height))")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if settings.pinnedScreenID == screen.displayID {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(settings.pinnedScreenID == screen.displayID ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
