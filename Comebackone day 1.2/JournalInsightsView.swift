//
//  JournalInsightsView.swift
//  Comebackone day 1.2
//
//  Journal stats, Apple Journal-style: entries, words written, streaks, and
//  a mood/journal breakdown — all derived fresh from JournalStore.entries,
//  no persisted state of its own.
//

import SwiftUI

struct JournalInsightsView: View {
    @EnvironmentObject var journalStore: JournalStore
    @EnvironmentObject var journalAppearanceStore: JournalAppearanceStore
    @AppStorage("journalStreakIsWeekly") private var streakIsWeekly = false

    private var entries: [JournalEntry] {
        journalStore.entries
    }

    private var entriesThisYear: Int {
        entries.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .year) }.count
    }

    private var totalWords: Int {
        entries.reduce(0) { $0 + $1.text.split(separator: " ").count }
    }

    private var currentStreak: Int {
        streakIsWeekly
            ? JournalStreak.currentWeeklyStreak(entryDates: entries.map(\.date))
            : JournalStreak.currentStreak(entryDates: entries.map(\.date))
    }

    private var longestStreak: Int {
        streakIsWeekly
            ? JournalStreak.longestWeeklyStreak(entryDates: entries.map(\.date))
            : JournalStreak.longestStreak(entryDates: entries.map(\.date))
    }

    // Regenerating the export file is a disk write, so it's cached in @State
    // rather than recomputed on every body re-render (e.g. toggling the
    // Daily/Weekly streak picker) — only refreshed when the entry count
    // actually changes, via the `.task(id:)` below.
    @State private var exportFileURL: URL?

    /// Every distinct journal name in use, paired with its entry count —
    /// same free-text grouping JournalListView already uses for filtering.
    private var journalBreakdown: [(name: String, count: Int)] {
        let groups = Dictionary(grouping: entries) { $0.journalName ?? "Journal" }
        return groups.map { (name: $0.key, count: $0.value.count) }.sorted { $0.count > $1.count }
    }

    private var moodBreakdown: [(mood: JournalMood, count: Int)] {
        let groups = Dictionary(grouping: entries.compactMap(\.mood)) { $0 }
        return JournalMood.allCases.compactMap { mood in
            guard let count = groups[mood]?.count, count > 0 else { return nil }
            return (mood: mood, count: count)
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(entriesThisYear)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Text("Entries this year")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .listRowBackground(
                    LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .opacity(0.85)
                )
                .foregroundStyle(.white)
            }

            Section("Overview") {
                statRow(label: "Total Entries", value: "\(entries.count)")
                statRow(label: "Words Written", value: "\(totalWords)")
                Picker("Streak", selection: $streakIsWeekly) {
                    Text("Daily").tag(false)
                    Text("Weekly").tag(true)
                }
                .pickerStyle(.segmented)
                statRow(
                    label: "Current Streak",
                    value: currentStreak > 0 ? "🔥 \(currentStreak) \(streakIsWeekly ? "weeks" : "days")" : "—"
                )
                statRow(label: "Longest Streak", value: "\(longestStreak) \(streakIsWeekly ? "weeks" : "days")")
            }

            if !moodBreakdown.isEmpty {
                Section("Moods") {
                    ForEach(moodBreakdown, id: \.mood) { item in
                        statRow(label: "\(item.mood.emoji) \(item.mood.label)", value: "\(item.count)")
                    }
                }
            }

            if journalBreakdown.count > 1 {
                Section("Journals") {
                    ForEach(journalBreakdown, id: \.name) { item in
                        let appearance = journalAppearanceStore.appearance(for: item.name)
                        HStack {
                            Image(systemName: appearance.iconName)
                                .foregroundStyle(appearance.resolvedColor)
                                .frame(width: 20)
                            Text(item.name)
                            Spacer()
                            Text("\(item.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: entries.count) {
            exportFileURL = JournalExporter.markdownFileURL(for: entries)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let exportFileURL {
                    ShareLink(item: exportFileURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(entries.isEmpty)
                }
            }
        }
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
