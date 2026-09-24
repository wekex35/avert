import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case status
    case privacy
    case neck
    case schedule
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: return "Status"
        case .privacy: return "Privacy"
        case .neck: return "Neck care"
        case .schedule: return "Schedule"
        case .general: return "General"
        }
    }

    var symbol: String {
        switch self {
        case .status: return "eye"
        case .privacy: return "shield.lefthalf.filled"
        case .neck: return "figure.mind.and.body"
        case .schedule: return "calendar"
        case .general: return "gearshape"
        }
    }
}

struct SettingsRootView: View {
    @Bindable var model: AppModel
    @State private var tab: SettingsTab = .status

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: Binding(
            get: { model.isCalibrationSheetPresented },
            set: { if !$0 { model.cancelCalibrationFlow() } }
        )) {
            CalibrationFlowView(model: model)
        }
        .sheet(isPresented: Binding(
            get: { model.isExerciseSheetPresented },
            set: { if !$0 { model.finishExerciseSession(completed: false) } }
        )) {
            ExerciseFlowView(model: model)
        }
        .onReceive(NotificationCenter.default.publisher(for: .avertShowAbout)) { _ in
            tab = .general
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image("BrandLogo")
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text("Avert")
                    .font(.headline)
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 10)

            ForEach(SettingsTab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    Label(item.title, systemImage: item.symbol)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(tab == item ? Color.accentColor.opacity(0.18) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: 168)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    @ViewBuilder
    private var detail: some View {
        ScrollView {
            Group {
                switch tab {
                case .status:
                    StatusPane(model: model)
                case .privacy:
                    PrivacyPane(model: model)
                case .neck:
                    NeckPane(model: model)
                case .schedule:
                    SchedulePane(model: model)
                case .general:
                    GeneralPane(model: model)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct StatusPane: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.detailStatusTitle)
                        .font(.system(size: 22, weight: .semibold))
                    Text(model.detailStatusSubtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(model.trackingDebugLine)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)

                    HStack(spacing: 10) {
                        Button(model.isEnabled ? "Disable" : "Enable protection") {
                            model.setEnabled(!model.isEnabled)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        if model.phase == .motionUnavailable || model.phase == .waitingForMotion {
                            Button("Bring AirPods to Mac") {
                                model.bringAirPodsToMac()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .controlSize(.large)
                        }

                        Button("Calibrate…") {
                            model.openCalibrationFlow()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(!model.isEnabled)

                        if model.needsRecalibration {
                            Button("Recalibrate…") {
                                model.openCalibrationFlow()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .controlSize(.large)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                startExerciseButton
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )

            if model.needsRecalibration {
                Label("Your seating pose drifted. Recalibrate while facing the screen.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metric("State", model.phaseLabel)
                metric("Motion", model.motionStatusLabel)
                metric("Yaw", model.lastYawDegrees.map { String(format: "%.0f°", $0) } ?? "—")
                metric("Pitch", model.lastPitchDegrees.map { String(format: "%.0f°", $0) } ?? "—")
                metric("Schedule", model.settings.isProtectionAllowed() ? "Active now" : "Paused by schedule")
                metric("Panic blur", model.isPanicBlurActive ? "On (⌘⇧B)" : "Off (⌘⇧B)")
                metric("Displays", model.settings.displayCoverage.title)
                metric("Active ear", model.activeEar.title)
                metric(
                    "Bud mode",
                    model.settings.singleEarMode
                        ? (model.headTracker.appearsSingleEarSession ? "Single-ear" : "Either ear")
                        : "Standard"
                )
                metric("Last calibrate", model.lastCalibrateSummary)
            }
        }
    }

    private var startExerciseButton: some View {
        Button {
            model.openExerciseSession()
        } label: {
            ZStack(alignment: .bottom) {
                Group {
                    if let image = NeckExercise.image(named: "home-exercise") {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.primary.opacity(0.08)
                        Image(systemName: "figure.cooldown")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 132, height: 132)
                .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(height: 56)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

                Text("Start exercise")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.bottom, 10)
            }
            .frame(width: 132, height: 132)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Start guided neck exercises")
        .accessibilityLabel("Start exercise")
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.medium))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }
}

private struct PrivacyPane: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Look-away veil") {
                Slider(value: Binding(
                    get: { model.settings.yawThresholdDegrees },
                    set: { model.settings.yawThresholdDegrees = $0 }
                ), in: 12...40, step: 0.5) {
                    Text("Yaw threshold")
                } minimumValueLabel: {
                    Text("12°")
                } maximumValueLabel: {
                    Text("40°")
                }
                Text("\(model.settings.yawThresholdDegrees, specifier: "%.1f")°")
                    .foregroundStyle(.secondary)

                Slider(value: Binding(
                    get: { model.settings.blurIntensity },
                    set: { model.settings.blurIntensity = $0 }
                ), in: 0.4...1.0, step: 0.05) {
                    Text("Intensity")
                }
                Text("\(Int(model.settings.blurIntensity * 100))%")
                    .foregroundStyle(.secondary)

                Slider(value: Binding(
                    get: { Double(model.settings.fadeMilliseconds) },
                    set: {
                        model.settings.fadeMilliseconds = Int($0)
                        model.overlays.setFadeDuration(model.settings.fadeDuration)
                    }
                ), in: 80...500, step: 20) {
                    Text("Fade")
                }
                Text("\(model.settings.fadeMilliseconds) ms")
                    .foregroundStyle(.secondary)
            }

            Section("Look down / look up") {
                Toggle("Soft dim when looking down", isOn: Binding(
                    get: { model.settings.lookDownDimEnabled },
                    set: { model.setLookDownDimEnabled($0) }
                ))
                Slider(value: Binding(
                    get: { model.settings.pitchLookDownDegrees },
                    set: { model.settings.pitchLookDownDegrees = $0 }
                ), in: 10...40, step: 1) {
                    Text("Look-down threshold (\(Int(model.settings.pitchLookDownDegrees))°)")
                }
                Text("Chin toward chest from your calibrated center. Lower if dim never appears.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Panic when looking up", isOn: Binding(
                    get: { model.settings.lookUpPanicEnabled },
                    set: { model.setLookUpPanicEnabled($0) }
                ))
                Text("Looking up covers the screen and stays on until you clear it with ⌘⇧B. Looking down does not clear panic.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { model.settings.pitchLookUpDegrees },
                    set: { model.settings.pitchLookUpDegrees = $0 }
                ), in: 8...40, step: 1) {
                    Text("Look-up threshold (\(Int(model.settings.pitchLookUpDegrees))°)")
                }

                Toggle("Invert look up / down", isOn: Binding(
                    get: { model.settings.invertVerticalPitch },
                    set: { model.settings.invertVerticalPitch = $0 }
                ))
                Text("If looking at the ceiling dims instead of covering (or the reverse), turn this on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Panic / look-up cover", selection: Binding(
                    get: { model.settings.panicCoverStyle },
                    set: { model.setPanicCoverStyle($0) }
                )) {
                    ForEach(PanicCoverStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }

                HStack(alignment: .center, spacing: 14) {
                    PanicCoverPreview(
                        style: model.settings.panicCoverStyle,
                        image: model.panicImagePreview
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Button("Choose image…") {
                            model.choosePanicImage()
                        }
                        if model.panicImages.hasImage {
                            Button("Clear image") {
                                model.clearPanicImage()
                            }
                        }
                        Text(model.settings.panicCoverStyle == .customImage && model.panicImagePreview != nil
                             ? "Selected image is used for look-up and ⌘⇧B."
                             : "Solid black fully hides the screen. Clear panic with ⌘⇧B only.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }

            Section("Displays") {
                Picker("Coverage", selection: Binding(
                    get: { model.settings.displayCoverage },
                    set: { model.setDisplayCoverage($0) }
                )) {
                    ForEach(DisplayCoverage.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct NeckPane: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Stillness at screen") {
                Toggle("Neck break reminders", isOn: Binding(
                    get: { model.settings.neckCareEnabled },
                    set: { model.setNeckCareEnabled($0) }
                ))
                Picker("Remind after", selection: Binding(
                    get: { model.settings.stillnessMinutes },
                    set: { model.setStillnessMinutes($0) }
                )) {
                    Text("2 min (demo)").tag(2)
                    Text("10 min").tag(10)
                    Text("15 min").tag(15)
                    Text("20 min (recommended)").tag(20)
                    Text("30 min").tag(30)
                    Text("60 min").tag(60)
                }
                Text("Default 20 min matches common microbreak guidance for static desk posture (e.g. Stanford EH&S ~every 20 min; OSHA also urges frequent short pauses). Head counts as still when turn rate stays under ~5°/s and pose drift under ~5°, after a 5 s dwell so brief wobbles don’t count.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sustained tilt") {
                Toggle("Tilt reminders", isOn: Binding(
                    get: { model.settings.sustainedFlexEnabled },
                    set: { model.setSustainedFlexEnabled($0) }
                ))
                Slider(value: Binding(
                    get: { model.settings.flexPitchDegrees },
                    set: { model.settings.flexPitchDegrees = $0 }
                ), in: 10...35, step: 1) {
                    Text("Flex threshold (\(Int(model.settings.flexPitchDegrees))°)")
                }
                Text("Default 20° follows occupational ergonomics reviews that treat ~20° neck flexion as the usual higher-risk cut-off. Sustained tilt must hold past a short dwell before timing starts. Wellness nudge only — not a diagnosis.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Guided exercises") {
                Toggle("Remind every 2 hours", isOn: Binding(
                    get: { model.settings.neckExercisesEnabled },
                    set: { model.setNeckExercisesEnabled($0) }
                ))
                Toggle("Voice coach", isOn: Binding(
                    get: { model.settings.neckExerciseVoiceEnabled },
                    set: { model.setNeckExerciseVoiceEnabled($0) }
                ))
                Text("Voice coach + AirPods counting. Hold each stretch gently; 4 slow reps per set.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Start exercises…") {
                    model.openExerciseSession()
                }
                .buttonStyle(.borderedProminent)

                if let done = model.settings.lastNeckExerciseCompletedAt {
                    Text("Last completed \(done.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Calibration drift") {
                Toggle("Prompt to recalibrate after posture change", isOn: Binding(
                    get: { model.settings.autoRecalibratePrompt },
                    set: { model.settings.autoRecalibratePrompt = $0 }
                ))
                Text("If you sit up or shift and the center feels wrong, Avert will ask you to recalibrate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct SchedulePane: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                Picker("When protection may run", selection: Binding(
                    get: { model.settings.scheduleMode },
                    set: { model.settings.scheduleMode = $0 }
                )) {
                    ForEach(ScheduleMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } footer: {
                Text("Use “outside work hours” for cafés and evenings. Master Enable still has to be on.")
            }

            if model.settings.scheduleMode == .activeHours {
                Section("Active hours") {
                    hourPicker("Start", Binding(
                        get: { model.settings.scheduleStartHour },
                        set: { model.settings.scheduleStartHour = $0 }
                    ))
                    hourPicker("End", Binding(
                        get: { model.settings.scheduleEndHour },
                        set: { model.settings.scheduleEndHour = $0 }
                    ))
                }
            }

            if model.settings.scheduleMode == .outsideWorkHours {
                Section("Work hours (protection off)") {
                    hourPicker("Work start", Binding(
                        get: { model.settings.workStartHour },
                        set: { model.settings.workStartHour = $0 }
                    ))
                    hourPicker("Work end", Binding(
                        get: { model.settings.workEndHour },
                        set: { model.settings.workEndHour = $0 }
                    ))
                }
            }
        }
        .formStyle(.grouped)
    }

    private func hourPicker(_ title: String, _ binding: Binding<Int>) -> some View {
        Picker(title, selection: binding) {
            ForEach(0..<24, id: \.self) { hour in
                Text(String(format: "%02d:00", hour)).tag(hour)
            }
        }
    }
}

private struct GeneralPane: View {
    @Bindable var model: AppModel

    private var versionLine: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image("BrandLogo")
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Avert")
                            .font(.title3.weight(.semibold))
                        Text(versionLine)
                            .foregroundStyle(.secondary)
                        Text("Shoulder-surf reduction with AirPods head tracking. No camera.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.settings.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                Text("Remembers Enable / settings in UserDefaults.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Hotkey") {
                Toggle("Panic blur hotkey (⌘⇧B)", isOn: Binding(
                    get: { model.settings.hotkeyEnabled },
                    set: { model.setHotkeyEnabled($0) }
                ))
                Text("Toggles a full-screen privacy veil without opening the menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Single AirPod") {
                Toggle("Single-ear friendly mode", isOn: Binding(
                    get: { model.settings.singleEarMode },
                    set: { model.setSingleEarMode($0) }
                ))
                Toggle("Recenter when ear switches", isOn: Binding(
                    get: { model.settings.autoRecalibrateOnEarSwitch },
                    set: { model.setAutoRecalibrateOnEarSwitch($0) }
                ))
                Text("Apple already streams motion from one bud at a time. One AirPod in-ear works. This mode adds longer disconnect grace and recenters if the streaming ear changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Text("Avert processes head motion on-device. It does not use a camera, does not upload pose data, and does not require an account. See docs/PRIVACY.md in the project for the full statement.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PanicCoverPreview: View {
    let style: PanicCoverStyle
    let image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black)

            if style == .customImage, let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 78)
                    .clipped()
            } else {
                Text(style == .customImage ? "No image" : "Solid black")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: 120, height: 78)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        )
        .accessibilityLabel(
            style == .customImage && image != nil ? "Selected panic image" : "Solid black panic cover"
        )
    }
}
