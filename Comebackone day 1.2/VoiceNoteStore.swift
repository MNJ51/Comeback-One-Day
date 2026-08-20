//
//  VoiceNoteStore.swift
//  Comebackone day 1.2
//
//  Voice notes live as .m4a files in Documents/VoiceNotes; memories store only
//  the filename, mirroring how PhotoStore handles photos.
//

import SwiftUI
import AVFoundation
import Combine

enum VoiceNoteStore {
    static var voiceNotesDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceNotes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for filename: String) -> URL {
        voiceNotesDirectory.appendingPathComponent(filename)
    }

    static func newFilename() -> String {
        UUID().uuidString + ".m4a"
    }

    static func delete(_ filename: String?) {
        guard let filename else { return }
        try? FileManager.default.removeItem(at: url(for: filename))
    }
}

/// Records audio to a new file in VoiceNoteStore, reporting elapsed time as it goes.
@MainActor
final class VoiceRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var elapsedTime: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var currentFilename: String?

    /// Requests microphone permission if needed, then starts recording. Returns
    /// false (without starting) if permission was denied.
    func requestPermissionAndStart() async -> Bool {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { return false }
        beginRecording()
        return true
    }

    private func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? session.setActive(true)

        let filename = VoiceNoteStore.newFilename()
        currentFilename = filename

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        guard let recorder = try? AVAudioRecorder(url: VoiceNoteStore.url(for: filename), settings: settings) else {
            currentFilename = nil
            return
        }
        self.recorder = recorder
        recorder.record()
        isRecording = true
        elapsedTime = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        elapsedTime = recorder?.currentTime ?? elapsedTime
    }

    /// Stops recording and returns the new file's name, or nil if nothing was captured.
    func stop() -> String? {
        recorder?.stop()
        recorder = nil
        timer?.invalidate()
        timer = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return currentFilename
    }
}

/// Plays back a voice note file, reporting playback position as it goes.
@MainActor
final class VoiceNotePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var loadedFilename: String?

    func load(filename: String) {
        guard filename != loadedFilename else { return }
        player = try? AVAudioPlayer(contentsOf: VoiceNoteStore.url(for: filename))
        loadedFilename = filename
        duration = player?.duration ?? 0
        currentTime = 0
    }

    func togglePlayback() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            timer?.invalidate()
        } else {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback)
            try? session.setActive(true)
            player.delegate = self
            player.play()
            isPlaying = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.currentTime = self?.player?.currentTime ?? 0 }
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
            self.timer?.invalidate()
        }
    }
}

/// Record / play / re-record / delete control for a memory's voice note.
///
/// `filename` is the in-session value the parent form is editing. `externallyOwnedFilename`
/// is whatever was already persisted (nil for a brand-new memory) — this view never deletes
/// that file itself, since the user might still cancel the form. Any *other* file it creates
/// mid-session (an intermediate take that gets replaced before the form is saved) is safe to
/// delete immediately, since it was never the persisted value. Final cleanup of a replaced or
/// removed externally-owned file is the parent's job, done at actual save/cancel time.
struct VoiceNoteControl: View {
    @Binding var filename: String?
    var externallyOwnedFilename: String?

    @StateObject private var recorder = VoiceRecorder()
    @StateObject private var player = VoiceNotePlayer()
    @State private var showingPermissionAlert = false

    var body: some View {
        Group {
            if recorder.isRecording {
                recordingRow
            } else if let filename {
                playbackRow(filename)
            } else {
                recordButton
            }
        }
        .alert("Microphone Access Needed", isPresented: $showingPermissionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enable microphone access in Settings to record a voice note.")
        }
    }

    private var recordButton: some View {
        Button {
            Task { await startRecording() }
        } label: {
            Label("Record a Voice Note", systemImage: "mic.fill")
        }
    }

    private var recordingRow: some View {
        HStack {
            Image(systemName: "waveform")
                .foregroundStyle(.red)
            Text(Self.formattedDuration(recorder.elapsedTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            Button("Stop", role: .destructive) {
                let previous = filename
                filename = recorder.stop()
                if let previous, previous != externallyOwnedFilename {
                    VoiceNoteStore.delete(previous)
                }
            }
        }
    }

    private func playbackRow(_ filename: String) -> some View {
        HStack {
            Button {
                player.load(filename: filename)
                player.togglePlayback()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)

            Text(Self.formattedDuration(player.duration))
                .font(.caption)
                .foregroundStyle(.secondary)
                .onAppear { player.load(filename: filename) }

            Spacer()

            Button {
                Task { await startRecording() }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                let previous = self.filename
                self.filename = nil
                if let previous, previous != externallyOwnedFilename {
                    VoiceNoteStore.delete(previous)
                }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
    }

    private func startRecording() async {
        let granted = await recorder.requestPermissionAndStart()
        if !granted { showingPermissionAlert = true }
    }

    private static func formattedDuration(_ time: TimeInterval) -> String {
        let seconds = Int(time.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
