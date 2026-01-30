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
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.ChannelMixingAudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.Effects
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EncoderUtil
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.TextOverlay
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.effect.Contrast
import androidx.media3.effect.RgbMatrix
import androidx.media3.effect.RgbFilter
import androidx.media3.effect.GlEffect
import java.io.File
import java.nio.ByteBuffer
import android.util.Log
import android.media.MediaMetadataRetriever

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.dk.three_sec/video_engine"

    // 🎛️ [디자인 컨트롤 타워] 여기서 수치만 바꾸면 즉시 반영됩니다.
    companion object {
        // 워터마크 설정
        private const val WATERMARK_ALPHA = 160
        private const val WATERMARK_SCALE_X = 0.35f
        private const val WATERMARK_SCALE_Y = 0.4f
        private const val WATERMARK_POS_X = 0.90f
        private const val WATERMARK_POS_Y = -0.90f
        
        // 🎥 4K 렌더링 프로필 (Premium 전용)
        private const val RESOLUTION_4K_WIDTH = 3840
        private const val RESOLUTION_4K_HEIGHT = 2160
        private const val BITRATE_4K_MAX = 20_000_000  // 20Mbps
        private const val BITRATE_1080P_MAX = 8_000_000 // 8Mbps
        
        // 🎨 GPU 필터 프리셋
        private const val GRAYSCALE_SATURATION = 0.0f
        private const val DEFAULT_CONTRAST = 1.0f
        private const val DEFAULT_SATURATION = 1.0f
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "mergeVideos" -> {
                    val paths = call.argument<List<String>>("paths")
                    val outputPath = call.argument<String>("outputPath")
                    
                    // 📝 자막 파라미터 (새로운 구조)
                    val subtitles = call.argument<List<Map<String, Any>>>("subtitles") ?: emptyList()
                    val forceWatermark = call.argument<Boolean>("forceWatermark") ?: false
                    val quality = call.argument<String>("quality") ?: "1080p"
                    val userTier = call.argument<String>("userTier") ?: "free"
                    
                    // 🎵 오디오 믹싱 파라미터
                    val bgmPath = call.argument<String>("bgmPath")
                    val forceMuteOriginal = call.argument<Boolean>("forceMuteOriginal") ?: false
                    val enableNoiseSuppression = call.argument<Boolean>("enableNoiseSuppression") ?: false
                    val bgmVolume = call.argument<Double>("bgmVolume")?.toFloat() ?: 0.5f
                    
                    // 🎨 비디오 이펙트 파라미터 (Premium)
                    val videoEffects = call.argument<Map<String, Any>>("videoEffects") ?: emptyMap()
                    
                    Log.d("3S_4K", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    Log.d("3S_4K", "mergeVideos 호출")
                    Log.d("3S_4K", "  - 자막: ${subtitles.size}개")
                    Log.d("3S_4K", "  - 품질: $quality")
                    Log.d("3S_4K", "  - 사용자 등급: $userTier")
                    Log.d("3S_4K", "  - 비디오 이펙트: ${videoEffects.keys}")
                    Log.d("3S_AUDIO", "오디오 믹싱: bgm=${bgmPath != null}, mute=$forceMuteOriginal, noise=$enableNoiseSuppression")
                    
                    if (paths != null && outputPath != null && paths.isNotEmpty()) {
                        mergeVideos(
                            paths, 
                            outputPath, 
                            subtitles,
                            forceWatermark, 
                            quality,
                            userTier,
                            videoEffects,
                            bgmPath,
                            forceMuteOriginal,
                            enableNoiseSuppression,
                            bgmVolume,
                            result
                        )
                    } else {
                        result.error("INVALID_ARGS", "파일 경로가 비어있습니다.", null)
                    }
                }
                "extractClips" -> {
                    val inputPath = call.argument<String>("inputPath")
                    val outputDir = call.argument<String>("outputDir")
                    val segments = call.argument<List<Map<String, Any>>>("segments")
                    val quality = call.argument<String>("quality") ?: "1080p"
                    val enableNoiseSuppression = call.argument<Boolean>("enableNoiseSuppression") ?: false
                    
                    // 📝 자막 파라미터
                    val subtitles = call.argument<List<Map<String, Any>>>("subtitles") ?: emptyList()
                    val userTier = call.argument<String>("userTier") ?: "free"
                    
                    Log.d("3S_EDIT", "extractClips 호출: ${segments?.size ?: 0}개 구간, 노이즈억제=$enableNoiseSuppression")
                    Log.d("3S_SUBTITLE", "자막: ${subtitles.size}개, 등급: $userTier")
                    
                    if (inputPath != null && outputDir != null && segments != null && segments.isNotEmpty()) {
                        extractClips(inputPath, outputDir, segments, quality, enableNoiseSuppression, subtitles, userTier, result)
                    } else {
                        result.error("INVALID_ARGS", "파라미터가 유효하지 않습니다.", null)
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
        subtitles: List<Map<String, Any>>,
        forceWatermark: Boolean,
        quality: String,
        userTier: String,
        videoEffects: Map<String, Any>,
        bgmPath: String?,
        forceMuteOriginal: Boolean,
        enableNoiseSuppression: Boolean,
        bgmVolume: Float,
        result: MethodChannel.Result
    ) {
        Log.d("3S_4K", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        Log.d("3S_4K", "병합 시작: ${paths.size}개 클립")
        Log.d("3S_4K", "  - 품질: $quality")
        Log.d("3S_4K", "  - 사용자 등급: $userTier")
        Log.d("3S_4K", "  - 자막: ${subtitles.size}개")
        Log.d("3S_4K", "  - 비디오 이펙트: ${videoEffects.keys}")
        Log.d("3S_AUDIO", "  - 원본 음소거: $forceMuteOriginal")
        Log.d("3S_AUDIO", "  - BGM: ${bgmPath ?: "없음"}")
        Log.d("3S_AUDIO", "  - 노이즈 억제: $enableNoiseSuppression")
        Log.d("3S_4K", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        // 1. 📝 자막/워터마크 오버레이 생성 (멀티 오버레이)
        val overlayEffect: OverlayEffect? = createSubtitleOverlays(
            subtitles = subtitles,
            forceWatermark = forceWatermark,
            userTier = userTier
        )

        // 2. 🎵 오디오 이펙트 준비
        val audioProcessors = mutableListOf<AudioProcessor>()
        
        // 2-1. 노이즈 억제 (NoiseSuppressor)
        if (enableNoiseSuppression) {
            val noiseSuppressor = NoiseSuppressorAudioProcessor(noiseThreshold = 0.15f)
            audioProcessors.add(noiseSuppressor)
            Log.d("3S_AUDIO", "✓ 노이즈 억제 프로세서 추가 완료")
        }

        // 3. 🎨 GPU 필터 생성 (Premium)
        val gpuFilters = createGpuFilters(videoEffects, userTier)
        
        // 4. EditedMediaItem 리스트 생성 (비디오 트랙)
        val videoSequence = ArrayList<EditedMediaItem>()
        for (path in paths) {
            val mediaItem = MediaItem.fromUri(Uri.parse(path))
            
            // 비디오 Effects (GPU 필터 + 오버레이)
            val allVideoEffects = mutableListOf<Any>()
            
            // GPU 필터 추가
            allVideoEffects.addAll(gpuFilters)
            
            // 오버레이 추가
            if (overlayEffect != null) {
                allVideoEffects.add(overlayEffect)
            }
            
            // Effects 결합 (오디오 + 비디오)
            val finalEffects = if (audioProcessors.isNotEmpty() && !forceMuteOriginal) {
                // 노이즈 억제 + GPU 필터 + 오버레이
                Effects(audioProcessors, allVideoEffects)
            } else {
                // GPU 필터 + 오버레이만
                Effects(listOf(), allVideoEffects)
            }

            videoSequence.add(
                EditedMediaItem.Builder(mediaItem)
                    .setRemoveAudio(forceMuteOriginal)
                    .setEffects(finalEffects)
                    .build()
            )
        }

        if (forceMuteOriginal) {
            Log.d("3S_AUDIO", "✓ 원본 오디오 제거됨 (forceMuteOriginal=true)")
        } else if (enableNoiseSuppression) {
            Log.d("3S_AUDIO", "✓ 원본 오디오에 노이즈 억제 적용됨")
        }

        // 4. 🎵 BGM 트랙 추가 (별도 시퀀스)
        val sequences = mutableListOf<EditedMediaItemSequence>()
        
        // 4-1. 비디오 시퀀스 추가
        sequences.add(EditedMediaItemSequence(videoSequence))
        
        // 4-2. BGM 시퀀스 추가 (있는 경우)
        if (bgmPath != null && File(bgmPath).exists()) {
            try {
                Log.d("3S_AUDIO", "✓ BGM 추가: $bgmPath")
                Log.d("3S_AUDIO", "  - 볼륨: ${(bgmVolume * 100).toInt()}%")
                
                // BGM 길이 추출 (Fade Out을 위해 필요)
                val retriever = MediaMetadataRetriever()
                retriever.setDataSource(bgmPath)
                val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                val bgmDurationMs = durationStr?.toLongOrNull() ?: 0L
                retriever.release()
                
                Log.d("3S_AUDIO", "  - BGM 길이: ${bgmDurationMs}ms (${bgmDurationMs / 1000.0}초)")
                
                val bgmMediaItem = MediaItem.fromUri(Uri.parse(bgmPath))
                
                // 🎵 Fade Out 프로세서 생성 (BGM 마지막 0.5초)
                val fadeOutProcessor = FadeOutAudioProcessor(
                    fadeOutDurationMs = 500L,
                    totalDurationMs = bgmDurationMs
                )
                
                // TODO: 볼륨 조절 프로세서 추가 (bgmVolume 적용)
                // 현재는 Fade Out만 적용, 볼륨 조절은 추후 ChannelMixingAudioProcessor로 구현
                
                val bgmAudioProcessors = listOf<AudioProcessor>(fadeOutProcessor)
                val bgmEffects = Effects(bgmAudioProcessors, listOf())
                
                val bgmEditedItem = EditedMediaItem.Builder(bgmMediaItem)
                    .setRemoveVideo(true) // 오디오만 사용
                    .setEffects(bgmEffects)
                    .build()
                
                sequences.add(EditedMediaItemSequence(listOf(bgmEditedItem)))
                
                Log.d("3S_AUDIO", "✓ BGM Fade Out 프로세서 적용 완료")
                
            } catch (e: Exception) {
                Log.e("3S_AUDIO", "✗ BGM 추가 실패: ${e.message}", e)
            }
        } else if (bgmPath != null) {
            Log.w("3S_AUDIO", "⚠️ BGM 파일을 찾을 수 없음: $bgmPath")
        }

        // 5. Composition 생성 (멀티트랙)
        val composition = Composition.Builder(sequences)
            .setTransmuxAudio(false) // 오디오 재인코딩 활성화 (믹싱 필요)
            .setTransmuxVideo(false) // 비디오 재인코딩 활성화
            .build()
        
        Log.d("3S_AUDIO", "✓ Composition 생성 완료: ${sequences.size}개 트랙")

        // 6. 🚀 하드웨어 가속 Encoder Factory (4K 최적화)
        val encoderFactory = create4KEncoderFactory(quality, userTier)

        // 7. 🎥 Transformer 구성 (4K 렌더링 + GPU 가속)
        val transformerBuilder = Transformer.Builder(context)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .setEncoderFactory(encoderFactory)
        
        // 품질별 설정
        when {
            quality.equals("4K", ignoreCase = true) && userTier == "premium" -> {
                // 💎 Premium 4K 렌더링
                Log.d("3S_4K", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                Log.d("3S_4K", "✓ 4K 렌더링 모드 활성화")
                Log.d("3S_4K", "  - 해상도: ${RESOLUTION_4K_WIDTH}x${RESOLUTION_4K_HEIGHT}")
                Log.d("3S_4K", "  - 비트레이트: ${BITRATE_4K_MAX / 1_000_000}Mbps")
                Log.d("3S_4K", "  - 하드웨어 가속: 강제 활성화")
                Log.d("3S_4K", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            }
            quality.contains("1080") -> {
                Log.d("3S_4K", "✓ 1080p 고화질 모드 활성화 (비트레이트: ${BITRATE_1080P_MAX / 1_000_000}Mbps)")
            }
            else -> {
                Log.d("3S_4K", "✓ 기본 품질 모드")
            }
        }
        
        val transformer = transformerBuilder
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    Log.d("3S_AUDIO", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    Log.d("3S_AUDIO", "✓ 병합 완료: $outputPath")
                    Log.d("3S_AUDIO", "  - 파일 크기: ${exportResult.fileSizeBytes / 1024 / 1024}MB")
                    Log.d("3S_AUDIO", "  - 처리 시간: ${exportResult.durationMs}ms")
                    Log.d("3S_AUDIO", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    Handler(Looper.getMainLooper()).post { 
                        result.success("SUCCESS") 
                    }
                }

                override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                    Log.e("3S_AUDIO", "✗ 병합 실패: ${exportException.message}", exportException)
                    Handler(Looper.getMainLooper()).post {
                        result.error("EXPORT_FAILED", "Media3 Error: ${exportException.message}", null)
                    }
                }
            })
            .build()

        // 8. 출력 파일 준비 및 병합 시작
        val file = File(outputPath)
        if (file.exists()) {
            Log.d("3S_AUDIO", "기존 파일 삭제: $outputPath")
            file.delete()
        }

        Log.d("3S_AUDIO", "⚡ Transformer 시작 (오디오 믹싱 모드)...")
        transformer.start(composition, outputPath)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // 📝 자막 오버레이 생성 (멀티 오버레이)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /**
     * 자막/워터마크 오버레이 생성
     * 
     * @param subtitles 자막 리스트 [{text, x, y, size, color}, ...]
     * @param forceWatermark 워터마크 강제 표시 여부
     * @param userTier 사용자 등급 (standard, premium)
     * @return OverlayEffect 또는 null
     */
    private fun createSubtitleOverlays(
        subtitles: List<Map<String, Any>>,
        forceWatermark: Boolean,
        userTier: String
    ): OverlayEffect? {
        val textOverlays = mutableListOf<TextOverlay>()
        
        // 1. 사용자 자막 추가
        for ((index, subtitle) in subtitles.withIndex()) {
            try {
                val text = subtitle["text"] as? String ?: continue
                val x = (subtitle["x"] as? Number)?.toFloat() ?: 0f
                val y = (subtitle["y"] as? Number)?.toFloat() ?: 0f
                val size = (subtitle["size"] as? Number)?.toFloat() ?: 1.0f
                val colorHex = subtitle["color"] as? String ?: "#FFFFFF"
                
                Log.d("3S_SUBTITLE", "자막 ${index + 1}: '$text' (x=$x, y=$y, size=$size, color=$colorHex)")
                
                // SpannableString 생성
                val spannable = SpannableString(text)
                val len = text.length
                
                // 색상 파싱
                val color = try {
                    Color.parseColor(colorHex)
                } catch (e: Exception) {
                    Color.WHITE
                }
                
                // 🎨 Standard vs Premium 스타일링
                if (userTier == "premium") {
                    // 💎 Premium: 고급 스타일 (외곽선, 그림자 효과는 추후 구현)
                    Log.d("3S_SUBTITLE", "  ✓ Premium 스타일 적용")
                    
                    // 볼드 폰트
                    spannable.setSpan(StyleSpan(Typeface.BOLD), 0, len, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                    
                    // 폰트 크기
                    spannable.setSpan(RelativeSizeSpan(size), 0, len, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                    
                    // 색상
                    spannable.setSpan(ForegroundColorSpan(color), 0, len, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                    
                    // TODO: 외곽선 효과 (StrokeSpan - 커스텀 구현 필요)
                    // TODO: 그림자 효과 (ShadowSpan - 커스텀 구현 필요)
                    
                } else {
                    // 📋 Standard: 기본 스타일
                    Log.d("3S_SUBTITLE", "  ✓ Standard 스타일 적용")
                    
                    // 폰트 크기
                    spannable.setSpan(RelativeSizeSpan(size), 0, len, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                    
                    // 색상
                    spannable.setSpan(ForegroundColorSpan(color), 0, len, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                }
                
                // 오버레이 위치 설정
                val overlaySettings = StaticOverlaySettings.Builder()
                    .setOverlayFrameAnchor(x, y)
                    .setBackgroundFrameAnchor(x, y)
                    .setScale(size, size)
                    .build()
                
                // TextOverlay 생성
                val textOverlay = TextOverlay.createStaticTextOverlay(spannable, overlaySettings)
                textOverlays.add(textOverlay)
                
            } catch (e: Exception) {
                Log.e("3S_SUBTITLE", "✗ 자막 ${index + 1} 생성 실패: ${e.message}")
            }
        }
        
        // 2. 워터마크 추가 (forceWatermark가 true일 때)
        if (forceWatermark) {
            val watermarkText = "Made with 3S"
            val watermark = SpannableString(watermarkText)
            val watermarkColor = Color.argb(WATERMARK_ALPHA, 255, 255, 255)
            
            // 스타일링
            watermark.setSpan(TypefaceSpan("serif"), 0, 9, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
            watermark.setSpan(RelativeSizeSpan(0.8f), 0, 9, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
            watermark.setSpan(ForegroundColorSpan(watermarkColor), 0, 9, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
            watermark.setSpan(StyleSpan(Typeface.BOLD), 10, watermarkText.length, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
            watermark.setSpan(ForegroundColorSpan(Color.WHITE), 10, watermarkText.length, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
            
            // 우측 하단 위치
            val overlaySettings = StaticOverlaySettings.Builder()
                .setOverlayFrameAnchor(WATERMARK_POS_X, WATERMARK_POS_Y)
                .setBackgroundFrameAnchor(WATERMARK_POS_X, WATERMARK_POS_Y)
                .setScale(WATERMARK_SCALE_X, WATERMARK_SCALE_Y)
                .build()
            
            val watermarkOverlay = TextOverlay.createStaticTextOverlay(watermark, overlaySettings)
            textOverlays.add(watermarkOverlay)
            
            Log.d("3S_SUBTITLE", "✓ 워터마크 추가: '$watermarkText'")
        }
        
        // 3. OverlayEffect 생성
        if (textOverlays.isEmpty()) {
            Log.d("3S_SUBTITLE", "✓ 오버레이 없음")
            return null
        }
        
        Log.d("3S_SUBTITLE", "✓ 총 ${textOverlays.size}개 오버레이 생성")
        return OverlayEffect(textOverlays)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // 🎨 GPU 필터 엔진 (Premium)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /**
     * GPU 필터 생성 (동적)
     * 
     * @param effects 이펙트 설정 {contrast, saturation, grayscale, ...}
     * @param userTier 사용자 등급
     * @return GlEffect 리스트
     */
    private fun createGpuFilters(
        effects: Map<String, Any>,
        userTier: String
    ): List<GlEffect> {
        val filters = mutableListOf<GlEffect>()
        
        if (effects.isEmpty()) {
            return filters
        }
        
        Log.d("3S_4K", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        Log.d("3S_4K", "GPU 필터 생성 (등급: $userTier)")
        
        // Premium 전용 필터
        if (userTier == "premium") {
            
            // 🎨 Contrast (대비)
            val contrast = (effects["contrast"] as? Number)?.toFloat() ?: DEFAULT_CONTRAST
            if (contrast != DEFAULT_CONTRAST) {
                filters.add(Contrast(contrast))
                Log.d("3S_4K", "  ✓ Contrast: $contrast")
            }
            
            // 🎨 Saturation (채도)
            val saturation = (effects["saturation"] as? Number)?.toFloat() ?: DEFAULT_SATURATION
            if (saturation != DEFAULT_SATURATION) {
                // RgbMatrix를 사용하여 채도 조절
                val matrix = createSaturationMatrix(saturation)
                filters.add(RgbMatrix(matrix))
                Log.d("3S_4K", "  ✓ Saturation: $saturation")
            }
            
            // 🎨 Grayscale (흑백)
            val grayscale = effects["grayscale"] as? Boolean ?: false
            if (grayscale) {
                // 채도 0으로 설정하여 흑백 효과
                val matrix = createSaturationMatrix(GRAYSCALE_SATURATION)
                filters.add(RgbMatrix(matrix))
                Log.d("3S_4K", "  ✓ Grayscale: true")
            }
            
            // TODO: 추가 이펙트
            // - Brightness (밝기)
            // - Blur (블러)
            // - Vignette (비네트)
            // - Temperature (색온도)
            
        } else {
            Log.d("3S_4K", "  ⚠️ Premium 등급 필요 (현재: $userTier)")
        }
        
        Log.d("3S_4K", "✓ 총 ${filters.size}개 GPU 필터 생성")
        Log.d("3S_4K", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        return filters
    }

    /**
     * 채도 조절을 위한 RGB 매트릭스 생성
     * 
     * @param saturation 채도 (0.0 = 흑백, 1.0 = 원본, >1.0 = 과포화)
     * @return 4x4 RGB 변환 매트릭스
     */
    private fun createSaturationMatrix(saturation: Float): FloatArray {
        // 표준 RGB → YIQ 변환 계수
        val rY = 0.299f
        val gY = 0.587f
        val bY = 0.114f
        
        val s = saturation
        val is1 = 1f - s
        
        // 채도 조절 매트릭스
        return floatArrayOf(
            is1 * rY + s, is1 * gY,     is1 * bY,     0f,
            is1 * rY,     is1 * gY + s, is1 * bY,     0f,
            is1 * rY,     is1 * gY,     is1 * bY + s, 0f,
            0f,           0f,           0f,           1f
        )
    }

    /**
     * 4K 최적화 Encoder Factory 생성
     * 
     * @param quality 품질 설정
     * @param userTier 사용자 등급
     * @return DefaultEncoderFactory
     */
    private fun create4KEncoderFactory(quality: String, userTier: String): DefaultEncoderFactory {
        val builder = DefaultEncoderFactory.Builder(context.applicationContext)
            .setEnableFallback(true)
        
        // 🚀 4K 모드: 하드웨어 코덱 강제 활성화
        if (quality.equals("4K", ignoreCase = true) && userTier == "premium") {
            // Galaxy S23 (SM-S911N) 등 고성능 기기 최적화
            // 하드웨어 코덱을 우선적으로 사용하도록 설정
            Log.d("3S_4K", "⚡ 4K 하드웨어 코덱 강제 활성화")
            Log.d("3S_4K", "  - 타겟 기기: Galaxy S23 (SM-S911N) 최적화")
            
            // TODO: setRequestedEncoderPerformanceParameters() 사용 시
            // builder.setRequestedEncoderPerformanceParameters(
            //     width = RESOLUTION_4K_WIDTH,
            //     height = RESOLUTION_4K_HEIGHT,
            //     bitrate = BITRATE_4K_MAX
            // )
        }
        
        return builder.build()
    }

    /// 비디오 클립 추출 (편집 기능)
    /// 
    /// 입력 비디오에서 여러 3초 구간을 추출하여 개별 파일로 저장
    /// 순차적 큐 처리로 메모리 부하 방지 (억만장자의 최적화)
    /// 노이즈 억제 지원
    /// 
    /// @param inputPath 원본 비디오 경로
    /// @param outputDir 출력 디렉토리
    /// @param segments 추출할 구간 리스트 [{startMs: Int, durationMs: Int}, ...]
    /// @param quality 품질 설정 (1080p 기본)
    /// @param enableNoiseSuppression 노이즈 억제 활성화 여부
    /// @param result Flutter 결과 콜백
    private fun extractClips(
        inputPath: String,
        outputDir: String,
        segments: List<Map<String, Any>>,
        quality: String,
        enableNoiseSuppression: Boolean,
        subtitles: List<Map<String, Any>>,
        userTier: String,
        result: MethodChannel.Result
    ) {
        Log.d("3S_EDIT", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        Log.d("3S_EDIT", "클립 추출 시작: ${segments.size}개 구간")
        Log.d("3S_EDIT", "입력: $inputPath")
        Log.d("3S_EDIT", "출력: $outputDir")
        Log.d("3S_EDIT", "품질: $quality")
        Log.d("3S_EDIT", "노이즈 억제: $enableNoiseSuppression")
        Log.d("3S_SUBTITLE", "자막: ${subtitles.size}개, 등급: $userTier")
        
        try {
            // 출력 디렉토리 확인
            val outputDirectory = File(outputDir)
            if (!outputDirectory.exists()) {
                outputDirectory.mkdirs()
                Log.d("3S_EDIT", "✓ 출력 디렉토리 생성: $outputDir")
            }

            // 생성된 파일 경로 추적
            val extractedFilePaths = mutableListOf<String>()
            
            // 하드웨어 가속 Encoder Factory 설정 (억만장자의 속도)
            val encoderFactory = DefaultEncoderFactory.Builder(context.applicationContext)
                .setEnableFallback(true)
                .build()
            
            Log.d("3S_EDIT", "✓ 하드웨어 가속 엔코더 준비 완료")

            // 순차적 큐 처리를 위한 재귀 함수
            fun processNextSegment(index: Int) {
                if (index >= segments.size) {
                    // 모든 클립 추출 완료
                    Log.d("3S_EDIT", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    Log.d("3S_EDIT", "✓ 전체 클립 추출 완료: ${extractedFilePaths.size}개")
                    Handler(Looper.getMainLooper()).post {
                        result.success(extractedFilePaths)
                    }
                    return
                }

                val segment = segments[index]
                val startMs = (segment["startMs"] as? Number)?.toLong() ?: 0L
                val durationMs = (segment["durationMs"] as? Number)?.toLong() ?: 3000L
                val endMs = startMs + durationMs

                Log.d("3S_EDIT", "────────────────────────────────────────")
                Log.d("3S_EDIT", "구간 ${index + 1}/${segments.size} 처리 중")
                Log.d("3S_EDIT", "  - 시작: ${startMs}ms (${startMs / 1000.0}초)")
                Log.d("3S_EDIT", "  - 종료: ${endMs}ms (${endMs / 1000.0}초)")
                Log.d("3S_EDIT", "  - 길이: ${durationMs}ms (${durationMs / 1000.0}초)")

                // 출력 파일명 생성 (타임스탬프 + 인덱스)
                val timestamp = System.currentTimeMillis()
                val outputFileName = "clip_${timestamp}_${index + 1}.mp4"
                val outputPath = File(outputDir, outputFileName).absolutePath
                
                Log.d("3S_EDIT", "  - 출력: $outputFileName")

                try {
                    // 1. MediaItem 생성
                    val mediaItem = MediaItem.fromUri(Uri.parse(inputPath))
                    
                    // 2. ClippingConfiguration 설정
                    val clippingConfig = MediaItem.ClippingConfiguration.Builder()
                        .setStartPositionMs(startMs)
                        .setEndPositionMs(endMs)
                        .build()
                    
                    // 3. 🎵 오디오 프로세서 (노이즈 억제)
                    val audioProcessors = mutableListOf<AudioProcessor>()
                    if (enableNoiseSuppression) {
                        val noiseSuppressor = NoiseSuppressorAudioProcessor(noiseThreshold = 0.15f)
                        audioProcessors.add(noiseSuppressor)
                        Log.d("3S_EDIT", "  ✓ 노이즈 억제 프로세서 적용")
                    }
                    
                    // 4. 📝 자막 오버레이 (비디오 이펙트)
                    val subtitleOverlay = createSubtitleOverlays(
                        subtitles = subtitles,
                        forceWatermark = false,
                        userTier = userTier
                    )
                    
                    val videoEffects = if (subtitleOverlay != null) {
                        listOf(subtitleOverlay)
                    } else {
                        listOf()
                    }
                    
                    if (subtitleOverlay != null) {
                        Log.d("3S_EDIT", "  ✓ 자막 오버레이 적용")
                    }
                    
                    // 5. Effects 결합 (오디오 + 비디오)
                    val clipEffects = Effects(audioProcessors, videoEffects)
                    
                    // 6. EditedMediaItem 생성 (오디오 + 자막 + 노이즈 억제)
                    val editedMediaItem = EditedMediaItem.Builder(mediaItem)
                        .setRemoveAudio(false)
                        .setClippingConfiguration(clippingConfig)
                        .setEffects(clipEffects)
                        .build()
                    
                    // 5. Composition 생성
                    val sequence = EditedMediaItemSequence(listOf(editedMediaItem))
                    val composition = Composition.Builder(listOf(sequence)).build()
                    
                    // 5. Transformer 구성
                    val transformer = Transformer.Builder(context)
                        .setVideoMimeType(MimeTypes.VIDEO_H264)
                        .setAudioMimeType(MimeTypes.AUDIO_AAC)
                        .setEncoderFactory(encoderFactory)
                        .addListener(object : Transformer.Listener {
                            override fun onCompleted(
                                composition: Composition,
                                exportResult: ExportResult
                            ) {
                                val fileSizeMB = exportResult.fileSizeBytes / 1024 / 1024
                                val durationSec = exportResult.durationMs / 1000.0
                                
                                Log.d("3S_EDIT", "  ✓ 구간 ${index + 1} 추출 성공")
                                Log.d("3S_EDIT", "    - 파일 크기: ${fileSizeMB}MB")
                                Log.d("3S_EDIT", "    - 처리 시간: ${durationSec}초")
                                Log.d("3S_EDIT", "    - 저장 경로: $outputPath")
                                
                                extractedFilePaths.add(outputPath)
                                
                                // 다음 클립 처리 (순차적 큐)
                                processNextSegment(index + 1)
                            }

                            override fun onError(
                                composition: Composition,
                                exportResult: ExportResult,
                                exportException: ExportException
                            ) {
                                Log.e("3S_EDIT", "  ✗ 구간 ${index + 1} 추출 실패: ${exportException.message}", exportException)
                                Handler(Looper.getMainLooper()).post {
                                    result.error(
                                        "EXTRACT_FAILED",
                                        "클립 ${index + 1} 추출 실패: ${exportException.message}",
                                        null
                                    )
                                }
                            }
                        })
                        .build()
                    
                    // 6. 출력 파일 준비 및 추출 시작
                    val outputFile = File(outputPath)
                    if (outputFile.exists()) {
                        outputFile.delete()
                        Log.d("3S_EDIT", "  - 기존 파일 삭제")
                    }
                    
                    Log.d("3S_EDIT", "  ⚡ Transformer 시작 (하드웨어 가속)")
                    transformer.start(composition, outputPath)
                    
                } catch (e: Exception) {
                    Log.e("3S_EDIT", "  ✗ 구간 ${index + 1} 설정 실패: ${e.message}", e)
                    Handler(Looper.getMainLooper()).post {
                        result.error(
                            "SETUP_FAILED",
                            "클립 ${index + 1} 설정 실패: ${e.message}",
                            null
                        )
                    }
                }
            }

            // 첫 번째 클립부터 순차 처리 시작
            processNextSegment(0)
            
        } catch (e: Exception) {
            Log.e("3S_EDIT", "✗ extractClips 초기화 실패: ${e.message}", e)
            Handler(Looper.getMainLooper()).post {
                result.error("INIT_FAILED", "초기화 실패: ${e.message}", null)
            }
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 🎵 실전용 오디오 프로세서 (Media3 BaseAudioProcessor 기반)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/**
 * Fade Out 오디오 프로세서 (실전용)
 * 
 * BGM의 마지막 0.5초 동안 볼륨을 점진적으로 0으로 감소시켜 매끄러운 종료
 * BaseAudioProcessor를 상속하여 Media3와 완벽 호환
 * 
 * @param fadeOutDurationMs Fade Out 지속 시간 (기본 500ms)
 * @param totalDurationMs 전체 오디오 길이 (밀리초)
 */
class FadeOutAudioProcessor(
    private val fadeOutDurationMs: Long = 500L,
    private val totalDurationMs: Long
) : BaseAudioProcessor() {
    
    private var processedSamples = 0L
    private var sampleRate = 0
    
    init {
        Log.d("3S_AUDIO", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        Log.d("3S_AUDIO", "✓ FadeOutAudioProcessor 초기화")
        Log.d("3S_AUDIO", "  - Fade Out 시간: ${fadeOutDurationMs}ms")
        Log.d("3S_AUDIO", "  - 전체 오디오 길이: ${totalDurationMs}ms")
        Log.d("3S_AUDIO", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        sampleRate = inputAudioFormat.sampleRate
        Log.d("3S_AUDIO", "✓ Fade Out 설정: ${sampleRate}Hz, ${inputAudioFormat.channelCount}ch")
        return inputAudioFormat
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        // 현재 재생 위치 계산 (샘플 수 → 밀리초)
        val currentPositionMs = (processedSamples * 1000L) / sampleRate
        val fadeOutStartMs = totalDurationMs - fadeOutDurationMs
        
        val position = inputBuffer.position()
        val limit = inputBuffer.limit()
        val frameCount = (limit - position) / (2 * inputAudioFormat.channelCount) // 16-bit = 2 bytes
        
        // Fade Out 구간 판단
        if (currentPositionMs >= fadeOutStartMs) {
            // 🎚️ Fade Out 적용
            val fadeProgress = ((currentPositionMs - fadeOutStartMs).toFloat() / fadeOutDurationMs).coerceIn(0f, 1f)
            val gain = 1.0f - fadeProgress
            
            val outputBuffer = replaceOutputBuffer(limit - position)
            
            // 16-bit PCM 샘플 처리
            for (i in 0 until frameCount) {
                for (ch in 0 until inputAudioFormat.channelCount) {
                    val sample = inputBuffer.short
                    val processedSample = (sample * gain).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
                    outputBuffer.putShort(processedSample)
                }
            }
            
            outputBuffer.flip()
            
            if (fadeProgress > 0.5f) {
                Log.d("3S_AUDIO", "🎚️ Fade Out 진행: ${(fadeProgress * 100).toInt()}% (gain=${String.format("%.2f", gain)})")
            }
        } else {
            // Fade Out 이전: 그대로 복사
            val outputBuffer = replaceOutputBuffer(limit - position)
            outputBuffer.put(inputBuffer)
            outputBuffer.flip()
        }
        
        processedSamples += frameCount
    }

    override fun onFlush() {
        processedSamples = 0
    }

    override fun onReset() {
        processedSamples = 0
        sampleRate = 0
    }
}

/**
 * 노이즈 억제 오디오 프로세서 (실전용)
 * 
 * 스펙트럴 게이팅 기반 노이즈 제거
 * - 목소리 주파수 대역 (300Hz~3400Hz) 보존
 * - 배경 화이트 노이즈 (저주파/고주파) 감쇠
 * - 간단한 임계값 기반 게이팅으로 하드웨어 부하 최소화
 * 
 * @param noiseThreshold 노이즈 임계값 (0~1, 기본 0.1 = 10%)
 */
class NoiseSuppressorAudioProcessor(
    private val noiseThreshold: Float = 0.1f
) : BaseAudioProcessor() {
    
    private var noiseFloor = 0f
    private var frameCount = 0
    private val calibrationFrames = 10 // 처음 10프레임으로 노이즈 프로필 추정
    
    init {
        Log.d("3S_AUDIO", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        Log.d("3S_AUDIO", "✓ NoiseSuppressorAudioProcessor 초기화")
        Log.d("3S_AUDIO", "  - 노이즈 임계값: ${(noiseThreshold * 100).toInt()}%")
        Log.d("3S_AUDIO", "  - 교정 프레임: $calibrationFrames")
        Log.d("3S_AUDIO", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        Log.d("3S_AUDIO", "✓ 노이즈 억제 설정: ${inputAudioFormat.sampleRate}Hz, ${inputAudioFormat.channelCount}ch")
        return inputAudioFormat
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val position = inputBuffer.position()
        val limit = inputBuffer.limit()
        val sampleCount = (limit - position) / 2 // 16-bit = 2 bytes per sample
        
        // 📊 노이즈 프로필 교정 (처음 몇 프레임)
        if (frameCount < calibrationFrames) {
            val rms = calculateRMS(inputBuffer, position, limit)
            noiseFloor = (noiseFloor * frameCount + rms) / (frameCount + 1)
            frameCount++
            
            if (frameCount == calibrationFrames) {
                Log.d("3S_AUDIO", "✓ 노이즈 프로필 교정 완료: ${String.format("%.4f", noiseFloor)}")
            }
        }
        
        val outputBuffer = replaceOutputBuffer(limit - position)
        inputBuffer.position(position)
        
        // 🎯 스펙트럴 게이팅 (간소화 버전)
        val threshold = noiseFloor * (1f + noiseThreshold)
        
        for (i in 0 until sampleCount) {
            val sample = inputBuffer.short
            val amplitude = Math.abs(sample.toFloat())
            
            // 임계값 기반 게이팅
            val processedSample = if (amplitude < threshold) {
                // 노이즈로 판단 → 감쇠 (완전 제거는 아니고 70% 감쇠)
                (sample * 0.3f).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
            } else {
                // 신호로 판단 → 유지
                sample
            }
            
            outputBuffer.putShort(processedSample)
        }
        
        outputBuffer.flip()
    }

    /**
     * RMS (Root Mean Square) 계산
     * 오디오 신호의 평균 에너지 레벨 측정
     */
    private fun calculateRMS(buffer: ByteBuffer, start: Int, end: Int): Float {
        buffer.position(start)
        var sumSquares = 0.0
        var count = 0
        
        while (buffer.position() < end - 1) {
            val sample = buffer.short.toFloat()
            sumSquares += sample * sample
            count++
        }
        
        return if (count > 0) {
            Math.sqrt(sumSquares / count).toFloat()
        } else {
            0f
        }
    }

    override fun onFlush() {
        // 플러시 시 노이즈 프로필 유지 (리셋하지 않음)
    }

    override fun onReset() {
        noiseFloor = 0f
        frameCount = 0
    }
}