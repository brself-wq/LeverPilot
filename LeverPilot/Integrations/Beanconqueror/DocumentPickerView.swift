//
//  DocumentPickerView.swift
//  VirtualEspressoMachine
//

import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit

public struct DocumentPickerView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    public var onFolderSelected: (URL) -> Void

    public init(onFolderSelected: @escaping (URL) -> Void) {
        self.onFolderSelected = onFolderSelected
    }

    public func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    public func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerView

        init(_ parent: DocumentPickerView) {
            self.parent = parent
        }

        public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first {
                parent.onFolderSelected(url)
            }
            parent.dismiss()
        }
        
        public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
    }
}

#elseif canImport(AppKit)
import AppKit

public struct DocumentPickerView: NSViewRepresentable {
    @Environment(\.dismiss) private var dismiss
    public var onFolderSelected: (URL) -> Void

    public init(onFolderSelected: @escaping (URL) -> Void) {
        self.onFolderSelected = onFolderSelected
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Select Beanconqueror Folder"
            
            if panel.runModal() == .OK, let url = panel.url {
                self.onFolderSelected(url)
            }
            self.dismiss()
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
