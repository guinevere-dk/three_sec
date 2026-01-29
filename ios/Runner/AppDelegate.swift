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
            } else if call.method == "convertImageToVideo" {
                // 추후 구현 예정
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
        
        // 1. 영상 트랙 병합
        for path in paths {
            let asset = AVURLAsset(url: URL(fileURLWithPath: path))
            do {
                if let assetVideoTrack = asset.tracks(withMediaType: .video).first {
                    try videoTrack?.insertTimeRange(CMTimeRangeMake(start: .zero, duration: asset.duration), of: assetVideoTrack, at: currentTime)
                }
                if let assetAudioTrack = asset.tracks(withMediaType: .audio).first {
                    try audioTrack?.insertTimeRange(CMTimeRangeMake(start: .zero, duration: asset.duration), of: assetAudioTrack, at: currentTime)
                }
                currentTime = CMTimeAdd(currentTime, asset.duration)
            } catch {
                result(FlutterError(code: "MERGE_ERROR", message: "Failed to merge clip: \(error.localizedDescription)", details: nil))
                return
            }
        }
        
        // 2. 내보내기 세션 설정
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1920x1080) else {
            result(FlutterError(code: "EXPORT_SESSION_ERROR", message: "Failed to create export session", details: nil))
            return
        }
        
        exportSession.outputURL = URL(fileURLWithPath: outputPath)
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        // 3. 기존 파일 삭제 및 내보내기 시작
        if FileManager.default.fileExists(atPath: outputPath) {
            try? FileManager.default.removeItem(atPath: outputPath)
        }
        
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
}