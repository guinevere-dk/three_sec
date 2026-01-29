package com.dk.three_sec

import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.graphics.Color
import android.text.SpannableString
import android.text.style.ForegroundColorSpan
import android.text.style.AbsoluteSizeSpan
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// 💡 Media3 & Guava Imports
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.Effects
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.TextOverlay
import androidx.media3.effect.StaticOverlaySettings
import com.google.common.collect.ImmutableList
import java.io.File

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.dk.three_sec/video_engine"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "mergeVideos" -> {
                    val paths = call.argument<List<String>>("paths")
                    val outputPath = call.argument<String>("outputPath")
                    val watermarkText = call.argument<String>("watermarkText") ?: "made with 3s"
                    
                    if (paths != null && outputPath != null && paths.isNotEmpty()) {
                        mergeVideos(paths, outputPath, watermarkText, result)
                    } else {
                        result.error("INVALID_ARGS", "파일 경로가 비어있습니다.", null)
                    }
                }
                "convertImageToVideo" -> {
                    result.notImplemented()
                }
                else -> result.notImplemented()
            }
        }
    }

    // 🎥 Media3 Transformer + Watermark Effect Engine (수정됨)
    private fun mergeVideos(paths: List<String>, outputPath: String, watermarkText: String, result: MethodChannel.Result) {
        
        // 1. [수정] 텍스트 디자인 및 투명도 설정 (setAlpha 대체)
        val span = SpannableString(watermarkText)
        // ARGB(178, 255, 255, 255) -> 약 70% 투명도의 흰색
        span.setSpan(ForegroundColorSpan(Color.argb(178, 255, 255, 255)), 0, span.length, 0)

        // 2. [수정] 위치 설정 (setAlpha 제거, 위치만 지정)
        val overlaySettings = StaticOverlaySettings.Builder()
            .setOverlayFrameAnchor(0.9f, -0.9f) // 우측 하단
            .setBackgroundFrameAnchor(0.9f, -0.9f)
            .build()
            
        // 3. [핵심 수정] TextOverlay 생성 시 설정(Settings)을 함께 전달
        val textOverlay = TextOverlay.createStaticTextOverlay(span, overlaySettings)

        // 4. [수정] 타입 불일치 해결 (ImmutableList -> Kotlin List)
        // TextureOverlay 타입으로 명시적 리스트 생성
        val overlayEffect = OverlayEffect(listOf(textOverlay))

        val editedMediaItems = ArrayList<EditedMediaItem>()
        for (path in paths) {
            val mediaItem = MediaItem.fromUri(Uri.parse(path))
            
            // 5. [수정] Effects 리스트도 Kotlin 표준 리스트 사용
            val effects = Effects(
                listOf(), // Audio effects
                listOf(overlayEffect) // Video effects
            )

            editedMediaItems.add(
                EditedMediaItem.Builder(mediaItem)
                    .setEffects(effects)
                    .build()
            )
        }

        // 6. 시퀀스 및 컴포지션 생성
        val sequence = EditedMediaItemSequence(editedMediaItems)
        val composition = Composition.Builder(listOf(sequence)).build()

        // 7. Transformer 설정 및 실행
        val transformer = Transformer.Builder(context)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    Handler(Looper.getMainLooper()).post {
                        result.success("SUCCESS")
                    }
                }

                override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                    Handler(Looper.getMainLooper()).post {
                        result.error("EXPORT_FAILED", "Media3 Error: ${exportException.message}", null)
                    }
                }
            })
            .build()

        // 파일 정리
        val file = File(outputPath)
        if (file.exists()) file.delete()

        // 엔진 가동
        transformer.start(composition, outputPath)
    }
}