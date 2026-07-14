//
//  QuickCameraView.swift
//  Comebackone day 1.1
//

import SwiftUI
import CoreLocation

struct QuickCameraView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: MemoryStore
    @EnvironmentObject var locationManager: LocationManager

    @State private var capturedImage: UIImage?
    @State private var showingCamera = true
    @State private var name = ""
    @State private var category = Category.location
    @State private var dateVisited = Date()

    private var hasLocation: Bool {
        locationManager.currentLocation != nil
    }

    var body: some View {
        NavigationStack {
            if let image = capturedImage {
                VStack(spacing: 20) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                        .padding()

                    VStack(alignment: .leading, spacing: 15) {
                        TextField("Name", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal)

                        DatePicker("Date Visited", selection: $dateVisited, displayedComponents: .date)
                            .padding(.horizontal)

                        Picker("Category", selection: $category) {
                            ForEach(Category.allCases) { cat in
                                Text(cat.rawValue).tag(cat)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)

                        if !hasLocation {
                            HStack {
                                ProgressView()
                                Text(locationManager.isDenied
                                     ? "Location access is off — enable it in Settings to save this memory."
                                     : "Waiting for your location…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                        }
                    }

                    Spacer()
                }
                .navigationTitle("Quick Memory")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveQuickMemory()
                        }
                        .disabled(name.isEmpty || !hasLocation)
                    }
                }
            } else {
                Color.black
                    .ignoresSafeArea()
                    .sheet(isPresented: $showingCamera, onDismiss: {
                        if capturedImage == nil {
                            dismiss()
                        }
                    }) {
                        CameraView(image: $capturedImage)
                    }
                    .onAppear {
                        showingCamera = true
                    }
            }
        }
    }

    private func saveQuickMemory() {
        guard let image = capturedImage,
              let imageData = image.jpegData(compressionQuality: 0.8),
              let location = locationManager.currentLocation,
              !name.isEmpty else {
            return
        }

        let filenames = PhotoStore.save(imageData).map { [$0] } ?? []
        let newMemory = TravelMemory(
            name: name,
            latitude: location.latitude,
            longitude: location.longitude,
            category: category,
            photoFilenames: filenames,
            dateVisited: dateVisited
        )
        store.add(newMemory)
        dismiss()
    }
}
