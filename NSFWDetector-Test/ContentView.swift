//
//  ContentView.swift
//  NSFWDetector-Test
//
//  Created by Mehmet Tırpan on 25.09.2025.
//

import SwiftUI
import PhotosUI
import CoreML
import Vision
import NSFWDetectorKit
import UIKit

struct ContentView: View {
    @State private var pickedItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var nsfwScore: Float = 0
    @State private var nsfwThreshold: Double = 0.20   // NSFW için eşik (≥ ise yayınlanamaz)
    @State private var nsfwDecisionText: String = "—"
    @State private var decision: String = "—"
    @State private var loading = false
    @State private var rawLabels: [(String, Float)] = []
    @State private var showDebug = false
    @State private var showCameraSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .frame(height: 320)
                        .overlay(
                            Group {
                                if let ui = image {
                                    Image(uiImage: ui)
                                        .resizable()
                                        .scaledToFit()
                                        .padding(10)
                                } else {
                                    VStack(spacing: 8) {
                                        Text("Görsel seçmek için aşağıdan seçin")
                                            .foregroundStyle(.secondary)
                                        Text("Designed for iPad — NSFW test")
                                            .font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        )
                }

                HStack(spacing: 12) {
                    PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                        Label("Görsel Seç", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.borderedProminent)
                    // iOS 16 uyumlu onChange
                    .onChange(of: pickedItem) { newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                               let ui = UIImage(data: data) {
                                resetForNewImage(ui)
                            }
                        }
                    }

                    Button {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            showCameraSheet = true
                        }
                    } label: {
                        Label("Kamera", systemImage: "camera")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.gray)

                    Button {
                        runScan()
                    } label: {
                        if loading {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Sınıflandır", systemImage: "wand.and.stars")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(image == nil || loading)
                }
                .sheet(isPresented: $showCameraSheet) {
                    CameraPicker(imageHandler: { ui in
                        resetForNewImage(ui)
                    })
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("NSFW eşiği: \(nsfwThreshold, specifier: "%.2f")")
                        Slider(value: $nsfwThreshold, in: 0.05...0.95, step: 0.01)
                            .frame(maxWidth: 300)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Karar: \(decision)")
                        .font(.headline)
                        .foregroundStyle(decision == "Yayınlanamaz" ? .red : (decision == "Yayınlanabilir" ? .green : .primary))
                    Text(String(format: "NSFW skoru: %.1f%%", nsfwScore * 100))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("NSFW kararı: \(nsfwDecisionText)")
                        .font(.subheadline)
                        .foregroundStyle(nsfwDecisionText == "Yayınlanamaz" ? .red : (nsfwDecisionText == "Yayınlanabilir" ? .green : .primary))
                    Text("Kurallar: NSFW ≥ NSFW eşiği → YAYINLANAMAZ")
                        .font(.footnote).foregroundStyle(.secondary)
#if DEBUG
                    // TODO: You can render raw labels here if you pass them via @State. For now, they are printed in console.
#endif
                    Toggle("Debug: Model etiketleri", isOn: $showDebug)
                        .toggleStyle(.switch)
                    if showDebug {
                        ScrollView { VStack(alignment: .leading, spacing: 4) {
                            ForEach(rawLabels.sorted(by: { $0.1 > $1.1 }), id: \.0) { kv in
                                Text("\(kv.0): \(String(format: "%.1f%%", kv.1 * 100))")
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }}
                        .frame(maxHeight: 160)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
            }
            .padding(20)
            .navigationTitle("NSFWDetector • iPad Test")
        }
    }

    private func resetForNewImage(_ ui: UIImage) {
        image = ui
        nsfwScore = 0
        decision = "—"
        nsfwDecisionText = "—"
        rawLabels = []
    }

    private func runScan() {
        guard let img = image else { return }
        loading = true
        decision = "—"
        nsfwDecisionText = "—"

        CoreMLNSFWScanner.shared.classify(img) { result in
            DispatchQueue.main.async {
                self.loading = false
                switch result {
                case .failure(let err):
                    self.decision = "Hata: \(err.localizedDescription)"
                    self.nsfwScore = 0
                    self.rawLabels = []
                case .success(let (nsfw, labels)):
                    self.nsfwScore = nsfw
                    self.rawLabels = labels.map { ($0.key, $0.value) }
                    self.nsfwDecisionText = self.nsfwScore >= Float(self.nsfwThreshold) ? "Yayınlanamaz" : "Yayınlanabilir"
                    self.decision = self.nsfwDecisionText
                }
            }
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIImagePickerController

    var imageHandler: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let ui = info[.originalImage] as? UIImage {
                parent.imageHandler(ui)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

//#Preview {
//    ContentView()
//}
