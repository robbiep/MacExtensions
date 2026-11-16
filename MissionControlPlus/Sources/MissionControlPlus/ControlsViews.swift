import MissionControlPlusCore
import SwiftUI

/// Full Control Panel window shown when launching or reopening the app.
struct ControlsWindowView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MasterHeaderCard(model: model, compact: false)

            if !model.isTrusted {
                AccessibilityBanner(model: model)
            }

            FeaturesCard(model: model, compact: false)
            AppBehaviorCard(model: model)
        }
        .padding(20)
        .frame(width: 440)
        .fixedSize(horizontal: true, vertical: true)
    }
}

/// Compact menu bar popover sharing the exact same toggle switches and live status.
struct PopoverControlsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MasterHeaderCard(model: model, compact: true)

            if !model.isTrusted {
                AccessibilityBanner(model: model)
            }

            FeaturesCard(model: model, compact: true)

            Divider()

            HStack {
                Button("Open Controls…") {
                    model.openControlsWindow()
                }
                .buttonStyle(.link)

                Spacer()

                Button("Quit") {
                    model.quit()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 330)
        .fixedSize(horizontal: true, vertical: true)
    }
}

// MARK: - Shared Components

private struct MasterHeaderCard: View {
    @ObservedObject var model: AppModel
    let compact: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.3.group.fill")
                .font(.system(size: compact ? 20 : 24, weight: .semibold))
                .foregroundStyle(model.statusIsActive ? Color.accentColor : Color.secondary)
                .frame(width: compact ? 34 : 40, height: compact ? 34 : 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("MissionControlPlus")
                    .font(compact ? .headline : .title3.weight(.semibold))
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(model.statusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Toggle("Enable MissionControlPlus", isOn: $model.isMasterEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(compact ? 10 : 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }

    private var statusColor: Color {
        if !model.isTrusted { return .orange }
        if !model.statusIsActive { return .secondary }
        return model.engineState == .showing ? .green : .blue
    }
}

private struct AccessibilityBanner: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Accessibility Permission Required", systemImage: "hand.raised.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            Text("MissionControlPlus reads WindowManager/Dock layout via Accessibility (no Screen Recording, no SIP changes).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Open Privacy Settings") {
                    model.requestAccessibilityPrompt()
                    model.openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Check Again") {
                    model.refreshAccessibilityStatus()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.30))
        )
    }
}

private struct FeaturesCard: View {
    @ObservedObject var model: AppModel
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            Text("Features")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: compact ? 10 : 12) {
                SwitchRow(
                    title: "App Icons on Windows",
                    subtitle: compact ? nil : "Show each window's app icon over its Mission Control thumbnail.",
                    isOn: $model.showWindowIcons
                )

                if model.showWindowIcons {
                    VStack(alignment: .leading, spacing: 8) {
                        SwitchRow(
                            title: "Show Window Titles",
                            subtitle: compact ? nil : "Include window title and app name next to the icon.",
                            isOn: $model.showWindowTitles
                        )

                        HStack {
                            Text("Icon Position")
                                .font(.subheadline)
                            Spacer()
                            Picker("Icon Position", selection: $model.iconAnchor) {
                                ForEach(OverlayAnchor.allCases, id: \.self) { anchor in
                                    Text(anchor.displayName).tag(anchor)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 132)
                        }
                    }
                    .padding(.leading, 14)
                    .padding(.top, 2)
                }

                Divider()

                SwitchRow(
                    title: "App Names in Top Spaces Bar",
                    subtitle: compact ? nil : "Replace contextual full-screen titles (e.g. \"Top 10 recipes\") with short app names (\"Chrome\").",
                    isOn: $model.replaceSpaceNames
                )
            }
            .padding(compact ? 10 : 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
            .disabled(!model.isMasterEnabled)
            .opacity(model.isMasterEnabled ? 1.0 : 0.55)
        }
    }
}

private struct AppBehaviorCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("App & Diagnostics")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 10) {
                SwitchRow(
                    title: "Launch at Login",
                    subtitle: nil,
                    isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )

                SwitchRow(
                    title: "Show Controls Window on Launch",
                    subtitle: nil,
                    isOn: $model.openWindowOnLaunch
                )

                Divider()

                HStack(spacing: 8) {
                    Button("Dump Next Diagnostics") {
                        model.armDiagnostics()
                    }
                    .controlSize(.small)

                    Button("Open Logs") {
                        model.openLogsFolder()
                    }
                    .controlSize(.small)

                    Spacer()

                    Button("Quit App") {
                        model.quit()
                    }
                    .controlSize(.small)
                }

                if let note = model.diagnosticNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
        }
    }
}

private struct SwitchRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: subtitle == nil ? .center : .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}
