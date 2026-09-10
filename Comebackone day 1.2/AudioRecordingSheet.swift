//
//  AudioRecordingSheet.swift
//  Comebackone day 1.2
//
//  Full-screen audio recorder, Apple Journal-style — grabber handle, a big
//  timer, and a large record button. Wraps the exact same VoiceRecorder/
//  VoiceNotePlayer engines VoiceNoteControl already uses (VoiceNoteStore.swift);
//  this is a bigger presentation of the same recording logic, not a new one.
//
//  `filename` is the in-session value the parent form is editing; `externallyOwnedFilename`
//  is whatever was already persisted — this view never deletes that file itself, only
//  intermediate takes it creates and replaces before the form is saved. Same contract
//  VoiceNoteControl already documents.
//

import SwiftUI

struct AudioRecordingSheet: View {
    @Binding var filename: String?
    var externallyOwnedFilename: String?
    @Environment(\.dismiss) private var dismiss

    @StateObject private var recorder = VoiceRecorder()
    @StateObject private var player = VoiceNotePlayer()
    @State private var showingPermissionAlert = false

    var body: some View {
        VStack(spacing: 32) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            Spacer()

            if recorder.isRecording {
                recordingContent
            } else if let filename {
                playbackContent(filename)
            } else {
                idleContent
            }

            Spacer()

            bigRecordButton
        }
        .padding()
        .alert("Microphone Access Needed", isPresented: $showingPermissionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enable microphone access in Settings to record a voice note.")
        }
    }

    private var idleContent: some View {
        VStack(spacing: 12) {
            Text("0:00")
                .font(.system(size: 44, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text("Start Audio Recording")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var recordingContent: some View {
        VStack(spacing: 12) {
            Text(Self.formattedDuration(recorder.elapsedTime))
                .font(.system(size: 44, weight: .light, design: .rounded))
                .monospacedDigit()
            Image(systemName: "waveform")
                .font(.largeTitle)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func playbackContent(_ filename: String) -> some View {
        let displayedTime = player.isPlaying || player.currentTime > 0 ? player.currentTime : player.duration
        VStack(spacing: 16) {
            Text(Self.formattedDuration(displayedTime))
                .font(.system(size: 44, weight: .light, design: .rounded))
                .monospacedDigit()
                .onAppear { player.load(filename: filename) }

            HStack(spacing: 32) {
                Button(role: .destructive) {
                    deleteCurrentTake()
                } label: {
                    Image(systemName: "trash")
                        .font(.title2)
                        .foregroundStyle(.red)
                }

                Button {
                    player.load(filename: filename)
                    player.togglePlayback()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 54))
                }

                Button {
                    Task { await startRecording() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title2)
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var bigRecordButton: some View {
        if recorder.isRecording {
            Button {
                stopRecording()
                dismiss()
            } label: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.red)
                    .frame(width: 32, height: 32)
                    .padding(20)
                    .background(Circle().stroke(.secondary, lineWidth: 3))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 20)
        } else if filename == nil {
            Button {
                Task { await startRecording() }
            } label: {
                Circle()
                    .fill(.red)
                    .frame(width: 64, height: 64)
                    .padding(8)
                    .background(Circle().stroke(.secondary, lineWidth: 3))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 20)
        }
    }

    private func startRecording() async {
        let granted = await recorder.requestPermissionAndStart()
        if !granted { showingPermissionAlert = true }
    }

    private func stopRecording() {
        let previous = filename
        filename = recorder.stop()
        if let previous, previous != externallyOwnedFilename {
            VoiceNoteStore.delete(previous)
        }
    }

    private func deleteCurrentTake() {
        let previous = filename
        filename = nil
        if let previous, previous != externallyOwnedFilename {
            VoiceNoteStore.delete(previous)
        }
    }

    private static func formattedDuration(_ time: TimeInterval) -> String {
        let seconds = Int(time.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
