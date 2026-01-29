package com.dk.three_sec

import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// 💡 Media3 (Native Engine) Imports
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import java.io.File

class MainActivity: FlutterActivity() {
    // 💡 Flutter와 통신할 채널명 (main.dart와 일치해야 함)
    private val CHANNEL = "com.dk.three_sec/video_engine"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "mergeVideos" -> {
                    val paths = call.argument<List<String>>("paths")
                    val outputPath = call.argument<String>("outputPath")
                    
                    if (paths != null && outputPath != null && paths.isNotEmpty()) {
                        mergeVideos(paths, outputPath, result)
                    } else {
                        result.error("INVALID_ARGS", "파일 경로가 비어있습니다.", null)
                    }
                }
                "convertImageToVideo" -> {
                    // 추후 사진 -> 영상 변환 로직 구현 공간 (현재는 미구현 응답)
                    result.notImplemented()
                }
                else -> result.notImplemented()
            }
        }
    }

    // 🎥 [핵심] Media3 Transformer를 이용한 초고속 병합 엔진
    private fun mergeVideos(paths: List<String>, outputPath: String, result: MethodChannel.Result) {
        // 1. 입력 파일들을 MediaItem으로 변환
        val editedMediaItems = ArrayList<EditedMediaItem>()
        for (path in paths) {
            val mediaItem = MediaItem.fromUri(Uri.parse(path))
            // 필요 시 여기서 Effects(워터마크, 필터 등)를 추가할 수 있습니다.
            editedMediaItems.add(EditedMediaItem.Builder(mediaItem).build())
        }

        // 2. 시퀀스 생성 (영상들을 순서대로 배열)
        val sequence = EditedMediaItemSequence(editedMediaItems)
        val composition = Composition.Builder(listOf(sequence)).build()

        // 3. Transformer 설정 (하드웨어 가속 자동 사용)
        val transformer = Transformer.Builder(context)
            .setVideoMimeType(MimeTypes.VIDEO_H264) // 호환성이 좋은 H.264 코덱 사용
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    // 💡 성공 시 UI 스레드에서 응답 전송
                    Handler(Looper.getMainLooper()).post {
                        result.success("SUCCESS")
                    }
                }

                override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                    // 💡 실패 시 에러 로그 전송
                    Handler(Looper.getMainLooper()).post {
                        result.error("EXPORT_FAILED", exportException.message, null)
                    }
                }
            })
            .build()

        // 4. 기존 파일이 있다면 삭제 후 시작
        val file = File(outputPath)
        if (file.exists()) {
            file.delete()
        }

        // 5. 엔진 시동
        transformer.start(composition, outputPath)
    }
}