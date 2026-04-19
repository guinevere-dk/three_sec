import UIKit
import Flutter
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
    private let CHANNEL = "com.dk.three_sec/video_engine"
    private let DEFAULT_TARGET_DURATION_MS: Int64 = 2000

    private func reportChannelError(
        step: String,
        platformError: String,
        message: String,
        result: @escaping FlutterResult,
        details: Any? = nil
    ) {
        NSLog("[3S_CHANNEL] step=\(step) platformError=\(platformError) message=\(message)")
        result(FlutterError(code: platformError, message: message, details: details))
    }

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
        let channel = FlutterMethodChannel(name: CHANNEL, binaryMessenger: controller.binaryMessenger)

        channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            if call.method == "mergeVideos" {
                guard let args = call.arguments as? [String: Any],
                      let paths = args["paths"] as? [String],
                      let outputPath = args["outputPath"] as? String else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
                    return
                }

                self?.mergeVideos(paths: paths, outputPath: outputPath, result: result)
            } else if call.method == "normalizeVideoDuration" {
                guard let args = call.arguments as? [String: Any],
                      let inputPath = args["inputPath"] as? String,
                      let outputPath = args["outputPath"] as? String else {
                    self?.reportChannelError(
                        step: "normalize",
                        platformError: "INVALID_ARGS",
                        message: "Invalid normalize arguments",
                        result: result
                    )
                    return
                }

                let rawTargetDuration = args["targetDurationMs"]
                let parsedTargetDurationMs: Int64 = {
                    switch rawTargetDuration {
                    case let value as NSNumber:
                        return value.int64Value
                    case let value as String:
                        return Int64(value) ?? DEFAULT_TARGET_DURATION_MS
                    default:
                        return DEFAULT_TARGET_DURATION_MS
                    }
                }()

                let targetDurationMs = parsedTargetDurationMs > 0 ? parsedTargetDurationMs : DEFAULT_TARGET_DURATION_MS

                self?.normalizeVideoDuration(
                    inputPath: inputPath,
                    outputPath: outputPath,
                    targetDurationMs: targetDurationMs,
                    result: result
                )
            } else if call.method == "convertImageToVideo" {
                self?.reportChannelError(
                    step: "photo_to_video",
                    platformError: "METHOD_NOT_IMPLEMENTED",
                    message: "convertImageToVideo is not implemented on iOS",
                    result: result
                )
            } else {
                result(FlutterMethodNotImplemented)
            }
        }

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func mergeVideos(paths: [String], outputPath: String, result: @escaping FlutterResult) {
        let composition = AVMutableComposition()
        let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        var currentTime = CMTime.zero

        for path in paths {
            let asset = AVURLAsset(url: URL(fileURLWithPath: path))
            do {
                if let assetVideoTrack = asset.tracks(withMediaType: .video).first {
                    try videoTrack?.insertTimeRange(
                        CMTimeRange(start: .zero, duration: asset.duration),
                        of: assetVideoTrack,
                        at: currentTime
                    )
                }
                if let assetAudioTrack = asset.tracks(withMediaType: .audio).first {
                    try audioTrack?.insertTimeRange(
                        CMTimeRange(start: .zero, duration: asset.duration),
                        of: assetAudioTrack,
                        at: currentTime
                    )
                }
                currentTime = CMTimeAdd(currentTime, asset.duration)
            } catch {
                result(FlutterError(code: "MERGE_ERROR", message: "Failed to merge clip: \(error.localizedDescription)", details: nil))
                return
            }
        }

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1920x1080) else {
            result(FlutterError(code: "EXPORT_SESSION_ERROR", message: "Failed to create export session", details: nil))
            return
        }

        if FileManager.default.fileExists(atPath: outputPath) {
            try? FileManager.default.removeItem(atPath: outputPath)
        }

        exportSession.outputURL = URL(fileURLWithPath: outputPath)
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                switch exportSession.status {
                case .completed:
                    result("SUCCESS")
                case .failed:
                    result(FlutterError(code: "EXPORT_FAILED", message: exportSession.error?.localizedDescription, details: nil))
                case .cancelled:
                    result(FlutterError(code: "EXPORT_CANCELLED", message: "Export cancelled", details: nil))
                default:
                    result(FlutterError(code: "UNKNOWN_ERROR", message: "Unknown error during export", details: nil))
                }
            }
        }
    }

    private func normalizeVideoDuration(
        inputPath: String,
        outputPath: String,
        targetDurationMs: Int64,
        result: @escaping FlutterResult
    ) {
        let safeTargetDurationMs = targetDurationMs > 0 ? targetDurationMs : DEFAULT_TARGET_DURATION_MS

        let inputURL = URL(fileURLWithPath: inputPath)
        let asset = AVURLAsset(url: inputURL)
        let sourceDurationMs = Int64(asset.duration.seconds * 1000)
        if sourceDurationMs <= 0 {
            reportChannelError(
                step: "normalize",
                platformError: "INVALID_SOURCE_DURATION",
                message: "Could not determine source duration",
                result: result
            )
            return
        }
        NSLog("[3S_NORMALIZE] normalizeVideoDuration sourceDurationMs=\(sourceDurationMs) targetDurationMs=\(safeTargetDurationMs)")

        guard let sourceVideoTrack = asset.tracks(withMediaType: .video).first else {
            reportChannelError(
                step: "normalize",
                platformError: "INVALID_SOURCE",
                message: "Source video has no video track",
                result: result
            )
            return
        }

        let composition = AVMutableComposition()
        guard let outputVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            reportChannelError(
                step: "normalize",
                platformError: "COMPOSITION_ERROR",
                message: "Failed to create output video track",
                result: result
            )
            return
        }
        let outputAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        let sourceAudioTrack = asset.tracks(withMediaType: .audio).first
        var remainingMs = safeTargetDurationMs
        var currentTime = CMTime.zero

        while remainingMs > 0 {
            let clipMs = min(remainingMs, sourceDurationMs)
            let clipDuration = CMTime(value: clipMs, timescale: 1000)

            do {
                try outputVideoTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: clipDuration),
                    of: sourceVideoTrack,
                    at: currentTime
                )
                if let sourceAudioTrack = sourceAudioTrack {
                    try outputAudioTrack?.insertTimeRange(
                        CMTimeRange(start: .zero, duration: clipDuration),
                        of: sourceAudioTrack,
                        at: currentTime
                    )
                }
            } catch {
                reportChannelError(
                    step: "normalize",
                    platformError: "INSERT_ERROR",
                    message: error.localizedDescription,
                    result: result
                )
                return
            }

            remainingMs -= clipMs
            currentTime = CMTimeAdd(currentTime, clipDuration)
        }

        if FileManager.default.fileExists(atPath: outputPath) {
            try? FileManager.default.removeItem(atPath: outputPath)
        }

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1920x1080) else {
            reportChannelError(
                step: "normalize",
                platformError: "EXPORT_SESSION_ERROR",
                message: "Failed to create export session",
                result: result
            )
            return
        }

        exporter.outputURL = URL(fileURLWithPath: outputPath)
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        exporter.timeRange = CMTimeRange(start: .zero, duration: CMTime(value: safeTargetDurationMs, timescale: 1000))

        exporter.exportAsynchronously {
            DispatchQueue.main.async {
                switch exporter.status {
                case .completed:
                    let outputAsset = AVURLAsset(url: URL(fileURLWithPath: outputPath))
                    let normalizedDurationMs = Int64(outputAsset.duration.seconds * 1000)
                    NSLog(
                        "[3S_NORMALIZE] normalizeVideoDuration complete " +
                        "sourceDurationMs=\(sourceDurationMs) " +
                        "targetDurationMs=\(safeTargetDurationMs) " +
                        "normalizedDurationMs=\(normalizedDurationMs)"
                    )
                    result("SUCCESS")
                case .failed:
                    self.reportChannelError(
                        step: "normalize",
                        platformError: "EXPORT_FAILED",
                        message: exporter.error?.localizedDescription ?? "Unknown export failure",
                        result: result
                    )
                case .cancelled:
                    self.reportChannelError(
                        step: "normalize",
                        platformError: "EXPORT_CANCELLED",
                        message: "Export cancelled",
                        result: result
                    )
                default:
                    self.reportChannelError(
                        step: "normalize",
                        platformError: "UNKNOWN_ERROR",
                        message: "Unknown export status: \(exporter.status)",
                        result: result
                    )
                }
            }
        }
    }
}
