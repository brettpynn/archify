//
//  FileOperations.swift
//  archify
//
//  Created by oct4pie on 6/12/24.
//

import AppKit
import Foundation

class FileOperations {
    let appState: AppState
    let fileManager = FileManager.default
    private let applicationCopier = ApplicationCopier()
    private let applicationThinner = ApplicationThinner()
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    func duplicateApp(
        appDir: String,
        outputDir: String,
        named name: String? = nil
    ) throws -> String {
        let inputURL = URL(fileURLWithPath: appDir, isDirectory: true)
        let outputRootURL = URL(fileURLWithPath: outputDir, isDirectory: true)
        appState.appendLog(
            "Copying \(inputURL.lastPathComponent) to \(outputRootURL.path)"
        )
        return try applicationCopier.copyApplication(
            from: appDir,
            toDirectory: outputDir,
            named: name
        )
    }
    
    func extractAndSignBinaries(
        in dir: String, targetArch: String, noSign: Bool, noEntitlements: Bool
    ) {
        // Security-first fork: never replace the original developer identity.
        // The UI no longer offers ad-hoc/LDID signing, but also enforce this
        // at the operation boundary for callers that bypass the UI.
        guard noSign, !appState.useCodesign, !appState.useLDID else {
            appState.appendLog("Blocked: re-signing changes the developer identity. Select Preserve signature.")
            DispatchQueue.main.async { self.appState.isProcessing = false }
            return
        }
        let universalApps = UniversalApps()
        let originalSize = universalApps.calculateDirectorySize(path: dir)
        let signaturePolicy: ApplicationThinner.SignaturePolicy = .preserve

        applicationThinner.thinApplicationReportingChanges(
            atPath: dir,
            targetArchitecture: targetArch,
            signaturePolicy: signaturePolicy
        ) { changedPaths, thinningError in
            guard let changedPaths else {
                self.appState.appendLog(
                    "Failed to thin app: \(thinningError ?? "Unknown error")"
                )
                DispatchQueue.main.async {
                    self.appState.isProcessing = false
                }
                return
            }

            self.appState.appendLog("ARM64 thinning completed: \(changedPaths.count) binaries modified.")
            self.appState.appendLog("Original app size: \(originalSize) bytes")
            self.finishProcessing(
                directory: dir,
                universalApps: universalApps,
                success: true
            )
        }
    }

    private func finishProcessing(
        directory: String,
        universalApps: UniversalApps,
        success: Bool
    ) {
        let finalSize = universalApps.calculateDirectorySize(path: directory)
        DispatchQueue.main.async {
            self.appState.finalAppSize = finalSize
            self.appState.appendLog(
                success
                    ? "All binaries processed successfully."
                    : "Binary processing completed with signing errors."
            )
            self.appState.appendLog("Final App Size: \(finalSize) bytes")
            self.appState.isProcessing = false
        }
    }
    
    func getArchitectures(path: String) -> [String]? {
        MachOInspector.architectures(atPath: path)
    }

    func isUniversal(path: String, targetArch: String) -> String? {
        guard let archs = getArchitectures(path: path) else { return nil }
        return ArchitectureUtilities.preferredSlice(
            from: archs,
            targetArchitecture: targetArch
        )
    }
    
    func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
}
