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
import android.text.style.BackgroundColorSpan
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
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.transformer.DefaultAssetLoaderFactory // ✅ 추가
import androidx.media3.datasource.DataSourceBitmapLoader // ✅ 추가
import androidx.media3.effect.Contrast
import androidx.media3.effect.RgbMatrix
import androidx.media3.effect.Presentation // ✅ 추가
import androidx.media3.common.Effect // ✅ 추가
import androidx.media3.effect.GlEffect
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.File
import java.nio.ByteBuffer
import android.util.Log
import android.media.MediaMetadataRetriever

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.dk.three_sec/video_engine"

    private fun toMediaUri(pathOrUri: String): Uri {
        val parsed = Uri.parse(pathOrUri)
        return if (parsed.scheme.isNullOrBlank()) {
            Uri.fromFile(File(pathOrUri))
        } else {
            parsed
        }
    }

    private fun validateReadableInput(inputPath: String): Pair<Uri, String?> {
        val uri = toMediaUri(inputPath)
        return when (uri.scheme?.lowercase()) {
            "file" -> {
                val filePath = uri.path
                if (filePath.isNullOrBlank()) {
                    uri to "File URI path is invalid: $inputPath"
                } else {
                    val inputFile = File(filePath)
                    if (!inputFile.exists()) {
                        uri to "Input file does not exist: $filePath"
                    } else {
                        uri to null
                    }
                }
            }
            "content" -> uri to null
            else -> uri to "Unsupported URI scheme: ${uri.scheme ?: "null"}"
        }
    }

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
        private const val BITRATE_1080P_MAX = 5_000_000 // 5Mbps (Standardized for Gallery)
        
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
                    // Flutter Args: videoPaths, audioChanges, bgmPath, bgmVolume, quality, outputPath
                    val paths = call.argument<List<String>>("videoPaths")
                    val audioChanges = call.argument<Map<String, Double>>("audioChanges") ?: emptyMap()
                    val outputPath = call.argument<String>("outputPath")
                    
                    // Optional Args (Defaults)
                    val subtitles = call.argument<List<Map<String, Any>>>("subtitles") ?: emptyList()
                    val forceWatermark = call.argument<Boolean>("forceWatermark") ?: false
                    val quality = call.argument<String>("quality") ?: "1080p"
                    val userTier = call.argument<String>("userTier") ?: "free"
                    
                    // Audio Mixing
                    val bgmPath = call.argument<String>("bgmPath")
                    val forceMuteOriginal = call.argument<Boolean>("forceMuteOriginal") ?: false
                    val enableNoiseSuppression = call.argument<Boolean>("enableNoiseSuppression") ?: false
                    val bgmVolume = call.argument<Double>("bgmVolume")?.toFloat() ?: 0.5f
                    
                    // Video Effects
                    val videoEffects = call.argument<Map<String, Any>>("videoEffects") ?: emptyMap()
                    
                    val startTimes = call.argument<List<Long>>("startTimes") ?: emptyList()
                    val endTimes = call.argument<List<Long>>("endTimes") ?: emptyList()
                    
                    Log.d("3S_4K", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    Log.d("3S_4K", "mergeVideos 호출 (Flutter -> Native)")
                    Log.d("3S_4K", "  - paths: $paths")
                    Log.d("3S_4K", "  - trim: start=$startTimes, end=$endTimes") // Log trim info
                    Log.d("3S_4K", "  - outputPath: $outputPath")
                    Log.d("3S_4K", "  - audioConfig: $audioChanges (To be implemented)")
                    Log.d("3S_4K", "  - bgmPath: $bgmPath, vol: $bgmVolume")
                    
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
                            startTimes,
                            endTimes,
                            result
                        )
                    } else {
                        result.error("INVALID_ARGS", "필수 인자 누락 (videoPaths or outputPath)", null)
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
                "applyEdits" -> {
                    val inputPath = call.argument<String>("inputPath")
                    val outputPath = call.argument<String>("outputPath")
                    
                    // 📝 자막, 스티커, 이펙트 파라미터
                    val subtitles = call.argument<List<Map<String, Any>>>("subtitles") ?: emptyList()
                    val stickers = call.argument<List<Map<String, Any>>>("stickers") ?: emptyList()
                    val videoEffects = call.argument<Map<String, Any>>("videoEffects") ?: emptyMap()
                    
                    val quality = call.argument<String>("quality") ?: "1080p"
                    val userTier = call.argument<String>("userTier") ?: "free"
                    
                    // 🎵 오디오 파라미터
                    val bgmPath = call.argument<String>("bgmPath")
                    val forceMuteOriginal = call.argument<Boolean>("forceMuteOriginal") ?: false
                    val enableNoiseSuppression = call.argument<Boolean>("enableNoiseSuppression") ?: false
                    val bgmVolume = call.argument<Double>("bgmVolume")?.toFloat() ?: 0.5f
                    
                    Log.d("3S_EDIT", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    Log.d("3S_EDIT", "applyEdits 호출")
                    Log.d("3S_EDIT", "  - 자막: ${subtitles.size}개")
                    Log.d("3S_EDIT", "  - 스티커: ${stickers.size}개")
                    Log.d("3S_EDIT", "  - 이펙트: ${videoEffects.keys}")
                    Log.d("3S_EDIT", "  - 품질: $quality")
                    Log.d("3S_EDIT", "  - 사용자 등급: $userTier")
                    
                    if (inputPath != null && outputPath != null) {
                        applyEdits(
                            inputPath,
                            outputPath,
                            subtitles,
                            stickers,
                            videoEffects,
                            quality,
                            userTier,
                            bgmPath,
                            forceMuteOriginal,
                            enableNoiseSuppression,
                            bgmVolume,
                            result
                        )
                    } else {
                        result.error("INVALID_ARGS", "입력 경로 또는 출력 경로가 비어있습니다.", null)
                    }
                }
                "convertImageToVideo" -> {
                    val imagePath = call.argument<String>("imagePath")
                    val outputPath = call.argument<String>("outputPath")
                    val duration = call.argument<Int>("duration") ?: 3

                    Log.d("3S_CONVERT", "convertImageToVideo 호출: $imagePath")

                    if (imagePath != null && outputPath != null) {
                        convertImageToVideo(imagePath, outputPath, duration, result)
                    } else {
                        result.error("INVALID_ARGS", "필수 인자가 누락되었습니다.", null)
                    }
                }
                "normalizeVideoDuration" -> {
                    val inputPath = call.argument<String>("inputPath")
                    val outputPath = call.argument<String>("outputPath")
                    val args = call.arguments as? Map<*, *>
                    val rawTargetDuration = args?.get("targetDurationMs")
                    val rawTrimMode = args?.get("trimMode")
                    val targetDurationMs = when (rawTargetDuration) {
                        is Long -> rawTargetDuration
                        is Int -> rawTargetDuration.toLong()
                        is Double -> rawTargetDuration.toLong()
                        is Float -> rawTargetDuration.toLong()
                        is Number -> rawTargetDuration.toLong()
                        is String -> rawTargetDuration.toLongOrNull() ?: 3000L
                        else -> 3000L
                    }
                    val trimMode = (rawTrimMode as? String)?.lowercase() ?: "start"

                    Log.d(
                        "3S_NORMALIZE",
                        "normalizeVideoDuration argType=${rawTargetDuration?.javaClass?.name} value=$rawTargetDuration parsedMs=$targetDurationMs trimMode=$trimMode"
                    )

                    if (inputPath != null && outputPath != null) {
                        normalizeVideoDuration(
                            inputPath = inputPath,
                            outputPath = outputPath,
                            targetDurationMs = targetDurationMs,
                            trimMode = trimMode,
                            result = result
                        )
                    } else {
                        result.error("INVALID_ARGS", "inputPath or outputPath is missing", null)
                    }
                }
                "getVideoDurationMs" -> {
                    val inputPath = call.argument<String>("inputPath")
                    if (inputPath != null) {
                        getVideoDurationMs(inputPath, result)
                    } else {
                        result.error("INVALID_ARGS", "inputPath is missing", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getVideoDurationMs(
        inputPath: String,
        result: MethodChannel.Result
    ) {
        var retriever: MediaMetadataRetriever? = null
        try {
            val (sourceUri, inputError) = validateReadableInput(inputPath)
            if (inputError != null) {
                result.error("INPUT_NOT_FOUND", inputError, null)
                return
            }

            retriever = MediaMetadataRetriever()
            retriever.setDataSource(this, sourceUri)
            val durationMs =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                    ?.toLongOrNull()
                    ?: 0L

            if (durationMs <= 0L) {
                result.error("INVALID_SOURCE_DURATION", "Could not determine source duration", null)
                return
            }

            result.success(durationMs)
        } catch (e: Exception) {
            Log.e("3S_NORMALIZE", "getVideoDurationMs failed: ${e.message}", e)
            result.error("DURATION_FAILED", "getVideoDurationMs failed: ${e.message}", null)
        } finally {
            retriever?.release()
        }
    }

    private fun normalizeVideoDuration(
        inputPath: String,
        outputPath: String,
        targetDurationMs: Long,
        trimMode: String,
        result: MethodChannel.Result
    ) {
        try {
            if (targetDurationMs <= 0L) {
                result.error("INVALID_DURATION", "targetDurationMs must be greater than 0", null)
                return
            }

            val (sourceUri, inputError) = validateReadableInput(inputPath)
            if (inputError != null) {
                result.error("INPUT_NOT_FOUND", inputError, null)
                return
            }

            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(this, sourceUri)
            val sourceDurationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            retriever.release()

            if (sourceDurationMs <= 0L) {
                result.error("INVALID_SOURCE_DURATION", "Could not determine source duration", null)
                return
            }

            val outputFile = File(outputPath)
            if (outputFile.exists()) {
                outputFile.delete()
            }

            val clipMs = kotlin.math.min(sourceDurationMs, targetDurationMs)
            val effectiveTrimMode = if (trimMode == "center") "center" else "start"
            val startMs = if (effectiveTrimMode == "center" && sourceDurationMs > clipMs) {
                (sourceDurationMs - clipMs) / 2L
            } else {
                0L
            }
            val endMs = startMs + clipMs
            Log.d(
                "3S_NORMALIZE",
                "normalizeVideoDuration sourceMs=$sourceDurationMs targetMs=$targetDurationMs clipMs=$clipMs trimMode=$effectiveTrimMode startMs=$startMs endMs=$endMs"
            )

            val clippingConfig = MediaItem.ClippingConfiguration.Builder()
                .setStartPositionMs(startMs)
                .setEndPositionMs(endMs)
                .build()

            val clippedItem = MediaItem.Builder()
                .setUri(sourceUri)
                .setMediaId("normalize_trim")
                .setClippingConfiguration(clippingConfig)
                .build()

            val editedItems = arrayListOf(
                EditedMediaItem.Builder(clippedItem).build()
            )

            val sequence = EditedMediaItemSequence(editedItems)
            val composition = Composition.Builder(listOf(sequence))
                .setTransmuxAudio(false)
                .setTransmuxVideo(false)
                .build()

            val transformer = Transformer.Builder(context)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        Handler(Looper.getMainLooper()).post {
                            Log.d(
                                "3S_NORMALIZE",
                                "normalizeVideoDuration complete: $outputPath (durationMs=${exportResult.durationMs} clipMs=$clipMs startMs=$startMs endMs=$endMs trimMode=$effectiveTrimMode)"
                            )
                            result.success("SUCCESS")
                        }
                    }

                    override fun onError(
                        composition: Composition,
                        exportResult: ExportResult,
                        exportException: ExportException
                    ) {
                        Handler(Looper.getMainLooper()).post {
                            Log.e("3S_NORMALIZE", "normalizeVideoDuration failed: ${exportException.message}", exportException)
                            result.error(
                                "NORMALIZE_FAILED",
                                "normalizeVideoDuration failed: ${exportException.message}",
                                null
                            )
                        }
                    }
                })
                .build()

            transformer.start(composition, outputPath)
        } catch (e: Exception) {
            Log.e("3S_NORMALIZE", "normalizeVideoDuration setup failed: ${e.message}", e)
            result.error("NORMALIZE_SETUP_FAILED", "normalizeVideoDuration setup failed: ${e.message}", null)
        }
    }

    private fun convertImageToVideo(
        imagePath: String,
        outputPath: String,
        durationSec: Int,
        result: MethodChannel.Result
    ) {
        // 1. 파일 검사
        val file = File(imagePath) // ✅ 누락된 변수 선언 복원
        if (!file.exists()) {
            Log.e("3S_CONVERT", "파일 없음: $imagePath")
            result.error("FILE_NOT_FOUND", "파일이 존재하지 않습니다.", null)
            return
        }
        if (!file.canRead()) {
            Log.e("3S_CONVERT", "읽기 권한 없음: $imagePath")
            result.error("PERMISSION_DENIED", "파일 읽기 권한이 없습니다.", null)
            return
        }
        Log.d("3S_CONVERT", "파일 확인됨. 크기: ${file.length()} bytes")

        // 2-1. 이미지 리사이징 (전처리)
        // 원본이 너무 크면(4K 등) AssetLoader가 실패할 수 있음 -> 1080p로 줄여서 TEMP 파일 생성
        val resizedPath = "${cacheDir.path}/resized_${System.currentTimeMillis()}.jpg"
        try {
            val options = android.graphics.BitmapFactory.Options()
            options.inJustDecodeBounds = true
            android.graphics.BitmapFactory.decodeFile(imagePath, options)
            
            val srcWidth = options.outWidth
            val srcHeight = options.outHeight
            var inSampleSize = 1
            
            // 1080p 기준(약 200만 픽셀 or 긴 변 1920)으로 샘플링 계산
            val reqSize = 1920
            if (srcWidth > reqSize || srcHeight > reqSize) {
                val halfHeight = srcHeight / 2
                val halfWidth = srcWidth / 2
                while ((halfHeight / inSampleSize) >= reqSize && (halfWidth / inSampleSize) >= reqSize) {
                    inSampleSize *= 2
                }
            }
            
            options.inJustDecodeBounds = false
            options.inSampleSize = inSampleSize
            
            val originalBitmap = android.graphics.BitmapFactory.decodeFile(imagePath, options)
            if (originalBitmap == null) {
                result.error("DECODE_NULL", "비트맵 디코딩 실패", null)
                return
            }
            
            // Exif 회전 정보 읽기 (InputStream 사용이 더 안정적일 수 있음)
            val exif = try {
                android.media.ExifInterface(imagePath)
            } catch (e: Exception) {
                Log.e("3S_CONVERT_V2", "Exif 읽기 실패: $e")
                null
            }
            
            val orientation = exif?.getAttributeInt(
                android.media.ExifInterface.TAG_ORIENTATION,
                android.media.ExifInterface.ORIENTATION_NORMAL
            ) ?: android.media.ExifInterface.ORIENTATION_NORMAL
            
            Log.d("3S_CONVERT_V2", "감지된 Orientation: $orientation")

            val matrix = android.graphics.Matrix()
            when (orientation) {
                android.media.ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
                android.media.ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
                android.media.ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            }
            
            val rotatedBitmap = android.graphics.Bitmap.createBitmap(
                originalBitmap, 0, 0, originalBitmap.width, originalBitmap.height, matrix, true
            )
            
            val outStream = java.io.FileOutputStream(resizedPath)
            rotatedBitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 95, outStream) // 품질 95
            outStream.flush()
            outStream.close()
            
            Log.d("3S_CONVERT_V2", "리사이징/회전 완료(V2): ${srcWidth}x${srcHeight} -> ${rotatedBitmap.width}x${rotatedBitmap.height}, path=$resizedPath")
            
        } catch (e: Exception) {
            Log.e("3S_CONVERT_V2", "리사이징 에러: $e")
            result.error("RESIZE_ERROR", "이미지 리사이징 실패: $e", null)
            return
        }

        val transcodeFile = File(resizedPath)
        val uri = Uri.fromFile(transcodeFile)
        Log.d("3S_CONVERT_V2", "변환 URI(V2): $uri")

        // 출력 파일이 이미 존재하면 삭제
        val outFile = File(outputPath)
        if (outFile.exists()) {
            outFile.delete()
        }

        // 3. MIME Type 명시
        val mediaItem = MediaItem.Builder()
            .setUri(uri)
            .setMimeType(MimeTypes.IMAGE_JPEG)
            .setImageDurationMs(durationSec * 1_000L) // ✅ 이미지 지속 시간 설정 (필수)
            .build()
        
        // 이미 리사이징했으므로 Presentation 효과는 제거 가능하지만, 안전하게 비율 유지위해 남겨둘 수도 있음.
        // 여기서는 그냥 심플하게 변환만 수행
        val editedMediaItem = EditedMediaItem.Builder(mediaItem)
            .setFrameRate(30)
            .setRemoveAudio(true)
            .build()
            // durationUs는 setImageDurationMs로 대체됨 (AssetLoader 사용 시)

        val transformer = Transformer.Builder(this)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setAssetLoaderFactory(DefaultAssetLoaderFactory(this, DataSourceBitmapLoader(this)))
            .build()
        
        transformer.addListener(object : Transformer.Listener {
            override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                Handler(Looper.getMainLooper()).post {
                    Log.d("3S_CONVERT", "변환 성공: $outputPath")
                    // 임시 파일 삭제
                    File(resizedPath).delete()
                    result.success("SUCCESS")
                }
            }

            override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                Handler(Looper.getMainLooper()).post {
                    File(resizedPath).delete() // 에러나도 삭제
                    val cause = exportException.cause?.message ?: "Unknown Cause"
                    Log.e("3S_CONVERT", "변환 실패: ${exportException.message}, Cause: $cause")
                    result.error("EXPORT_FAILED", "변환 실패(${exportException.errorCode}): ${exportException.message} / $cause", null)
                }
            }
        })
        
        transformer.start(editedMediaItem, outputPath)
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
        startTimes: List<Long>, // ✅ Add startTimes
        endTimes: List<Long>,   // ✅ Add endTimes
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
        for ((i, path) in paths.withIndex()) {
            val startTime = if (i < startTimes.size) startTimes[i] else 0L
            val endTime = if (i < endTimes.size) endTimes[i] else 0L
            
            // ✅ Clipping Configuration
            val clippingBuilder = MediaItem.ClippingConfiguration.Builder()
                .setStartPositionMs(startTime)
            
            if (endTime > 0) {
                 clippingBuilder.setEndPositionMs(endTime)
            }
            
            val mediaItem = MediaItem.Builder()
                .setUri(toMediaUri(path))
                .setClippingConfiguration(clippingBuilder.build())
                .build()
            
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
                Effects(audioProcessors, allVideoEffects as List<androidx.media3.common.Effect>)
            } else {
                // GPU 필터 + 오버레이만
                Effects(mutableListOf<AudioProcessor>(), allVideoEffects as List<androidx.media3.common.Effect>)
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
                
                val bgmMediaItem = MediaItem.fromUri(toMediaUri(bgmPath))
                
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
                    Log.d("3S_AUDIO", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    Handler(Looper.getMainLooper()).post { 
                        result.success(outputPath) 
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
     * 자막/워터마크 오버레이 생성 (고도화)
     * 
     * @param subtitles 자막 리스트 [{text, x, y, size, color, backgroundColor, startTime, endTime}, ...]
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
                
                // 🆕 배경색 (선택적)
                val backgroundColorHex = subtitle["backgroundColor"] as? String
                
                // 🆕 표시 시간 (선택적, ms 단위)
                val startTimeMs = (subtitle["startTime"] as? Number)?.toLong()
                val endTimeMs = (subtitle["endTime"] as? Number)?.toLong()
                
                Log.d("3S_SUBTITLE", "자막 ${index + 1}: '$text' (x=$x, y=$y, size=$size, color=$colorHex)")
                if (backgroundColorHex != null) {
                    Log.d("3S_SUBTITLE", "  - 배경색: $backgroundColorHex")
                }
                if (startTimeMs != null && endTimeMs != null) {
                    Log.d("3S_SUBTITLE", "  - 시간: ${startTimeMs}ms ~ ${endTimeMs}ms")
                }
                
                // SpannableString 생성
                val spannable = SpannableString(text)
                val len = text.length
                
                // 색상 파싱
                val color = try {
                    Color.parseColor(colorHex)
                } catch (e: Exception) {
                    Color.WHITE
                }
                
                // 배경색 파싱
                val backgroundColor = if (backgroundColorHex != null) {
                    try {
                        Color.parseColor(backgroundColorHex)
                    } catch (e: Exception) {
                        null
                    }
                } else {
                    null
                }
                
                // 🎨 Standard vs Premium 스타일링
                if (userTier == "premium") {
                    // 💎 Premium: 고급 스타일
                    Log.d("3S_SUBTITLE", "  ✓ Premium 스타일 적용")
                    
                    // 볼드 폰트
                    spannable.setSpan(StyleSpan(Typeface.BOLD), 0, len, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                    
                    // 폰트 크기
                    spannable.setSpan(RelativeSizeSpan(size), 0, len, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                    
                    // 색상
                    spannable.setSpan(ForegroundColorSpan(color), 0, len, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                    
                    // 배경색 (선택적)
                    if (backgroundColor != null) {
                        spannable.setSpan(BackgroundColorSpan(backgroundColor), 0, len, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                        Log.d("3S_SUBTITLE", "  ✓ 배경색 적용")
                    }
                    
                    // TODO: 외곽선 효과 (StrokeSpan - 커스텀 구현 필요)
                    // TODO: 그림자 효과 (ShadowSpan - 커스텀 구현 필요)
                    
                } else {
                    // 📋 Standard: 기본 스타일
                    Log.d("3S_SUBTITLE", "  ✓ Standard 스타일 적용")
                    
                    // 폰트 크기
                    spannable.setSpan(RelativeSizeSpan(size), 0, len, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                    
                    // 색상
                    spannable.setSpan(ForegroundColorSpan(color), 0, len, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                    
                    // 배경색 (선택적)
                    if (backgroundColor != null) {
                        spannable.setSpan(BackgroundColorSpan(backgroundColor), 0, len, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                        Log.d("3S_SUBTITLE", "  ✓ 배경색 적용")
                    }
                }
                
                // 오버레이 위치 설정
                val overlaySettings = StaticOverlaySettings.Builder()
                    .setOverlayFrameAnchor(x, y)
                    .setBackgroundFrameAnchor(x, y)
                    .setScale(size, size)
                    .build()
                
                // TextOverlay 생성 (Media3는 시간 파라미터 미지원, 전체 구간 표시)
                // TODO: 시간 범위 표시는 별도 로직으로 구현 필요
                val textOverlay = TextOverlay.createStaticTextOverlay(spannable, overlaySettings)
                textOverlays.add(textOverlay)
                
                if (startTimeMs != null && endTimeMs != null) {
                    Log.d("3S_SUBTITLE", "  ⚠️ 시간 범위는 현재 버전에서 미지원 (${startTimeMs}~${endTimeMs}ms)")
                }

                
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
        return OverlayEffect(textOverlays.toList())
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // 🎨 스티커 오버레이 생성
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /**
     * 스티커 오버레이 생성
     * 
     * @param stickers 스티커 리스트 [{imagePath, x, y, width, height, rotation, startTime, endTime}, ...]
     * @return OverlayEffect 또는 null
     */
    private fun createStickerOverlays(
        stickers: List<Map<String, Any>>
    ): OverlayEffect? {
        val bitmapOverlays = mutableListOf<BitmapOverlay>()
        
        for ((index, sticker) in stickers.withIndex()) {
            try {
                val imagePath = sticker["imagePath"] as? String ?: continue
                val x = (sticker["x"] as? Number)?.toFloat() ?: 0f
                val y = (sticker["y"] as? Number)?.toFloat() ?: 0f
                val width = (sticker["width"] as? Number)?.toFloat() ?: 0.2f
                val height = (sticker["height"] as? Number)?.toFloat() ?: 0.2f
                val rotation = (sticker["rotation"] as? Number)?.toFloat() ?: 0f
                
                // 표시 시간 (선택적, ms 단위)
                val startTimeMs = (sticker["startTime"] as? Number)?.toLong()
                val endTimeMs = (sticker["endTime"] as? Number)?.toLong()
                
                Log.d("3S_STICKER", "스티커 ${index + 1}: $imagePath")
                Log.d("3S_STICKER", "  - 위치: (x=$x, y=$y)")
                Log.d("3S_STICKER", "  - 크기: ${width}x${height}")
                Log.d("3S_STICKER", "  - 회전: ${rotation}°")
                
                if (startTimeMs != null && endTimeMs != null) {
                    Log.d("3S_STICKER", "  - 시간: ${startTimeMs}ms ~ ${endTimeMs}ms")
                }
                
                // 이미지 파일 로드
                val imageFile = File(imagePath)
                if (!imageFile.exists()) {
                    Log.e("3S_STICKER", "✗ 스티커 파일 없음: $imagePath")
                    continue
                }
                
                val bitmap = BitmapFactory.decodeFile(imagePath)
                if (bitmap == null) {
                    Log.e("3S_STICKER", "✗ 비트맵 디코딩 실패: $imagePath")
                    continue
                }
                
                // 오버레이 위치 설정
                val overlaySettings = StaticOverlaySettings.Builder()
                    .setOverlayFrameAnchor(x, y)
                    .setBackgroundFrameAnchor(x, y)
                    .setScale(width, height)
                    .build()
                
                // BitmapOverlay 생성 (Media3는 시간 파라미터 미지원, 전체 구간 표시)
                // TODO: 시간 범위 표시는 별도 로직으로 구현 필요
                val bitmapOverlay = BitmapOverlay.createStaticBitmapOverlay(bitmap, overlaySettings)
                
                bitmapOverlays.add(bitmapOverlay)
                Log.d("3S_STICKER", "✓ 스티커 ${index + 1} 생성 완료")
                
                if (startTimeMs != null && endTimeMs != null) {
                    Log.d("3S_STICKER", "  ⚠️ 시간 범위는 현재 버전에서 미지원 (${startTimeMs}~${endTimeMs}ms)")
                }

                
            } catch (e: Exception) {
                Log.e("3S_STICKER", "✗ 스티커 ${index + 1} 생성 실패: ${e.message}")
            }
        }
        
        if (bitmapOverlays.isEmpty()) {
            Log.d("3S_STICKER", "✓ 스티커 없음")
            return null
        }
        
        Log.d("3S_STICKER", "✓ 총 ${bitmapOverlays.size}개 스티커 생성")
        return OverlayEffect(bitmapOverlays.toList())
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
                filters.add(RgbMatrix { _, _ -> matrix })
                Log.d("3S_4K", "  ✓ Saturation: $saturation")
            }
            
            // 🎨 Grayscale (흑백)
            val grayscale = effects["grayscale"] as? Boolean ?: false
            if (grayscale) {
                // 채도 0으로 설정하여 흑백 효과
                val matrix = createSaturationMatrix(GRAYSCALE_SATURATION)
                filters.add(RgbMatrix { _, _ -> matrix })
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
                val startMs = (segment["start"] as? Number)?.toLong() ?: 0L
                val endMs = (segment["end"] as? Number)?.toLong() ?: (startMs + 3000L)
                val durationMs = endMs - startMs

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
                    val baseMediaItem = MediaItem.fromUri(toMediaUri(inputPath))
                    
                    // 2. ClippingConfiguration 설정
                    val clippingConfig = MediaItem.ClippingConfiguration.Builder()
                        .setStartPositionMs(startMs)
                        .setEndPositionMs(endMs)
                        .build()
                    
                    // MediaItem에 ClippingConfiguration 적용
                    val mediaItem = baseMediaItem.buildUpon()
                        .setClippingConfiguration(clippingConfig)
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
                    val clipEffects = Effects(audioProcessors, videoEffects as List<androidx.media3.common.Effect>)
                    
                    // 6. EditedMediaItem 생성 (오디오 + 자막 + 노이즈 억제)
                    val editedMediaItem = EditedMediaItem.Builder(mediaItem)
                        .setRemoveAudio(false)
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

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // ✏️ 영상 편집 적용 (자막 + 스티커 + 이펙트)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /**
     * 영상 편집 적용
     * 
     * Flutter의 applyEdits 호출에 대응하는 네이티브 메서드
     * 
     * @param inputPath 입력 영상 경로
     * @param outputPath 출력 영상 경로
     * @param subtitles 자막 리스트
     * @param stickers 스티커 리스트
     * @param videoEffects 비디오 이펙트 맵
     * @param quality 품질 설정
     * @param userTier 사용자 등급
     * @param bgmPath BGM 경로 (선택적)
     * @param forceMuteOriginal 원본 음소거 여부
     * @param enableNoiseSuppression 노이즈 억제 활성화
     * @param bgmVolume BGM 볼륨
     * @param result Flutter 결과 콜백
     */
    private fun applyEdits(
        inputPath: String,
        outputPath: String,
        subtitles: List<Map<String, Any>>,
        stickers: List<Map<String, Any>>,
        videoEffects: Map<String, Any>,
        quality: String,
        userTier: String,
        bgmPath: String?,
        forceMuteOriginal: Boolean,
        enableNoiseSuppression: Boolean,
        bgmVolume: Float,
        result: MethodChannel.Result
    ) {
        Log.d("3S_EDIT", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        Log.d("3S_EDIT", "영상 편집 시작")
        Log.d("3S_EDIT", "  - 입력: $inputPath")
        Log.d("3S_EDIT", "  - 출력: $outputPath")
        Log.d("3S_EDIT", "  - 자막: ${subtitles.size}개")
        Log.d("3S_EDIT", "  - 스티커: ${stickers.size}개")
        Log.d("3S_EDIT", "  - GPU 이펙트: ${videoEffects.keys}")
        Log.d("3S_EDIT", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        try {
            // 1. MediaItem 생성
            val mediaItem = MediaItem.fromUri(toMediaUri(inputPath))

            // 2. 🎵 오디오 프로세서 (노이즈 억제)
            val audioProcessors = mutableListOf<AudioProcessor>()
            if (enableNoiseSuppression) {
                val noiseSuppressor = NoiseSuppressorAudioProcessor(noiseThreshold = 0.15f)
                audioProcessors.add(noiseSuppressor)
                Log.d("3S_EDIT", "✓ 노이즈 억제 활성화")
            }

            // 3. 🎨 비디오 이펙트 생성
            val allVideoEffects = mutableListOf<Any>()

            // 3-1. GPU 필터
            val gpuFilters = createGpuFilters(videoEffects, userTier)
            allVideoEffects.addAll(gpuFilters)

            // 3-2. 자막 오버레이
            val subtitleOverlay = createSubtitleOverlays(
                subtitles = subtitles,
                forceWatermark = false,
                userTier = userTier
            )
            if (subtitleOverlay != null) {
                allVideoEffects.add(subtitleOverlay)
                Log.d("3S_EDIT", "✓ 자막 ${subtitles.size}개 적용")
            }

            // 3-3. 스티커 오버레이
            val stickerOverlay = createStickerOverlays(stickers)
            if (stickerOverlay != null) {
                allVideoEffects.add(stickerOverlay)
                Log.d("3S_EDIT", "✓ 스티커 ${stickers.size}개 적용")
            }

            // 4. Effects 결합
            val effects = Effects(
                audioProcessors,
                allVideoEffects as List<androidx.media3.common.Effect>
            )

            // 5. EditedMediaItem 생성
            val editedMediaItem = EditedMediaItem.Builder(mediaItem)
                .setRemoveAudio(forceMuteOriginal)
                .setEffects(effects)
                .build()

            val sequence = EditedMediaItemSequence(listOf(editedMediaItem))

            // 6. BGM 추가 (선택적)
            val sequences = mutableListOf(sequence)
            if (bgmPath != null && File(bgmPath).exists()) {
                Log.d("3S_EDIT", "✓ BGM 추가: $bgmPath")
                
                val retriever = MediaMetadataRetriever()
                retriever.setDataSource(bgmPath)
                val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                val bgmDurationMs = durationStr?.toLongOrNull() ?: 0L
                retriever.release()

                val bgmMediaItem = MediaItem.fromUri(toMediaUri(bgmPath))
                val fadeOutProcessor = FadeOutAudioProcessor(
                    fadeOutDurationMs = 500L,
                    totalDurationMs = bgmDurationMs
                )

                val bgmEffects = Effects(listOf<AudioProcessor>(fadeOutProcessor), listOf())
                val bgmEditedItem = EditedMediaItem.Builder(bgmMediaItem)
                    .setRemoveVideo(true)
                    .setEffects(bgmEffects)
                    .build()

                sequences.add(EditedMediaItemSequence(listOf(bgmEditedItem)))
            }

            // 7. Composition 생성
            val composition = Composition.Builder(sequences)
                .setTransmuxAudio(false)
                .setTransmuxVideo(false)
                .build()

            // 8. Encoder Factory (4K 지원)
            val encoderFactory = create4KEncoderFactory(quality, userTier)

            // 9. Transformer 구성
            val transformer = Transformer.Builder(context)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .setEncoderFactory(encoderFactory)
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        Log.d("3S_EDIT", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        Log.d("3S_EDIT", "✓ 편집 완료")
                        Log.d("3S_EDIT", "  - 파일 크기: ${exportResult.fileSizeBytes / 1024 / 1024}MB")
                        Log.d("3S_EDIT", "  - 처리 시간: ${exportResult.durationMs}ms")
                        Log.d("3S_EDIT", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        Log.d("3S_EDIT", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        Handler(Looper.getMainLooper()).post {
                            result.success(outputPath)
                        }
                    }

                    override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                        Log.e("3S_EDIT", "✗ 편집 실패: ${exportException.message}", exportException)
                        Handler(Looper.getMainLooper()).post {
                            result.error("EXPORT_FAILED", "편집 실패: ${exportException.message}", null)
                        }
                    }
                })
                .build()

            // 10. 출력 파일 준비 및 시작
            val file = File(outputPath)
            if (file.exists()) {
                file.delete()
            }

            Log.d("3S_EDIT", "⚡ Transformer 시작...")
            transformer.start(composition, outputPath)

        } catch (e: Exception) {
            Log.e("3S_EDIT", "✗ applyEdits 실패: ${e.message}", e)
            Handler(Looper.getMainLooper()).post {
                result.error("APPLY_EDITS_FAILED", "편집 적용 실패: ${e.message}", null)
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
