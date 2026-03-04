import UIKit
import Flutter
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
    private let CHANNEL = "com.dk.three_sec/video_engine"

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
                      let outputPath = args["outputPath"] as? String,
                      let targetDurationMs = args["targetDurationMs"] as? NSNumber else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Invalid normalize arguments", details: nil))
                    return
                }

                self?.normalizeVideoDuration(
                    inputPath: inputPath,
                    outputPath: outputPath,
                    targetDurationMs: targetDurationMs.int64Value,
                    result: result
                )
            } else if call.method == "convertImageToVideo" {
                result(FlutterMethodNotImplemented)
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
        guard targetDurationMs > 0 else {
            result(FlutterError(code: "INVALID_DURATION", message: "targetDurationMs must be greater than 0", details: nil))
            return
        }

        let inputURL = URL(fileURLWithPath: inputPath)
        let asset = AVURLAsset(url: inputURL)
        let sourceDurationMs = Int64(asset.duration.seconds * 1000)
        if sourceDurationMs <= 0 {
            result(FlutterError(code: "INVALID_SOURCE_DURATION", message: "Could not determine source duration", details: nil))
            return
        }

        guard let sourceVideoTrack = asset.tracks(withMediaType: .video).first else {
            result(FlutterError(code: "INVALID_SOURCE", message: "Source video has no video track", details: nil))
            return
        }

        let composition = AVMutableComposition()
        guard let outputVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            result(FlutterError(code: "COMPOSITION_ERROR", message: "Failed to create output video track", details: nil))
            return
        }
        let outputAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        let sourceAudioTrack = asset.tracks(withMediaType: .audio).first
        var remainingMs = targetDurationMs
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
                result(FlutterError(code: "INSERT_ERROR", message: error.localizedDescription, details: nil))
                return
            }

            remainingMs -= clipMs
            currentTime = CMTimeAdd(currentTime, clipDuration)
        }

        if FileManager.default.fileExists(atPath: outputPath) {
            try? FileManager.default.removeItem(atPath: outputPath)
        }

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1920x1080) else {
            result(FlutterError(code: "EXPORT_SESSION_ERROR", message: "Failed to create export session", details: nil))
            return
        }

        exporter.outputURL = URL(fileURLWithPath: outputPath)
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        exporter.timeRange = CMTimeRange(start: .zero, duration: CMTime(value: targetDurationMs, timescale: 1000))

        exporter.exportAsynchronously {
            DispatchQueue.main.async {
                switch exporter.status {
                case .completed:
                    result("SUCCESS")
                case .failed:
                    result(FlutterError(code: "EXPORT_FAILED", message: exporter.error?.localizedDescription, details: nil))
                case .cancelled:
                    result(FlutterError(code: "EXPORT_CANCELLED", message: "Export cancelled", details: nil))
                default:
                    result(FlutterError(code: "UNKNOWN_ERROR", message: "Unknown export status: \(exporter.status)", details: nil))
                }
            }
        }
    }
}
