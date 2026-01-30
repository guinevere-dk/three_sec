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
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.TextOverlay
import androidx.media3.effect.StaticOverlaySettings
import java.io.File
import android.util.Log

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
                    val watermarkText = call.argument<String>("watermarkText") ?: ""
                    val forceWatermark = call.argument<Boolean>("forceWatermark") ?: false
                    val quality = call.argument<String>("quality") ?: "1080p"
                    
                    Log.d("3S_IAP", "mergeVideos 호출: forceWatermark=$forceWatermark, watermarkText='$watermarkText', quality=$quality")
                    
                    if (paths != null && outputPath != null && paths.isNotEmpty()) {
                        mergeVideos(paths, outputPath, watermarkText, forceWatermark, quality, result)
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

    private fun mergeVideos(
        paths: List<String>, 
        outputPath: String, 
        watermarkText: String, 
        forceWatermark: Boolean,
        quality: String,
        result: MethodChannel.Result
    ) {
        Log.d("3S_IAP", "병합 시작: ${paths.size}개 클립, forceWatermark=$forceWatermark")
        
        // 1. 워터마크 준비 (forceWatermark가 true일 때만)
        val overlayEffect: OverlayEffect? = if (forceWatermark && watermarkText.isNotEmpty()) {
            // 1-1. 스타일링된 워터마크 텍스트 생성
            val displayText = if (watermarkText.isEmpty()) "Made with 3S" else watermarkText
            val watermark = SpannableString(displayText)
            val totalLen = watermark.length
            
            // 투명도가 적용된 컬러
            val watermarkColor = Color.argb(WATERMARK_ALPHA, 255, 255, 255)
            
            // "Made with" 부분 스타일링 (0~9)
            if (totalLen > 9) {
                watermark.setSpan(TypefaceSpan("serif"), 0, 9, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                watermark.setSpan(RelativeSizeSpan(0.8f), 0, 9, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                watermark.setSpan(ForegroundColorSpan(watermarkColor), 0, 9, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                
                // "3S" 부분 스타일링 (10~끝)
                watermark.setSpan(StyleSpan(Typeface.BOLD), 10, totalLen, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                watermark.setSpan(ForegroundColorSpan(Color.WHITE), 10, totalLen, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
            } else {
                // 텍스트가 짧으면 전체에 기본 스타일 적용
                watermark.setSpan(ForegroundColorSpan(watermarkColor), 0, totalLen, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
            }

            // 1-2. 오버레이 위치 설정 (우측 하단)
            val overlaySettings = StaticOverlaySettings.Builder()
                .setOverlayFrameAnchor(WATERMARK_POS_X, WATERMARK_POS_Y)
                .setBackgroundFrameAnchor(WATERMARK_POS_X, WATERMARK_POS_Y)
                .setScale(WATERMARK_SCALE_X, WATERMARK_SCALE_Y)
                .build()

            // 1-3. TextOverlay 생성
            val textOverlay = TextOverlay.createStaticTextOverlay(watermark, overlaySettings)
            
            Log.d("3S_IAP", "✓ 워터마크 생성: '$displayText'")
            OverlayEffect(listOf(textOverlay))
        } else {
            Log.d("3S_IAP", "✓ 워터마크 없음 (Premium/Standard 사용자)")
            null
        }

        // 2. EditedMediaItem 리스트 생성
        val editedMediaItems = ArrayList<EditedMediaItem>()
        for (path in paths) {
            val mediaItem = MediaItem.fromUri(Uri.parse(path))
            
            // 워터마크 여부에 따라 Effects 적용
            val effects = if (overlayEffect != null) {
                Effects(listOf(), listOf(overlayEffect))
            } else {
                // 워터마크가 없으면 Effects 없이 깨끗하게 병합
                Effects(listOf(), listOf())
            }

            editedMediaItems.add(
                EditedMediaItem.Builder(mediaItem)
                    .setEffects(effects)
                    .build()
            )
        }

        // 3. 시퀀스 및 Composition 생성
        val sequence = EditedMediaItemSequence(editedMediaItems)
        val composition = Composition.Builder(listOf(sequence)).build()

        // 4. 하드웨어 가속 Encoder Factory 설정 (1080p 최적화)
        // enableFallback=true로 하드웨어 실패 시 소프트웨어 폴백 보장
        val encoderFactory = DefaultEncoderFactory.Builder(context.applicationContext)
            .setEnableFallback(true)
            .build()

        // 5. Transformer 구성 (고해상도 최적화 + 하드웨어 가속)
        val transformerBuilder = Transformer.Builder(context)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .setEncoderFactory(encoderFactory)
        
        // 1080p 고화질 요청 시 추가 설정
        // (실제 해상도는 입력 영상 기준으로 자동 결정되지만, 비트레이트 힌트를 줄 수 있음)
        if (quality.contains("1080")) {
            Log.d("3S_IAP", "1080p 고화질 모드 활성화")
            // 추가 최적화 설정 가능 (Media3의 최신 API에 따라 조정)
        }
        
        val transformer = transformerBuilder
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    Log.d("3S_IAP", "✓ 병합 완료: $outputPath")
                    Log.d("3S_IAP", "  - 파일 크기: ${exportResult.fileSizeBytes / 1024 / 1024}MB")
                    Log.d("3S_IAP", "  - 처리 시간: ${exportResult.durationMs}ms")
                    Handler(Looper.getMainLooper()).post { 
                        result.success("SUCCESS") 
                    }
                }

                override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                    Log.e("3S_IAP", "✗ 병합 실패: ${exportException.message}", exportException)
                    Handler(Looper.getMainLooper()).post {
                        result.error("EXPORT_FAILED", "Media3 Error: ${exportException.message}", null)
                    }
                }
            })
            .build()

        // 6. 출력 파일 준비 및 병합 시작
        val file = File(outputPath)
        if (file.exists()) {
            Log.d("3S_IAP", "기존 파일 삭제: $outputPath")
            file.delete()
        }

        Log.d("3S_IAP", "Transformer 시작...")
        transformer.start(composition, outputPath)
    }
}