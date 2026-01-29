package com.dk.three_sec

import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.graphics.Color
import android.graphics.Typeface
import android.text.Spannable
import android.text.SpannableString
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.text.style.TypefaceSpan
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.text.style.RelativeSizeSpan

// Media3 Imports
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
import java.io.File

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.dk.three_sec/video_engine"

    // 🎛️ [디자인 컨트롤 타워] 여기서 수치만 바꾸면 즉시 반영됩니다.
    companion object {
        // 투명도 (0: 투명 ~ 255: 불투명) -> 180는 약 40% 농도
        private const val WATERMARK_ALPHA = 160
        
        // 크기 (1.0 = 화면 꽉 참) -> 가로 8%, 세로 3% 크기
        private const val WATERMARK_SCALE_X = 0.35f
        private const val WATERMARK_SCALE_Y = 0.4f
        
        // 위치 (-1.0 ~ 1.0) -> (1, -1)이 우측 하단 끝
        // 0.95는 끝에서 약간 띄운 여백
        private const val WATERMARK_POS_X = 0.90f
        private const val WATERMARK_POS_Y = -0.90f
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "mergeVideos" -> {
                    val paths = call.argument<List<String>>("paths")
                    val outputPath = call.argument<String>("outputPath")
                    val watermarkText = call.argument<String>("watermarkText") ?: "Made with 3S"
                    
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

    private fun mergeVideos(paths: List<String>, outputPath: String, watermarkTextRaw: String, result: MethodChannel.Result) {
        
        // 1. [디자인] 복합 스타일링 및 투명도 통합 설정
        val watermark = SpannableString("Made with 3S")
        val totalLen = watermark.length
        
        // 💡 투명도 상수를 ARGB 컬러에 직접 적용하여 setAlpha 에러 원천 차단
        // WATERMARK_ALPHA(160) 값을 사용하여 약 62% 투명도의 흰색 적용
        val watermarkColor = Color.argb(WATERMARK_ALPHA, 255, 255, 255)
        
        // "Made with" 부분 (0~9): Serif 서체 + 0.8배 크기
        watermark.setSpan(TypefaceSpan("serif"), 0, 9, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        watermark.setSpan(RelativeSizeSpan(0.8f), 0, 9, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        watermark.setSpan(ForegroundColorSpan(watermarkColor), 0, 9, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        
        // "3S" 부분 (10~12): BOLD 스타일 + 강조 컬러
        watermark.setSpan(StyleSpan(Typeface.BOLD), 10, totalLen, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        watermark.setSpan(ForegroundColorSpan(Color.WHITE), 10, totalLen, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)

        // 2. [수정] 오버레이 설정 (setAlpha 제거)
        // 💡 에러가 발생한 .setAlpha()를 제거하고 위치와 스케일만 정의합니다.
        val overlaySettings = StaticOverlaySettings.Builder()
            .setOverlayFrameAnchor(WATERMARK_POS_X, WATERMARK_POS_Y)
            .setBackgroundFrameAnchor(WATERMARK_POS_X, WATERMARK_POS_Y)
            .setScale(WATERMARK_SCALE_X, WATERMARK_SCALE_Y)
            .build()

        // 3. TextOverlay 생성 및 설정 주입
        val textOverlay = TextOverlay.createStaticTextOverlay(watermark, overlaySettings)

        // 4. Effect 레이어 구성 (기존과 동일)
        val overlayEffect = OverlayEffect(listOf(textOverlay))

        val editedMediaItems = ArrayList<EditedMediaItem>()
        for (path in paths) {
            val mediaItem = MediaItem.fromUri(Uri.parse(path))
            val effects = Effects(listOf(), listOf(overlayEffect))

            editedMediaItems.add(
                EditedMediaItem.Builder(mediaItem)
                    .setEffects(effects)
                    .build()
            )
        }

        // 5. 시퀀스 및 Transformer 실행 로직
        val sequence = EditedMediaItemSequence(editedMediaItems)
        val composition = Composition.Builder(listOf(sequence)).build()

        val transformer = Transformer.Builder(context)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    Handler(Looper.getMainLooper()).post { result.success("SUCCESS") }
                }

                override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                    Handler(Looper.getMainLooper()).post {
                        result.error("EXPORT_FAILED", "Media3 Error: ${exportException.message}", null)
                    }
                }
            })
            .build()

        val file = File(outputPath)
        if (file.exists()) file.delete()

        transformer.start(composition, outputPath)
    }
}