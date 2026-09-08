//
//  JournalExporter.swift
//  Comebackone day 1.2
//
//  Exports journal entries as a single Markdown document — reliable, no new
//  frameworks, and readable/re-importable anywhere (a text editor, Day One,
//  Obsidian). A PDF export is a natural follow-up once this is in, not
//  bundled in here.
//

import Foundation

enum JournalExporter {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()

    /// Formats entries newest-first as one Markdown document, one `##`
    /// section per entry.
    static func markdown(for entries: [JournalEntry]) -> String {
        let sorted = entries.sorted { $0.date > $1.date }
        let sections = sorted.map(markdownSection(for:))
        return sections.joined(separator: "\n\n---\n\n")
    }

    private static func markdownSection(for entry: JournalEntry) -> String {
        var lines: [String] = []

        let heading = entry.title?.trimmedNonEmpty ?? dateFormatter.string(from: entry.date)
        lines.append("## \(heading)")

        var metaParts: [String] = [dateFormatter.string(from: entry.date)]
        if let mood = entry.mood {
            metaParts.append("\(mood.emoji) \(mood.label)")
        }
        if let locationLabel = entry.locationLabel {
            metaParts.append(locationLabel)
        }
        if let journalName = entry.journalName {
            metaParts.append("Journal: \(journalName)")
        }
        lines.append("*\(metaParts.joined(separator: " · "))*")

        if !entry.text.isEmpty {
            lines.append("")
            lines.append(entry.text)
        }

        return lines.joined(separator: "\n")
    }

    /// Writes the export to a temp file for sharing via `ShareLink`.
    static func markdownFileURL(for entries: [JournalEntry]) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Journal Export.md")
        do {
            try markdown(for: entries).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
