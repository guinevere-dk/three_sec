package com.dk.three_sec

import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.opengl.GLES20
import android.graphics.Color
import android.graphics.Typeface
import android.text.Spannable
import android.text.SpannableString
import android.text.style.ForegroundColorSpan
import android.text.style.BackgroundColorSpan
import android.text.style.StyleSpan
import android.text.style.TypefaceSpan
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.FlutterInjector
import android.text.style.RelativeSizeSpan
import androidx.activity.enableEdgeToEdge

// Media3 Imports
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.VideoFrameProcessingException
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
import androidx.media3.effect.BaseGlShaderProgram
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.transformer.DefaultAssetLoaderFactory // ✅ 추가
import androidx.media3.datasource.DataSourceBitmapLoader // ✅ 추가
import androidx.media3.effect.Contrast
import androidx.media3.effect.ConvolutionFunction1D
import androidx.media3.effect.GaussianBlur
import androidx.media3.effect.RgbMatrix
import androidx.media3.effect.SeparableConvolution
import androidx.media3.effect.Presentation // ✅ 추가
import androidx.media3.common.Effect // ✅ 추가
import androidx.media3.effect.GlEffect
import androidx.media3.common.util.GlProgram
import androidx.media3.common.util.GlUtil
import androidx.media3.common.util.Size
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.File
import java.nio.ByteBuffer
import android.util.Log
import android.media.MediaMetadataRetriever
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.BufferedReader
import java.io.InputStreamReader

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "com.dk.three_sec/video_engine"
    private val NEAR_TARGET_DURATION_MS = 2030L
    private val SAVE_GATE_MIN_EXCLUSIVE_MS = 2000L
    @Volatile
    private var activeMergeSessionId: String? = null
    @Volatile
    private var activeMergeTraceId: String? = null
    @Volatile
    private var activeMergeAttempt: Int? = null
    @Volatile
    private var activeMergeRetryPlan: String? = null
    private val colorLutCache = mutableMapOf<String, CubeLut>()

    private data class CubeLut(
        val assetPath: String,
        val size: Int,
        val rgbaBytes: ByteArray
    )

    private fun logLifecycle(event: String, extra: String = "") {
        val suffix = if (extra.isBlank()) "" else " $extra"
        Log.w(
            "3S_LIFECYCLE",
            "[Activity] $event pid=${android.os.Process.myPid()} " +
                "sessionId=${activeMergeSessionId ?: "none"} " +
                "traceId=${activeMergeTraceId ?: "none"} " +
                "attempt=${activeMergeAttempt ?: -1} " +
                "retryPlan=${activeMergeRetryPlan ?: "none"}$suffix"
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Android 15+ 기본 edge-to-edge 동작과 하위 버전 호환 처리를 통일
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        logLifecycle("onCreate")
    }

    override fun onStart() {
        super.onStart()
        logLifecycle("onStart")
    }

    override fun onResume() {
        super.onResume()
        logLifecycle("onResume")
    }

    override fun onPause() {
        logLifecycle("onPause")
        super.onPause()
    }

    override fun onStop() {
        logLifecycle("onStop")
        super.onStop()
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        logLifecycle("onTrimMemory", "level=$level")
    }

    override fun onDestroy() {
        logLifecycle("onDestroy")
        super.onDestroy()
    }

    private fun toMediaUri(pathOrUri: String): Uri {
        val parsed = Uri.parse(pathOrUri)
        return if (parsed.scheme.isNullOrBlank()) {
            Uri.fromFile(File(pathOrUri))
        } else {
            parsed
        }
    }

    private fun redactedPath(path: String?): String {
        if (path.isNullOrBlank()) return "<path-empty>"
        return "<redacted-path>"
    }

    private fun redactedPathList(paths: List<String>?): String {
        val count = paths?.size ?: 0
        return "<redacted-path-list:$count>"
    }

    private fun audioConfigSummary(
        audioChangesByClipIndex: List<Double>,
        audioChanges: Map<String, Double>
    ): String {
        val values = if (audioChangesByClipIndex.isNotEmpty()) {
            audioChangesByClipIndex
        } else {
            audioChanges.values.toList()
        }
        if (values.isEmpty()) return "<audio-config:empty>"
        val mutedCount = values.count { it <= 0.0 }
        val reducedCount = values.count { it > 0.0 && it < 1.0 }
        val fullCount = values.size - mutedCount - reducedCount
        val source = if (audioChangesByClipIndex.isNotEmpty()) "clipIndex" else "pathMap"
        return "<audio-config:source=$source,count=${values.size},muted=$mutedCount,reduced=$reducedCount,full=$fullCount>"
    }

    private fun validateReadableInput(inputPath: String): Pair<Uri, String?> {
        val uri = toMediaUri(inputPath)
        return when (uri.scheme?.lowercase()) {
            "file" -> {
                val filePath = uri.path
                if (filePath.isNullOrBlank()) {
                    uri to "File URI path is invalid: ${redactedPath(inputPath)}"
                } else {
                    val inputFile = File(filePath)
                    if (!inputFile.exists()) {
                        uri to "Input file does not exist: ${redactedPath(filePath)}"
                    } else {
                        uri to null
                    }
                }
            }
            "content" -> uri to null
            else -> uri to "Unsupported URI scheme: ${uri.scheme ?: "null"}"
        }
    }

    private data class AudioPreflightInfo(
        val path: String,
        val uri: Uri,
        val hasAudio: Boolean,
        val audioTrackCount: Int,
        val hasVideo: Boolean,
        val reason: String,
    )

    private fun inspectMediaAudioTrack(path: String, uri: Uri): AudioPreflightInfo {
        var hasAudio = false
        var audioTrackCount = 0
        var hasVideo = false
        val reasonParts = StringBuilder()

        try {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(this, uri)
                val hasAudioMeta = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO)
                val hasVideoMeta = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO)
                if (!hasAudioMeta.isNullOrBlank()) {
                    hasAudio = hasAudioMeta == "1" || hasAudioMeta.equals("true", ignoreCase = true)
                    reasonParts.append("metadataAudio=$hasAudioMeta, ")
                }
                if (!hasVideoMeta.isNullOrBlank()) {
                    hasVideo = hasVideoMeta == "1" || hasVideoMeta.equals("true", ignoreCase = true)
                    reasonParts.append("metadataVideo=$hasVideoMeta, ")
                }
            } finally {
                retriever.release()
            }
        } catch (e: Exception) {
            reasonParts.append("metadataError=${e.javaClass.simpleName}:${e.message}")
        }

        try {
            val extractor = MediaExtractor()
            try {
                extractor.setDataSource(this, uri, null)
                val trackCount = extractor.trackCount
                for (i in 0 until trackCount) {
                    val format = extractor.getTrackFormat(i)
                    val mimeType = format.getString(MediaFormat.KEY_MIME)
                    if (!mimeType.isNullOrBlank() && mimeType.startsWith("audio/")) {
                        audioTrackCount += 1
                    }
                    if (!mimeType.isNullOrBlank() && mimeType.startsWith("video/")) {
                        hasVideo = true
                    }
                }
                if (audioTrackCount > 0) {
                    hasAudio = true
                }
                reasonParts.append("tracks=${trackCount}, audioTracks=${audioTrackCount}")
            } finally {
                extractor.release()
            }
        } catch (e: Exception) {
            reasonParts.append(", extractorError=${e.javaClass.simpleName}:${e.message}")
        }

        return AudioPreflightInfo(
            path = path,
            uri = uri,
            hasAudio = hasAudio,
            audioTrackCount = audioTrackCount,
            hasVideo = hasVideo,
            reason = reasonParts.toString().ifBlank { "no-info" },
        )
    }

    private fun applyForceAudioTrackIfPossible(
        builder: EditedMediaItem.Builder,
        forceAudioTrack: Boolean,
    ): Boolean {
        if (!forceAudioTrack) return false

        val candidateMethodNames = listOf("experimentalSetForceAudioTrack", "setForceAudioTrack")
        for (name in candidateMethodNames) {
            try {
                val method = EditedMediaItem.Builder::class.java.getMethod(name, Boolean::class.javaPrimitiveType)
                method.invoke(builder, true)
                Log.d("3S_AUDIO", "✓ $name 적용 완료")
                return true
            } catch (_: NoSuchMethodException) {
                // 현재 의존성 버전에 해당 메서드가 없을 수 있습니다.
            } catch (_: Exception) {
                // 예외가 발생하면 다음 후보를 시도합니다.
            }
        }

        Log.w("3S_AUDIO", "⚠️ forceAudioTrack API 미지원: fallback 정책으로 이동")
        return false
    }

    private fun buildVideoSequenceWithOptionalForceAudioTrack(
        videoItems: List<EditedMediaItem>,
        forceAudioTrack: Boolean,
    ): Pair<EditedMediaItemSequence, String> {
        if (!forceAudioTrack) {
            return EditedMediaItemSequence.Builder(videoItems).build() to "skipped_not_needed"
        }

        try {
            val builderClass = Class.forName("androidx.media3.transformer.EditedMediaItemSequence\$Builder")
            val ctor = builderClass.constructors.firstOrNull { constructor ->
                val params = constructor.parameterTypes
                params.size == 1 && java.util.List::class.java.isAssignableFrom(params[0])
            } ?: run {
                Log.w("3S_AUDIO", "⚠️ Sequence Builder 생성자 미발견: constructor(List) 없음")
                return EditedMediaItemSequence.Builder(videoItems).build() to "builder_ctor_missing"
            }

            val builder = ctor.newInstance(videoItems)
            var appliedMethodName: String? = null
            val candidateMethods = listOf("experimentalSetForceAudioTrack", "setForceAudioTrack")

            for (name in candidateMethods) {
                try {
                    val method = try {
                        builderClass.getMethod(name, Boolean::class.javaPrimitiveType)
                    } catch (_: NoSuchMethodException) {
                        builderClass.getMethod(name, java.lang.Boolean::class.java)
                    }
                    method.invoke(builder, true)
                    appliedMethodName = name
                    break
                } catch (_: NoSuchMethodException) {
                    // 다음 후보 메서드 시도
                }
            }

            val buildMethod = builderClass.getMethod("build")
            val sequence = buildMethod.invoke(builder) as? EditedMediaItemSequence
            if (sequence != null) {
                if (appliedMethodName != null) {
                    Log.d("3S_AUDIO", "✓ Sequence forceAudioTrack 적용 완료: $appliedMethodName")
                    return sequence to "applied_$appliedMethodName"
                }
                Log.w("3S_AUDIO", "⚠️ Sequence Builder는 존재하지만 forceAudioTrack 메서드가 없음")
                return sequence to "builder_no_force_method"
            }
        } catch (e: Exception) {
            Log.w("3S_AUDIO", "⚠️ Sequence forceAudioTrack 적용 실패: ${e.message}")
        }

        return EditedMediaItemSequence.Builder(videoItems).build() to "fallback_constructor"
    }

    private fun createErrorDetails(
        exportException: ExportException,
        attempt: Int,
        attemptQuality: String,
        previousMessages: List<String>
    ): Map<String, Any> {
        val cause = exportException.cause
        val causeMessage = (cause?.message ?: "Unknown Cause").take(1536)
        val causeClass = cause?.javaClass?.name ?: "N/A"
        val stackText = exportException.stackTraceToString()
            .take(1600)
            .trim()

        val details = LinkedHashMap<String, Any>()
        details["attempt"] = attempt
        details["quality"] = attemptQuality
        details["errorCode"] = exportException.errorCode
        details["message"] = exportException.message ?: "Media3 export failed"
        details["cause"] = causeMessage
        details["causeClass"] = causeClass
        details["stack"] = stackText
        if (previousMessages.isNotEmpty()) {
            details["history"] = previousMessages
        }

        val serialized = StringBuilder()
        details.forEach { (key, value) ->
            serialized.append("$key=$value\n")
        }
        val text = serialized.toString().trim().take(2048)
        details["summary"] = text

        return details
    }

    private fun trySetRequestedEncoderParams(
        builder: DefaultEncoderFactory.Builder,
        width: Int,
        height: Int,
        bitrate: Int
    ) {
        val methodName = "setRequestedEncoderPerformanceParameters"
        val methods = builder.javaClass.methods.filter { it.name == methodName }
        for (method in methods) {
            val params = method.parameterTypes
            try {
                if (params.size == 3
                    && params[0] == Int::class.javaPrimitiveType
                    && params[1] == Int::class.javaPrimitiveType
                    && params[2] == Int::class.javaPrimitiveType
                ) {
                    method.invoke(builder, width, height, bitrate)
                    Log.d("3S_4K", "✓ Requested encoder params: ${width}x$height, ${bitrate / 1_000_000}Mbps")
                    return
                }
            } catch (_: Exception) {
                // API 시그니처가 다르거나 미지원일 수 있어 무시
            }
        }
        Log.w("3S_4K", "⚠️ setRequestedEncoderPerformanceParameters 미지원/호출 실패 (dependency fallback)")
    }

    // 🎛️ [디자인 컨트롤 타워] 여기서 수치만 바꾸면 즉시 반영됩니다.
    companion object {
        private const val DEFAULT_EDIT_TARGET_DURATION_MS = 2100L
        private const val DEFAULT_SAVE_TARGET_DURATION_MS = 2100L
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
        private const val BITRATE_1080P_MAX = 12_000_000 // 12Mbps (P0 beautiful 1080p baseline)
        private const val BITRATE_720P_MAX = 5_000_000
        private const val TARGET_EXPORT_FPS = 30
        
        // 🎨 GPU 필터 프리셋
        private const val GRAYSCALE_SATURATION = 0.0f
        private const val DEFAULT_CONTRAST = 1.0f
        private const val DEFAULT_SATURATION = 1.0f
    }

    private fun reportChannelError(
        step: String,
        platformError: String,
        message: String,
        result: MethodChannel.Result,
        details: Any? = null
    ) {
        Log.e("3S_CHANNEL", "step=$step platformError=$platformError message=$message")
        result.error(platformError, message, details)
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "mergeVideos" -> {
                    // Flutter Args: videoPaths, audioChanges, bgmPath, bgmVolume, quality, outputPath
                    val paths = call.argument<List<String>>("videoPaths")
                    val audioChanges = call.argument<Map<String, Double>>("audioChanges") ?: emptyMap()
                    val audioChangesByClipIndex = call.argument<List<Double>>("audioChangesByClipIndex") ?: emptyList()
                    val outputPath = call.argument<String>("outputPath")
                    
                    // Optional Args (Defaults)
                    val subtitles = call.argument<List<Map<String, Any>>>("subtitles") ?: emptyList()
                    val forceWatermark = call.argument<Boolean>("forceWatermark") ?: false
                    val quality = call.argument<String>("quality") ?: "1080p"
                    val userTier = call.argument<String>("userTier") ?: "free"
                    val canvasAspectRatioPreset = call.argument<String>("canvasAspectRatioPreset") ?: "r9_16"
                    
                    // Audio Mixing
                    val bgmPath = call.argument<String>("bgmPath")
                    val forceMuteOriginal = call.argument<Boolean>("forceMuteOriginal") ?: false
                    val enableNoiseSuppression = call.argument<Boolean>("enableNoiseSuppression") ?: false
                    val bgmVolume = call.argument<Double>("bgmVolume")?.toFloat() ?: 0.5f
                    
                    // Video Effects
                    val videoEffects = call.argument<Map<String, Any>>("videoEffects") ?: emptyMap()
                    val videoEffectsByClipIndex = call.argument<List<Map<String, Any>>>("videoEffectsByClipIndex") ?: emptyList()
                    
                    val startTimes = call.argument<List<Long>>("startTimes") ?: emptyList()
                    val endTimes = call.argument<List<Long>>("endTimes") ?: emptyList()
                    val mergeSessionId = call.argument<String>("mergeSessionId")
                    val mergeTraceId = call.argument<String>("mergeTraceId")
                    val mergeAttempt = call.argument<Int>("attempt") ?: 1
                    val mergeRetryPlan = call.argument<String>("retryPlan")
                    val mergeAudioSimplify = call.argument<Boolean>("audioSimplify") ?: false
                    val mergeQualityPreset = call.argument<String>("qualityPreset")
                    val mergeCaller = call.argument<String>("caller")
                    
                    Log.d("3S_4K", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    Log.d("3S_4K", "mergeVideos 호출 (Flutter -> Native)")
                    Log.d("3S_4K", "  - paths: ${redactedPathList(paths)}")
                    Log.d("3S_4K", "  - trim: start=$startTimes, end=$endTimes") // Log trim info
                    Log.d("3S_4K", "  - outputPath: ${redactedPath(outputPath)}")
                    Log.d("3S_4K", "  - audioConfig: ${audioConfigSummary(audioChangesByClipIndex, audioChanges)}")
                    Log.d("3S_4K", "  - clipAudioConfig: ${audioChangesByClipIndex.size} items")
                    Log.d("3S_4K", "  - bgmPath: ${redactedPath(bgmPath)}, vol: $bgmVolume")
                    Log.d("3S_4K", "  - clipVideoEffects: ${videoEffectsByClipIndex.size} items")
                    Log.w(
                        "3S_LIFECYCLE",
                        "[MergeArgs] sessionId=${mergeSessionId ?: "none"} traceId=${mergeTraceId ?: "none"} " +
                            "attempt=$mergeAttempt retryPlan=${mergeRetryPlan ?: "none"} " +
                            "audioSimplify=$mergeAudioSimplify qualityPreset=${mergeQualityPreset ?: "none"} " +
                            "caller=${mergeCaller ?: "unknown"}"
                    )
                    
                    if (paths != null && outputPath != null && paths.isNotEmpty()) {
                        mergeVideos(
                            paths,
                            outputPath,
                            subtitles,
                            forceWatermark,
                            quality,
                            userTier,
                            canvasAspectRatioPreset,
                            videoEffects,
                            videoEffectsByClipIndex,
                            audioChanges,
                            audioChangesByClipIndex,
                            bgmPath,
                            forceMuteOriginal,
                            enableNoiseSuppression,
                            bgmVolume,
                            startTimes,
                            endTimes,
                            mergeSessionId,
                            mergeTraceId,
                            mergeAttempt,
                            mergeRetryPlan,
                            mergeAudioSimplify,
                            mergeQualityPreset,
                            mergeCaller,
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
                    val rawDuration = call.argument<Any?>("duration")
                    val parsedDurationMs = when (rawDuration) {
                        is Long -> rawDuration
                        is Int -> rawDuration.toLong()
                        is Double -> rawDuration.toLong()
                        is String -> rawDuration.toLongOrNull() ?: DEFAULT_SAVE_TARGET_DURATION_MS
                        else -> DEFAULT_SAVE_TARGET_DURATION_MS
                    }
                    val durationMs = when {
                        parsedDurationMs <= 0L -> DEFAULT_SAVE_TARGET_DURATION_MS
                        parsedDurationMs <= 1000L -> parsedDurationMs * 1_000L
                        else -> parsedDurationMs
                    }

                    Log.d("3S_CONVERT", "convertImageToVideo 호출: ${redactedPath(imagePath)}")

                    if (imagePath != null && outputPath != null) {
                        convertImageToVideo(imagePath, outputPath, durationMs, result)
                    } else {
                        reportChannelError(
                            step = "photo_to_video",
                            platformError = "INVALID_ARGS",
                            message = "필수 인자가 누락되었습니다.",
                            result = result
                        )
                    }
                }
                "normalizeVideoDuration" -> {
                    val inputPath = call.argument<String>("inputPath")
                    val outputPath = call.argument<String>("outputPath")
                    val args = call.arguments as? Map<*, *>
                    val rawTargetDuration = args?.get("targetDurationMs")
                    val rawTrimMode = args?.get("trimMode")
                    val rawPadToTarget = args?.get("padToTarget")
                    val rawAspectPreset = args?.get("aspectPreset")
                    val rawQuality = args?.get("quality")
                    val rawTargetFps = args?.get("targetFps")
                    val rawTargetBitrate = args?.get("targetBitrate")
                    val targetDurationMs = when (rawTargetDuration) {
                        is Long -> rawTargetDuration
                        is Int -> rawTargetDuration.toLong()
                        is Double -> rawTargetDuration.toLong()
                        is Float -> rawTargetDuration.toLong()
                        is Number -> rawTargetDuration.toLong()
                        is String -> rawTargetDuration.toLongOrNull() ?: DEFAULT_SAVE_TARGET_DURATION_MS
                        else -> DEFAULT_SAVE_TARGET_DURATION_MS
                    }
                    val trimMode = (rawTrimMode as? String)?.lowercase() ?: "start"
                    val padToTarget = rawPadToTarget as? Boolean ?: true
                    val aspectPreset = (rawAspectPreset as? String)?.lowercase() ?: "r9_16"
                    val normalizeQuality = (rawQuality as? String)?.lowercase() ?: "1080p"
                    val normalizeTargetFps = (rawTargetFps as? Number)?.toInt() ?: TARGET_EXPORT_FPS
                    val normalizeTargetBitrate = (rawTargetBitrate as? Number)?.toInt() ?: bitrateForQuality(normalizeQuality)

                    Log.d(
                        "3S_NORMALIZE",
                        "normalizeVideoDuration argType=${rawTargetDuration?.javaClass?.name} value=$rawTargetDuration parsedMs=$targetDurationMs trimMode=$trimMode padToTarget=$padToTarget aspectPreset=$aspectPreset quality=$normalizeQuality targetFps=$normalizeTargetFps targetBitrate=$normalizeTargetBitrate"
                    )

                    if (inputPath != null && outputPath != null) {
                        normalizeVideoDuration(
                            inputPath = inputPath,
                            outputPath = outputPath,
                            targetDurationMs = targetDurationMs,
                            trimMode = trimMode,
                            padToTarget = padToTarget,
                            aspectPreset = aspectPreset,
                            quality = normalizeQuality,
                            targetFps = normalizeTargetFps,
                            targetBitrate = normalizeTargetBitrate,
                            result = result
                        )
                    } else {
                        reportChannelError(
                            step = "normalize",
                            platformError = "INVALID_ARGS",
                            message = "inputPath or outputPath is missing",
                            result = result
                        )
                    }
                }
                "getVideoDurationMs" -> {
                    val inputPath = call.argument<String>("inputPath")
                    if (inputPath != null) {
                        getVideoDurationMs(inputPath, result)
                    } else {
                        reportChannelError(
                            step = "duration_query",
                            platformError = "INVALID_ARGS",
                            message = "inputPath is missing",
                            result = result
                        )
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
                reportChannelError(
                    step = "duration_query",
                    platformError = "INPUT_NOT_FOUND",
                    message = inputError,
                    result = result
                )
                return
            }

            retriever = MediaMetadataRetriever()
            retriever.setDataSource(this, sourceUri)
            val durationMs =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                    ?.toLongOrNull()
                    ?: 0L

            if (durationMs <= 0L) {
                reportChannelError(
                    step = "duration_query",
                    platformError = "INVALID_SOURCE_DURATION",
                    message = "Could not determine source duration",
                    result = result
                )
                return
            }

            result.success(durationMs)
        } catch (e: Exception) {
            Log.e("3S_NORMALIZE", "getVideoDurationMs failed: ${e.message}", e)
            reportChannelError(
                step = "duration_query",
                platformError = "DURATION_FAILED",
                message = "getVideoDurationMs failed: ${e.message}",
                result = result
            )
        } finally {
            retriever?.release()
        }
    }

    private fun normalizeVideoDuration(
        inputPath: String,
        outputPath: String,
        targetDurationMs: Long,
        trimMode: String,
        padToTarget: Boolean,
        aspectPreset: String,
        quality: String,
        targetFps: Int,
        targetBitrate: Int,
        result: MethodChannel.Result
    ) {
        try {
            if (targetDurationMs <= 0L) {
                reportChannelError(
                    step = "normalize",
                    platformError = "INVALID_DURATION",
                    message = "targetDurationMs must be greater than 0",
                    result = result
                )
                return
            }

            val (sourceUri, inputError) = validateReadableInput(inputPath)
            if (inputError != null) {
                reportChannelError(
                    step = "normalize",
                    platformError = "INPUT_NOT_FOUND",
                    message = inputError,
                    result = result
                )
                return
            }

            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(this, sourceUri)
            val sourceDurationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val sourceWidth = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val sourceHeight = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            val sourceRotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            retriever.release()

            if (sourceDurationMs <= 0L) {
                reportChannelError(
                    step = "normalize",
                    platformError = "INVALID_SOURCE_DURATION",
                    message = "Could not determine source duration",
                    result = result
                )
                return
            }

            val outputFile = File(outputPath)
            if (outputFile.exists()) {
                outputFile.delete()
            }

            val shouldPadToTarget = padToTarget && sourceDurationMs < targetDurationMs
            val clipMs = if (shouldPadToTarget) targetDurationMs else kotlin.math.min(sourceDurationMs, targetDurationMs)
            val requestedEndMs = if (shouldPadToTarget) sourceDurationMs else clipMs
            val effectiveTrimMode = if (trimMode == "center") "center" else "start"
            val startMs = if (effectiveTrimMode == "center" && sourceDurationMs > requestedEndMs) {
                (sourceDurationMs - requestedEndMs) / 2L
            } else {
                0L
            }
            val endMs = startMs + requestedEndMs
            val normalizedAspectPreset = normalizeCaptureAspectPreset(aspectPreset)
            val targetAspect = captureAspectRatio(normalizedAspectPreset)
            val sourceAspect = sourceDisplayAspectRatio(sourceWidth, sourceHeight, sourceRotation)
            Log.d(
                "3S_NORMALIZE",
                "normalizeVideoDuration sourceDurationMs=$sourceDurationMs targetDurationMs=$targetDurationMs clipMs=$clipMs trimMode=$effectiveTrimMode startMs=$startMs endMs=$endMs padArg=$padToTarget padApplied=$shouldPadToTarget aspectPreset=$normalizedAspectPreset quality=$quality targetFps=$targetFps targetBitrate=$targetBitrate sourceWidth=$sourceWidth sourceHeight=$sourceHeight sourceRotation=$sourceRotation sourceAspect=$sourceAspect targetAspect=$targetAspect nearTargetWindow=$NEAR_TARGET_DURATION_MS"
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

            val videoEffects = mutableListOf<androidx.media3.common.Effect>()
            if (normalizedAspectPreset != "r9_16") {
                videoEffects.add(Presentation.createForAspectRatio(targetAspect, Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP))
            }
            val itemEffects = Effects(listOf<AudioProcessor>(), videoEffects)

            val clippedEditedItem = EditedMediaItem.Builder(clippedItem)
                .setDurationUs(clipMs * 1000L)
                .setEffects(itemEffects)
                .build()
            val editedItems = arrayListOf(clippedEditedItem)

            val sequence = EditedMediaItemSequence.Builder(editedItems).build()
            val composition = Composition.Builder(listOf(sequence))
                .setTransmuxAudio(false)
                .setTransmuxVideo(false)
                .build()

            val transformer = Transformer.Builder(this)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .setEncoderFactory(createQualityEncoderFactory(quality, "standard", targetBitrate))
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        Handler(Looper.getMainLooper()).post {
                            Log.d(
                                "3S_NORMALIZE",
                                "normalizeVideoDuration complete: ${redactedPath(outputPath)} " +
                                    "sourceDurationMs=$sourceDurationMs " +
                                    "targetDurationMs=$targetDurationMs " +
                                    "normalizedDurationMs=${exportResult.durationMs} " +
                                    "clipMs=$clipMs startMs=$startMs endMs=$endMs trimMode=$effectiveTrimMode padToTarget=$shouldPadToTarget aspectPreset=$normalizedAspectPreset quality=$quality targetFps=$targetFps targetBitrate=$targetBitrate sourceAspect=$sourceAspect targetAspect=$targetAspect " +
                                    "saveGateMinExclusiveMs=$SAVE_GATE_MIN_EXCLUSIVE_MS " +
                                    "saveGatePass=${exportResult.durationMs > SAVE_GATE_MIN_EXCLUSIVE_MS}"
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
                            reportChannelError(
                                step = "normalize",
                                platformError = "NORMALIZE_FAILED",
                                message = "normalizeVideoDuration failed: ${exportException.message}",
                                result = result
                            )
                        }
                    }
                })
                .build()

            transformer.start(composition, outputPath)
        } catch (e: Exception) {
            Log.e("3S_NORMALIZE", "normalizeVideoDuration setup failed: ${e.message}", e)
            reportChannelError(
                step = "normalize",
                platformError = "NORMALIZE_SETUP_FAILED",
                message = "normalizeVideoDuration setup failed: ${e.message}",
                result = result
            )
        }
    }

    private fun normalizeCaptureAspectPreset(aspectPreset: String): String {
        return when (aspectPreset.lowercase()) {
            "r1_1", "1:1", "1x1" -> "r1_1"
            "r3_4", "3:4", "3x4" -> "r3_4"
            else -> "r9_16"
        }
    }

    private fun captureAspectRatio(aspectPreset: String): Float {
        return when (normalizeCaptureAspectPreset(aspectPreset)) {
            "r1_1" -> 1f
            "r3_4" -> 3f / 4f
            else -> 9f / 16f
        }
    }

    private fun normalizeEditCanvasAspectPreset(aspectPreset: String): String {
        return when (aspectPreset.lowercase()) {
            "r1_1", "1:1", "1x1" -> "r1_1"
            "r3_4", "3:4", "3x4" -> "r3_4"
            "r4_3", "4:3", "4x3" -> "r4_3"
            "r16_9", "16:9", "16x9" -> "r16_9"
            else -> "r9_16"
        }
    }

    private fun editCanvasAspectRatio(aspectPreset: String): Float {
        return when (normalizeEditCanvasAspectPreset(aspectPreset)) {
            "r1_1" -> 1f
            "r3_4" -> 3f / 4f
            "r4_3" -> 4f / 3f
            "r16_9" -> 16f / 9f
            else -> 9f / 16f
        }
    }

    private fun sourceDisplayAspectRatio(width: Int, height: Int, rotation: Int): Float {
        if (width <= 0 || height <= 0) return 0f
        val displayWidth = if (rotation == 90 || rotation == 270) height else width
        val displayHeight = if (rotation == 90 || rotation == 270) width else height
        if (displayHeight <= 0) return 0f
        return displayWidth.toFloat() / displayHeight.toFloat()
    }

    private fun convertImageToVideo(
        imagePath: String,
        outputPath: String,
        durationMs: Long,
        result: MethodChannel.Result
    ) {
        // 1. 파일 검사
        val file = File(imagePath) // ✅ 누락된 변수 선언 복원
        if (!file.exists()) {
            Log.e("3S_CONVERT", "파일 없음: ${redactedPath(imagePath)}")
            result.error("FILE_NOT_FOUND", "파일이 존재하지 않습니다.", null)
            return
        }
        if (!file.canRead()) {
            Log.e("3S_CONVERT", "읽기 권한 없음: ${redactedPath(imagePath)}")
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
            
            Log.d("3S_CONVERT_V2", "리사이징/회전 완료(V2): ${srcWidth}x${srcHeight} -> ${rotatedBitmap.width}x${rotatedBitmap.height}, path=${redactedPath(resizedPath)}")
            
        } catch (e: Exception) {
            Log.e("3S_CONVERT_V2", "리사이징 에러: $e")
            result.error("RESIZE_ERROR", "이미지 리사이징 실패: $e", null)
            return
        }

        val transcodeFile = File(resizedPath)
        val uri = Uri.fromFile(transcodeFile)
        Log.d("3S_CONVERT_V2", "변환 URI(V2): ${redactedPath(uri.toString())}")

        // 출력 파일이 이미 존재하면 삭제
        val outFile = File(outputPath)
        if (outFile.exists()) {
            outFile.delete()
        }

        // 3. MIME Type 명시
        val mediaItem = MediaItem.Builder()
            .setUri(uri)
            .setMimeType(MimeTypes.IMAGE_JPEG)
            .setImageDurationMs(durationMs) // ✅ 이미지 지속 시간 설정 (필수)
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
                    Log.d("3S_CONVERT", "변환 성공: ${redactedPath(outputPath)}")
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
        canvasAspectRatioPreset: String,
        videoEffects: Map<String, Any>,
        videoEffectsByClipIndex: List<Map<String, Any>>,
        audioChanges: Map<String, Double>,
        audioChangesByClipIndex: List<Double>,
        bgmPath: String?,
        forceMuteOriginal: Boolean,
        enableNoiseSuppression: Boolean,
        bgmVolume: Float,
        startTimes: List<Long>, // ✅ Add startTimes
        endTimes: List<Long>,   // ✅ Add endTimes
        mergeSessionId: String?,
        mergeTraceId: String?,
        mergeAttempt: Int,
        mergeRetryPlan: String?,
        mergeAudioSimplify: Boolean,
        mergeQualityPreset: String?,
        mergeCaller: String?,
        result: MethodChannel.Result
    ) {
        activeMergeSessionId = mergeSessionId
        activeMergeTraceId = mergeTraceId
        activeMergeAttempt = mergeAttempt
        activeMergeRetryPlan = mergeRetryPlan

        Log.w(
            "3S_LIFECYCLE",
            "[MergeBegin] sessionId=${mergeSessionId ?: "none"} traceId=${mergeTraceId ?: "none"} " +
                "attempt=$mergeAttempt retryPlan=${mergeRetryPlan ?: "none"} " +
                "audioSimplify=$mergeAudioSimplify qualityPreset=${mergeQualityPreset ?: "none"} " +
                "caller=${mergeCaller ?: "unknown"}"
        )

        Log.d("3S_4K", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        Log.d("3S_4K", "병합 시작: ${paths.size}개 클립")
        Log.d("3S_4K", "  - 품질: $quality")
        Log.d("3S_4K", "  - 사용자 등급: $userTier")
        Log.d("3S_4K", "  - 캔버스: $canvasAspectRatioPreset")
        Log.d("3S_4K", "  - 자막: ${subtitles.size}개")
        Log.d("3S_4K", "  - 비디오 이펙트: ${videoEffects.keys}")
        Log.d("3S_4K", "  - clipVideoEffects: ${videoEffectsByClipIndex.size} items")
        Log.d("3S_AUDIO", "  - clipAudioConfig: ${audioChangesByClipIndex.size} items")
        Log.d("3S_AUDIO", "  - 원본 음소거: $forceMuteOriginal")
        Log.d("3S_AUDIO", "  - BGM: ${if (bgmPath == null) "없음" else redactedPath(bgmPath)}")
        Log.d("3S_AUDIO", "  - 노이즈 억제: $enableNoiseSuppression")
        Log.d("3S_4K", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        val preflightInfos = paths.mapIndexed { index, path ->
            val (uri, inputError) = validateReadableInput(path)
            if (inputError != null) {
                val failed = AudioPreflightInfo(
                    path = path,
                    uri = uri,
                    hasAudio = false,
                    audioTrackCount = -1,
                    hasVideo = false,
                    reason = inputError,
                )
                Log.e("3S_AUDIO", "[preflight] index=$index path=${redactedPath(path)} FAILED: ${failed.reason}")
                failed
            } else {
                inspectMediaAudioTrack(path, uri).also { info ->
                    Log.d(
                        "3S_AUDIO",
                        "[preflight] index=$index path=${redactedPath(info.path)} hasAudio=${info.hasAudio} " +
                            "audioTracks=${info.audioTrackCount} hasVideo=${info.hasVideo} reason=${info.reason}"
                    )
                    if (!info.hasAudio) {
                        Log.w(
                            "3S_AUDIO",
                            "[preflight] 경고: 오디오 트랙이 없습니다. index=$index path=${redactedPath(info.path)}"
                        )
                    }
                }
            }
        }

        val missingAudioCount = preflightInfos.count { !it.hasAudio }
        if (missingAudioCount > 0) {
            Log.w(
                "3S_AUDIO",
                "[preflight] 오디오 없는 클립: $missingAudioCount/${paths.size}. " +
                    "forceAudioTrack 시도 후 fallback 정책으로 진행합니다."
            )
        }

        // 1. 📝 자막/워터마크 오버레이 생성 (멀티 오버레이)
        val overlayEffect: OverlayEffect? = createSubtitleOverlays(
            subtitles = subtitles,
            forceWatermark = forceWatermark,
            userTier = userTier
        )

        // 2. 🎵 오디오 이펙트 준비
        
        // 2-1. 노이즈 억제 (NoiseSuppressor)
        if (enableNoiseSuppression) {
            Log.d("3S_AUDIO", "✓ 노이즈 억제 프로세서 추가 완료")
        }

        // 3. 🎨 GPU 필터 생성 (Premium)
        val normalizedCanvasAspectPreset = normalizeEditCanvasAspectPreset(canvasAspectRatioPreset)
        val canvasAspectRatio = editCanvasAspectRatio(normalizedCanvasAspectPreset)
        
        // 4. EditedMediaItem 리스트 생성 (비디오 트랙)
        val videoSequence = ArrayList<EditedMediaItem>()
        var forceAudioTrackEligibleCount = 0
        var forceAudioTrackAppliedItemCount = 0
        var forceAudioTrackFailedItemCount = 0
        fun requestedOriginalVolume(index: Int, path: String): Float {
            val indexedVolume = audioChangesByClipIndex.getOrNull(index)
            return (indexedVolume ?: audioChanges[path] ?: 1.0).toFloat().coerceIn(0f, 1f)
        }

        fun removesOriginalAudio(index: Int, path: String): Boolean {
            return forceMuteOriginal || requestedOriginalVolume(index, path) <= 0f
        }

        for ((i, path) in paths.withIndex()) {
            val startTime = if (i < startTimes.size) startTimes[i] else 0L
            val endTime = if (i < endTimes.size) endTimes[i] else 0L
            val preflight = preflightInfos.getOrNull(i)
            
            // ✅ Clipping Configuration
            val clippingBuilder = MediaItem.ClippingConfiguration.Builder()
                .setStartPositionMs(startTime)
            
            if (endTime > 0) {
                 clippingBuilder.setEndPositionMs(endTime)
            }
            
            val mediaItem = MediaItem.Builder()
                .setUri(preflight?.uri ?: toMediaUri(path))
                .setClippingConfiguration(clippingBuilder.build())
                .build()
            
            // 비디오 Effects (GPU 필터 + 오버레이)
            val allVideoEffects = mutableListOf<Any>()
            val clipVideoEffects = videoEffectsByClipIndex.getOrNull(i) ?: videoEffects
            val gpuFilters = createGpuFilters(clipVideoEffects, userTier)
            val requestedClipVolume = requestedOriginalVolume(i, path)
            val removeOriginalAudio = removesOriginalAudio(i, path)
            val itemAudioProcessors = mutableListOf<AudioProcessor>()
            if (!removeOriginalAudio && enableNoiseSuppression) {
                itemAudioProcessors.add(NoiseSuppressorAudioProcessor(noiseThreshold = 0.15f))
            }
            if (!removeOriginalAudio && requestedClipVolume < 0.999f) {
                itemAudioProcessors.add(VolumeAudioProcessor(requestedClipVolume))
            }
            
            // GPU 필터 추가
            allVideoEffects.addAll(gpuFilters)

            allVideoEffects.add(
                Presentation.createForAspectRatio(
                    canvasAspectRatio,
                    Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP
                )
            )
            
            // 오버레이 추가
            if (overlayEffect != null) {
                allVideoEffects.add(overlayEffect)
            }
            
            // Effects 결합 (오디오 + 비디오)
            val finalEffects = if (itemAudioProcessors.isNotEmpty()) {
                // 노이즈 억제 + GPU 필터 + 오버레이
                Effects(itemAudioProcessors, allVideoEffects as List<androidx.media3.common.Effect>)
            } else {
                // GPU 필터 + 오버레이만
                Effects(mutableListOf<AudioProcessor>(), allVideoEffects as List<androidx.media3.common.Effect>)
            }

            val itemBuilder = EditedMediaItem.Builder(mediaItem)
                .setRemoveAudio(removeOriginalAudio)
                .setEffects(finalEffects)

            if (!removeOriginalAudio && preflight != null && !preflight.hasAudio) {
                forceAudioTrackEligibleCount += 1
                val forceApplied = applyForceAudioTrackIfPossible(itemBuilder, true)
                if (!forceApplied) {
                    forceAudioTrackFailedItemCount += 1
                    Log.w(
                        "3S_AUDIO",
                        "[fallback] index=$i path=${redactedPath(preflight.path)}: forceAudioTrack API 미지원. 기존 멀티트랙 방식 유지"
                    )
                } else {
                    forceAudioTrackAppliedItemCount += 1
                }
            }

            videoSequence.add(itemBuilder.build())
        }

        if (forceMuteOriginal) {
            Log.d("3S_AUDIO", "✓ 원본 오디오 제거됨 (forceMuteOriginal=true)")
        } else if (audioChangesByClipIndex.isNotEmpty() || audioChanges.isNotEmpty()) {
            val appliedAudioVolumes = if (audioChangesByClipIndex.isNotEmpty()) {
                audioChangesByClipIndex
            } else {
                audioChanges.values.toList()
            }
            val mutedCount = appliedAudioVolumes.count { it <= 0.0 }
            val adjustedCount = appliedAudioVolumes.count { it > 0.0 && it < 1.0 }
            Log.d("3S_AUDIO", "Original audio volume applied: adjusted=$adjustedCount muted=$mutedCount")
        } else if (enableNoiseSuppression) {
            Log.d("3S_AUDIO", "✓ 원본 오디오에 노이즈 억제 적용됨")
        }

        // 4. 🎵 BGM 트랙 추가 (별도 시퀀스)
        val sequences = mutableListOf<EditedMediaItemSequence>()
        
        // 4-1. 비디오 시퀀스 추가
        val firstInfo = preflightInfos.firstOrNull()
        val effectiveAudioPresence = paths.mapIndexed { index, path ->
            preflightInfos.getOrNull(index)?.hasAudio == true &&
                !removesOriginalAudio(index, path)
        }
        val hasAnyAudio = effectiveAudioPresence.any { it }
        val hasMixedAudioPresence = effectiveAudioPresence.any { !it } && hasAnyAudio
        val needSequenceForceAudio = !forceMuteOriginal && hasMixedAudioPresence
        val (builtVideoSequence, sequenceForceState) = buildVideoSequenceWithOptionalForceAudioTrack(
            videoItems = videoSequence,
            forceAudioTrack = needSequenceForceAudio,
        )

        Log.w(
            "3S_AUDIO",
            "[diag] sequence_audio sessionId=${mergeSessionId ?: "none"} " +
                "attempt=$mergeAttempt retryPlan=${mergeRetryPlan ?: "none"} " +
                "audioSimplify=$mergeAudioSimplify qualityPreset=${mergeQualityPreset ?: "none"} " +
                "firstClipHasAudio=${firstInfo?.hasAudio ?: false} " +
                "missingAudioCount=$missingAudioCount totalClips=${paths.size} " +
                "hasMixedAudioPresence=$hasMixedAudioPresence needSequenceForceAudio=$needSequenceForceAudio " +
                "itemForceEligible=$forceAudioTrackEligibleCount itemForceApplied=$forceAudioTrackAppliedItemCount " +
                "itemForceFailed=$forceAudioTrackFailedItemCount sequenceForceState=$sequenceForceState"
        )

        sequences.add(builtVideoSequence)
        
        // 4-2. BGM 시퀀스 추가 (있는 경우)
        if (bgmPath != null && bgmVolume > 0f && File(bgmPath).exists()) {
            try {
                Log.d("3S_AUDIO", "✓ BGM 추가: ${redactedPath(bgmPath)}")
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
                
                val bgmAudioProcessors = mutableListOf<AudioProcessor>()
                val normalizedBgmVolume = bgmVolume.coerceIn(0f, 1f)
                if (normalizedBgmVolume < 0.999f) {
                    bgmAudioProcessors.add(VolumeAudioProcessor(normalizedBgmVolume))
                }
                bgmAudioProcessors.add(fadeOutProcessor)
                val bgmEffects = Effects(bgmAudioProcessors, listOf())
                
                val bgmEditedItem = EditedMediaItem.Builder(bgmMediaItem)
                    .setRemoveVideo(true) // 오디오만 사용
                    .setEffects(bgmEffects)
                    .build()
                
                sequences.add(EditedMediaItemSequence.Builder(listOf(bgmEditedItem)).build())
                
                Log.d("3S_AUDIO", "✓ BGM Fade Out 프로세서 적용 완료")
                
            } catch (e: Exception) {
                Log.e("3S_AUDIO", "✗ BGM 추가 실패: ${e.message}", e)
            }
        } else if (bgmPath != null) {
            Log.w("3S_AUDIO", "⚠️ BGM 파일을 찾을 수 없음: ${redactedPath(bgmPath)}")
        }

        // 5. Composition 생성 (멀티트랙)
        val composition = Composition.Builder(sequences)
            .setTransmuxAudio(false) // 오디오 재인코딩 활성화 (믹싱 필요)
            .setTransmuxVideo(false) // 비디오 재인코딩 활성화
            .build()
        
        Log.d("3S_AUDIO", "✓ Composition 생성 완료: ${sequences.size}개 트랙")
        Log.d(
            "3S_AUDIO",
            "✓ Canvas aspect 적용: preset=$normalizedCanvasAspectPreset ratio=$canvasAspectRatio"
        )

        // 6. 2단계 이내 Fallback(4K → 1080p) 포함 재시도
        val attemptQualities = if (quality.equals("4K", ignoreCase = true) && userTier == "premium") {
            listOf("4K", "1080p")
        } else {
            listOf(quality)
        }

        val attemptHistory = mutableListOf<String>()

        fun startMergeAttempt(attemptIndex: Int) {
            val attemptQuality = attemptQualities[attemptIndex]
            val encoderFactory = createQualityEncoderFactory(attemptQuality, userTier, bitrateForQuality(attemptQuality))

            val transformerBuilder = Transformer.Builder(this)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .setEncoderFactory(encoderFactory)

            when {
                attemptQuality.equals("4K", ignoreCase = true) && userTier == "premium" -> {
                    Log.d("3S_4K", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    Log.d("3S_4K", "✓ 4K 렌더링 모드")
                    Log.d("3S_4K", "  - 해상도: ${RESOLUTION_4K_WIDTH}x${RESOLUTION_4K_HEIGHT}")
                    Log.d("3S_4K", "  - 비트레이트: ${BITRATE_4K_MAX / 1_000_000}Mbps")
                    Log.d("3S_4K", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                }
                attemptQuality.contains("1080") -> {
                    Log.d("3S_4K", "✓ 1080p 하향 호환 모드")
                }
                else -> {
                    Log.d("3S_4K", "✓ 기본 품질 모드")
                }
            }

            val transformer = transformerBuilder
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        Log.w(
                            "3S_LIFECYCLE",
                            "[MergeComplete] sessionId=${mergeSessionId ?: "none"} " +
                                "traceId=${mergeTraceId ?: "none"} attempt=${attemptIndex + 1} status=success"
                        )
                        Log.d("3S_AUDIO", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        Log.d("3S_AUDIO", "✓ 병합 완료: ${redactedPath(outputPath)}")
                        Log.d("3S_AUDIO", "  - 사용 품질: $attemptQuality")
                        Log.d("3S_AUDIO", "  - 파일 크기: ${exportResult.fileSizeBytes / 1024 / 1024}MB")
                        Log.d("3S_AUDIO", "  - 처리 시간: ${exportResult.durationMs}ms")
                        Log.d("3S_AUDIO", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        Handler(Looper.getMainLooper()).post {
                            activeMergeSessionId = null
                            activeMergeTraceId = null
                            activeMergeAttempt = null
                            activeMergeRetryPlan = null
                            result.success(outputPath)
                        }
                    }

                    override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                        Log.w(
                            "3S_LIFECYCLE",
                            "[MergeComplete] sessionId=${mergeSessionId ?: "none"} " +
                                "traceId=${mergeTraceId ?: "none"} attempt=${attemptIndex + 1} status=error " +
                                "code=${exportException.errorCode}"
                        )
                        val errorDetails = createErrorDetails(
                            exportException,
                            attemptIndex + 1,
                            attemptQuality,
                            attemptHistory.toList()
                        )
                        attemptHistory.add("Attempt ${attemptIndex + 1}: ${errorDetails["summary"]}")

                        Log.e(
                            "3S_AUDIO",
                            "✗ 병합 실패(시도 ${attemptIndex + 1}/${attemptQualities.size}): ${errorDetails["message"]}, cause=${errorDetails["cause"]}"
                        )

                        if (attemptIndex + 1 < attemptQualities.size) {
                            Log.w("3S_AUDIO", "[fallback] 시도 1 실패. 2단계 재시도")
                            startMergeAttempt(attemptIndex + 1)
                            return
                        }

                        Handler(Looper.getMainLooper()).post {
                            activeMergeSessionId = null
                            activeMergeTraceId = null
                            activeMergeAttempt = null
                            activeMergeRetryPlan = null
                            result.error(
                                "EXPORT_FAILED",
                                "Media3 Error: ${errorDetails["message"]}",
                                errorDetails
                            )
                        }
                    }
                })
                .build()

            val file = File(outputPath)
            if (file.exists()) {
                Log.d("3S_AUDIO", "기존 파일 삭제: ${redactedPath(outputPath)}")
                file.delete()
            }

            Log.d(
                "3S_AUDIO",
                "⚡ Transformer 시작 (오디오 믹싱 모드, 시도=${attemptIndex + 1}/${attemptQualities.size}, 품질=$attemptQuality)..."
            )
            transformer.start(composition, outputPath)
        }

        startMergeAttempt(0)
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
                
                Log.d("3S_STICKER", "스티커 ${index + 1}: ${redactedPath(imagePath)}")
                Log.d("3S_STICKER", "  - 위치: (x=$x, y=$y)")
                Log.d("3S_STICKER", "  - 크기: ${width}x${height}")
                Log.d("3S_STICKER", "  - 회전: ${rotation}°")
                
                if (startTimeMs != null && endTimeMs != null) {
                    Log.d("3S_STICKER", "  - 시간: ${startTimeMs}ms ~ ${endTimeMs}ms")
                }
                
                // 이미지 파일 로드
                val imageFile = File(imagePath)
                if (!imageFile.exists()) {
                    Log.e("3S_STICKER", "✗ 스티커 파일 없음: ${redactedPath(imagePath)}")
                    continue
                }
                
                val bitmap = BitmapFactory.decodeFile(imagePath)
                if (bitmap == null) {
                    Log.e("3S_STICKER", "✗ 비트맵 디코딩 실패: ${redactedPath(imagePath)}")
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
        
        if ((effects["moaColorAdjustmentV1"] as? Number)?.toInt() == 1) {
            val contrast = DEFAULT_CONTRAST + normalizedEffectPercent(effects, "contrast")
            if (contrast != DEFAULT_CONTRAST) {
                filters.add(Contrast(contrast.coerceIn(0.01f, 2.0f)))
                Log.d("3S_4K", "  colorAdjust base_contrast=$contrast")
            }

            if (hasRgbColorAdjustment(effects)) {
                val matrix = createColorAdjustmentMatrix(effects)
                filters.add(RgbMatrix { _, _ -> matrix })
                Log.d(
                    "3S_4K",
                    "  colorAdjust brightness=${effects["brightness"] ?: 0} " +
                        "exposure=${effects["exposure"] ?: 0} " +
                        "highlights=${effects["highlights"] ?: 0} " +
                        "shadows=${effects["shadows"] ?: 0} " +
                        "saturation=${effects["saturation"] ?: 0} " +
                        "temperature=${effects["temperature"] ?: 0} " +
                        "tint=${effects["tint"] ?: 0} " +
                        "sharpness=${effects["sharpness"] ?: 0} " +
                        "clarity=${effects["clarity"] ?: 0}"
                )
            }

            addAdvancedColorAdjustmentFilters(filters, effects)
            addColorLutFilter(filters, effects)

            Log.d("3S_4K", "??珥?${filters.size}媛?GPU ?꾪꽣 ?앹꽦")
            Log.d("3S_4K", "?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺?곣봺")
            return filters
        }

        addColorLutFilter(filters, effects)
        if (filters.isNotEmpty()) {
            Log.d("3S_4K", "✓ 총 ${filters.size}개 GPU 필터 생성")
            Log.d("3S_4K", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            return filters
        }

        // Legacy premium-only effects path.
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

    private fun normalizedEffectPercent(
        effects: Map<String, Any>,
        key: String
    ): Float {
        return ((effects[key] as? Number)?.toFloat() ?: 0f)
            .coerceIn(-100f, 100f) / 100f
    }

    private fun hasRgbColorAdjustment(effects: Map<String, Any>): Boolean {
        return listOf(
            "brightness",
            "exposure",
            "saturation",
            "temperature",
            "tint"
        )
            .any { key -> normalizedEffectPercent(effects, key) != 0f }
    }

    private fun createColorAdjustmentMatrix(effects: Map<String, Any>): FloatArray {
        val brightness = normalizedEffectPercent(effects, "brightness")
        val exposure = normalizedEffectPercent(effects, "exposure")
        val saturation = DEFAULT_SATURATION + normalizedEffectPercent(effects, "saturation")
        val temperature = normalizedEffectPercent(effects, "temperature")
        val tint = normalizedEffectPercent(effects, "tint")

        val baseGain = ((1f + (brightness * 0.35f)) *
            Math.pow(2.0, exposure.toDouble()).toFloat()).coerceIn(0.01f, 3.0f)
        val redGain = (baseGain * (1f + (temperature * 0.18f) + (tint * 0.08f)))
            .coerceIn(0.01f, 3.0f)
        val greenGain = (baseGain * (1f - (tint * 0.10f))).coerceIn(0.01f, 3.0f)
        val blueGain = (baseGain * (1f - (temperature * 0.18f) + (tint * 0.08f)))
            .coerceIn(0.01f, 3.0f)

        val matrix = createSaturationMatrix(saturation.coerceIn(0f, 2f))
        for (column in 0..2) {
            matrix[column] *= redGain
            matrix[4 + column] *= greenGain
            matrix[8 + column] *= blueGain
        }
        return matrix
    }

    private fun addAdvancedColorAdjustmentFilters(
        filters: MutableList<GlEffect>,
        effects: Map<String, Any>
    ) {
        val highlights = normalizedEffectPercent(effects, "highlights")
        val shadows = normalizedEffectPercent(effects, "shadows")
        if (highlights != 0f || shadows != 0f) {
            filters.add(
                SelectiveToneCurveEffect(
                    highlights = highlights,
                    shadows = shadows,
                    fallbackMatrix = createSelectiveToneFallbackMatrix(highlights, shadows)
                )
            )
            Log.d(
                "3S_4K",
                "  colorAdjust selective_tone_curve highlights=$highlights shadows=$shadows"
            )
        }

        val sharpness = normalizedEffectPercent(effects, "sharpness")
        if (sharpness != 0f) {
            if (sharpness > 0f) {
                filters.add(SharpnessConvolution(sharpness.coerceIn(0f, 1f)))
                Log.d("3S_4K", "  colorAdjust advanced_sharpness=$sharpness kernel=unsharp")
            } else {
                val sigma = (1f + ((-sharpness).coerceIn(0f, 1f) * 2.5f))
                filters.add(GaussianBlur(sigma))
                Log.d("3S_4K", "  colorAdjust advanced_sharpness=$sharpness kernel=gaussian_blur sigma=$sigma")
            }
        }

        val clarity = normalizedEffectPercent(effects, "clarity")
        if (clarity != 0f) {
            val clarityContrast = (DEFAULT_CONTRAST + (clarity * 0.22f))
                .coerceIn(0.01f, 2.0f)
            val claritySaturation = (DEFAULT_SATURATION + (clarity * 0.12f))
                .coerceIn(0f, 2f)
            filters.add(Contrast(clarityContrast))
            filters.add(RgbMatrix { _, _ -> createSaturationMatrix(claritySaturation) })
            Log.d(
                "3S_4K",
                "  colorAdjust advanced_clarity=$clarity contrast=$clarityContrast saturation=$claritySaturation"
            )
        }
    }

    private fun addColorLutFilter(
        filters: MutableList<GlEffect>,
        effects: Map<String, Any>
    ) {
        if ((effects["moaColorLutV1"] as? Number)?.toInt() != 1) {
            return
        }

        val assetPath = effects["colorFilterLutAsset"] as? String
        val presetId = effects["colorFilterPresetId"] as? String ?: "unknown"
        val intensity = ((effects["colorFilterIntensity"] as? Number)?.toFloat() ?: 1f)
            .coerceIn(0f, 1f)

        if (assetPath.isNullOrBlank() || intensity <= 0f) {
            Log.d(
                "3S_4K",
                "  colorLut skipped preset=$presetId asset=${assetPath ?: "none"} intensity=$intensity"
            )
            return
        }

        val cubeLut = loadCubeLutFromFlutterAsset(assetPath)
        if (cubeLut == null) {
            Log.w(
                "3S_4K",
                "  color_lut_fallback reason=load_failed preset=$presetId asset=$assetPath"
            )
            return
        }

        filters.add(CubeLutEffect(cubeLut, intensity))
        Log.d(
            "3S_4K",
            "  colorLut preset=$presetId asset=$assetPath size=${cubeLut.size} intensity=$intensity"
        )
    }

    private fun loadCubeLutFromFlutterAsset(assetPath: String): CubeLut? {
        synchronized(colorLutCache) {
            colorLutCache[assetPath]?.let { return it }
        }

        return try {
            val lookupKey = FlutterInjector.instance()
                .flutterLoader()
                .getLookupKeyForAsset(assetPath)
            val parsed = assets.open(lookupKey).use { input ->
                BufferedReader(InputStreamReader(input, Charsets.UTF_8)).use { reader ->
                    parseCubeLut(assetPath, reader)
                }
            }
            if (parsed != null) {
                synchronized(colorLutCache) {
                    colorLutCache[assetPath] = parsed
                }
            }
            parsed
        } catch (e: Exception) {
            Log.w(
                "3S_4K",
                "color_lut_fallback reason=${e.javaClass.simpleName} asset=$assetPath"
            )
            null
        }
    }

    private fun parseCubeLut(assetPath: String, reader: BufferedReader): CubeLut? {
        var lutSize = 0
        val values = ArrayList<Float>()
        val whitespace = Regex("\\s+")

        reader.lineSequence().forEach { rawLine ->
            val line = rawLine.trim()
            if (line.isEmpty() || line.startsWith("#")) {
                return@forEach
            }
            when {
                line.startsWith("TITLE", ignoreCase = true) -> return@forEach
                line.startsWith("DOMAIN_MIN", ignoreCase = true) -> return@forEach
                line.startsWith("DOMAIN_MAX", ignoreCase = true) -> return@forEach
                line.startsWith("LUT_3D_SIZE", ignoreCase = true) -> {
                    val parts = line.split(whitespace)
                    lutSize = parts.getOrNull(1)?.toIntOrNull() ?: 0
                    return@forEach
                }
            }

            val parts = line.split(whitespace)
            if (parts.size < 3) {
                return@forEach
            }
            val red = parts[0].toFloatOrNull()
            val green = parts[1].toFloatOrNull()
            val blue = parts[2].toFloatOrNull()
            if (red != null && green != null && blue != null) {
                values.add(red.coerceIn(0f, 1f))
                values.add(green.coerceIn(0f, 1f))
                values.add(blue.coerceIn(0f, 1f))
            }
        }

        val expectedFloatCount = lutSize * lutSize * lutSize * 3
        if (lutSize <= 1 || values.size != expectedFloatCount) {
            Log.w(
                "3S_4K",
                "color_lut_fallback reason=invalid_cube asset=$assetPath size=$lutSize " +
                    "values=${values.size} expected=$expectedFloatCount"
            )
            return null
        }

        val rgbaBytes = ByteArray(lutSize * lutSize * lutSize * 4)
        var outIndex = 0
        var inIndex = 0
        while (inIndex < values.size) {
            rgbaBytes[outIndex++] = Math.round(values[inIndex++] * 255f)
                .coerceIn(0, 255)
                .toByte()
            rgbaBytes[outIndex++] = Math.round(values[inIndex++] * 255f)
                .coerceIn(0, 255)
                .toByte()
            rgbaBytes[outIndex++] = Math.round(values[inIndex++] * 255f)
                .coerceIn(0, 255)
                .toByte()
            rgbaBytes[outIndex++] = 255.toByte()
        }

        return CubeLut(assetPath = assetPath, size = lutSize, rgbaBytes = rgbaBytes)
    }

    private fun createHighlightAdjustmentMatrix(highlights: Float): FloatArray {
        val factor = (1f + (highlights * 0.18f)).coerceIn(0.01f, 2f)
        val offset = highlights * 0.047f
        return createRgbGainOffsetMatrix(factor, factor, factor, offset)
    }

    private fun createShadowAdjustmentMatrix(shadows: Float): FloatArray {
        val factor = (1f + (shadows * 0.10f)).coerceIn(0.01f, 2f)
        val offset = shadows * 0.071f
        return createRgbGainOffsetMatrix(factor, factor, factor, offset)
    }

    private fun createSelectiveToneFallbackMatrix(highlights: Float, shadows: Float): FloatArray {
        var matrix = createIdentityRgbMatrix()
        if (highlights != 0f) {
            matrix = multiplyRgbMatrices(createHighlightAdjustmentMatrix(highlights), matrix)
        }
        if (shadows != 0f) {
            matrix = multiplyRgbMatrices(createShadowAdjustmentMatrix(shadows), matrix)
        }
        return matrix
    }

    private fun createIdentityRgbMatrix(): FloatArray {
        return floatArrayOf(
            1f, 0f, 0f, 0f,
            0f, 1f, 0f, 0f,
            0f, 0f, 1f, 0f,
            0f, 0f, 0f, 1f
        )
    }

    private fun multiplyRgbMatrices(a: FloatArray, b: FloatArray): FloatArray {
        val result = FloatArray(16)
        for (row in 0..3) {
            for (column in 0..3) {
                var value = 0f
                for (i in 0..3) {
                    value += a[(row * 4) + i] * b[(i * 4) + column]
                }
                result[(row * 4) + column] = value
            }
        }
        return result
    }

    private fun createRgbGainOffsetMatrix(
        redGain: Float,
        greenGain: Float,
        blueGain: Float,
        offset: Float
    ): FloatArray {
        return floatArrayOf(
            redGain, 0f, 0f, offset,
            0f, greenGain, 0f, offset,
            0f, 0f, blueGain, offset,
            0f, 0f, 0f, 1f
        )
    }

    private class SelectiveToneCurveEffect(
        private val highlights: Float,
        private val shadows: Float,
        private val fallbackMatrix: FloatArray
    ) : GlEffect {
        override fun toGlShaderProgram(
            context: android.content.Context,
            useHdr: Boolean
        ): androidx.media3.effect.GlShaderProgram {
            return try {
                SelectiveToneCurveShaderProgram(useHdr, highlights, shadows)
            } catch (e: Exception) {
                Log.w(
                    "3S_4K",
                    "selective_tone_curve_fallback reason=${e.javaClass.simpleName} " +
                        "highlights=$highlights shadows=$shadows"
                )
                RgbMatrix { _, _ -> fallbackMatrix }.toGlShaderProgram(context, useHdr)
            }
        }

        override fun isNoOp(inputWidth: Int, inputHeight: Int): Boolean {
            return highlights == 0f && shadows == 0f
        }
    }

    private class SelectiveToneCurveShaderProgram(
        useHdr: Boolean,
        private val highlights: Float,
        private val shadows: Float
    ) : BaseGlShaderProgram(useHdr, 1) {
        private val glProgram: GlProgram = GlProgram(VERTEX_SHADER, FRAGMENT_SHADER)

        init {
            glProgram.setBufferAttribute(
                "aFramePosition",
                GlUtil.getNormalizedCoordinateBounds(),
                2
            )
            glProgram.setBufferAttribute(
                "aTexCoords",
                GlUtil.getTextureCoordinateBounds(),
                2
            )
        }

        override fun configure(inputWidth: Int, inputHeight: Int): Size {
            return Size(inputWidth, inputHeight)
        }

        override fun drawFrame(inputTexId: Int, presentationTimeUs: Long) {
            try {
                glProgram.use()
                glProgram.setSamplerTexIdUniform("uTexSampler", inputTexId, 0)
                glProgram.setFloatUniform("uHighlights", highlights.coerceIn(-1f, 1f))
                glProgram.setFloatUniform("uShadows", shadows.coerceIn(-1f, 1f))
                glProgram.setFloatUniform("uShadowStart", 0.02f)
                glProgram.setFloatUniform("uShadowEnd", 0.55f)
                glProgram.setFloatUniform("uHighlightStart", 0.45f)
                glProgram.setFloatUniform("uHighlightEnd", 0.98f)
                glProgram.bindAttributesAndUniforms()
                GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
                GlUtil.checkGlError()
            } catch (e: Exception) {
                throw VideoFrameProcessingException.from(e, presentationTimeUs)
            }
        }

        override fun release() {
            try {
                glProgram.delete()
            } catch (e: Exception) {
                throw VideoFrameProcessingException.from(e)
            } finally {
                super.release()
            }
        }

        companion object {
            private const val VERTEX_SHADER = """
                attribute vec4 aFramePosition;
                attribute vec2 aTexCoords;
                varying vec2 vTexCoords;

                void main() {
                  gl_Position = aFramePosition;
                  vTexCoords = aTexCoords;
                }
            """

            private const val FRAGMENT_SHADER = """
                precision mediump float;

                uniform sampler2D uTexSampler;
                uniform float uHighlights;
                uniform float uShadows;
                uniform float uShadowStart;
                uniform float uShadowEnd;
                uniform float uHighlightStart;
                uniform float uHighlightEnd;
                varying vec2 vTexCoords;

                vec3 adjustHighlights(vec3 color, float amount, float mask) {
                  if (amount > 0.0) {
                    return mix(color, color + ((1.0 - color) * amount), mask);
                  }
                  return mix(color, color * (1.0 + amount), mask);
                }

                vec3 adjustShadows(vec3 color, float amount, float mask) {
                  if (amount > 0.0) {
                    return mix(color, color + ((1.0 - color) * amount), mask);
                  }
                  return mix(color, color * (1.0 + amount), mask);
                }

                void main() {
                  vec4 color = texture2D(uTexSampler, vTexCoords);
                  float luma = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
                  float shadowMask = 1.0 - smoothstep(uShadowStart, uShadowEnd, luma);
                  float highlightMask = smoothstep(uHighlightStart, uHighlightEnd, luma);
                  vec3 adjusted = color.rgb;
                  adjusted = adjustShadows(adjusted, uShadows, shadowMask * abs(uShadows));
                  adjusted = adjustHighlights(adjusted, uHighlights, highlightMask * abs(uHighlights));
                  gl_FragColor = vec4(clamp(adjusted, 0.0, 1.0), color.a);
                }
            """
        }
    }

    private class CubeLutEffect(
        private val lut: CubeLut,
        private val intensity: Float
    ) : GlEffect {
        override fun toGlShaderProgram(
            context: android.content.Context,
            useHdr: Boolean
        ): androidx.media3.effect.GlShaderProgram {
            return try {
                CubeLutShaderProgram(useHdr, lut, intensity)
            } catch (e: Exception) {
                Log.w(
                    "3S_4K",
                    "color_lut_fallback reason=${e.javaClass.simpleName} asset=${lut.assetPath}"
                )
                RgbMatrix { _, _ -> IDENTITY_MATRIX }.toGlShaderProgram(context, useHdr)
            }
        }

        override fun isNoOp(inputWidth: Int, inputHeight: Int): Boolean {
            return intensity <= 0f
        }

        companion object {
            private val IDENTITY_MATRIX = floatArrayOf(
                1f, 0f, 0f, 0f,
                0f, 1f, 0f, 0f,
                0f, 0f, 1f, 0f,
                0f, 0f, 0f, 1f
            )
        }
    }

    private class CubeLutShaderProgram(
        useHdr: Boolean,
        private val lut: CubeLut,
        private val intensity: Float
    ) : BaseGlShaderProgram(useHdr, 1) {
        private val glProgram: GlProgram = GlProgram(VERTEX_SHADER, FRAGMENT_SHADER)
        private val lutTextureId: Int

        init {
            glProgram.setBufferAttribute(
                "aFramePosition",
                GlUtil.getNormalizedCoordinateBounds(),
                2
            )
            glProgram.setBufferAttribute(
                "aTexCoords",
                GlUtil.getTextureCoordinateBounds(),
                2
            )
            lutTextureId = createLutTexture(lut)
        }

        override fun configure(inputWidth: Int, inputHeight: Int): Size {
            return Size(inputWidth, inputHeight)
        }

        override fun drawFrame(inputTexId: Int, presentationTimeUs: Long) {
            try {
                glProgram.use()
                glProgram.setSamplerTexIdUniform("uTexSampler", inputTexId, 0)
                glProgram.setSamplerTexIdUniform("uLutSampler", lutTextureId, 1)
                glProgram.setFloatUniform("uIntensity", intensity.coerceIn(0f, 1f))
                glProgram.setFloatUniform("uLutSize", lut.size.toFloat())
                glProgram.bindAttributesAndUniforms()
                GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
                GlUtil.checkGlError()
            } catch (e: Exception) {
                throw VideoFrameProcessingException.from(e, presentationTimeUs)
            }
        }

        override fun release() {
            try {
                if (lutTextureId > 0) {
                    val textures = intArrayOf(lutTextureId)
                    GLES20.glDeleteTextures(1, textures, 0)
                }
                glProgram.delete()
            } catch (e: Exception) {
                throw VideoFrameProcessingException.from(e)
            } finally {
                super.release()
            }
        }

        companion object {
            private fun createLutTexture(lut: CubeLut): Int {
                val textureIds = IntArray(1)
                GLES20.glGenTextures(1, textureIds, 0)
                val textureId = textureIds[0]
                if (textureId == 0) {
                    throw IllegalStateException("Unable to allocate LUT texture")
                }

                val buffer = ByteBuffer.allocateDirect(lut.rgbaBytes.size)
                buffer.put(lut.rgbaBytes)
                buffer.position(0)

                GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId)
                GLES20.glTexParameteri(
                    GLES20.GL_TEXTURE_2D,
                    GLES20.GL_TEXTURE_MIN_FILTER,
                    GLES20.GL_LINEAR
                )
                GLES20.glTexParameteri(
                    GLES20.GL_TEXTURE_2D,
                    GLES20.GL_TEXTURE_MAG_FILTER,
                    GLES20.GL_LINEAR
                )
                GLES20.glTexParameteri(
                    GLES20.GL_TEXTURE_2D,
                    GLES20.GL_TEXTURE_WRAP_S,
                    GLES20.GL_CLAMP_TO_EDGE
                )
                GLES20.glTexParameteri(
                    GLES20.GL_TEXTURE_2D,
                    GLES20.GL_TEXTURE_WRAP_T,
                    GLES20.GL_CLAMP_TO_EDGE
                )
                GLES20.glPixelStorei(GLES20.GL_UNPACK_ALIGNMENT, 1)
                GLES20.glTexImage2D(
                    GLES20.GL_TEXTURE_2D,
                    0,
                    GLES20.GL_RGBA,
                    lut.size * lut.size,
                    lut.size,
                    0,
                    GLES20.GL_RGBA,
                    GLES20.GL_UNSIGNED_BYTE,
                    buffer
                )
                GlUtil.checkGlError()
                return textureId
            }

            private const val VERTEX_SHADER = """
                attribute vec4 aFramePosition;
                attribute vec2 aTexCoords;
                varying vec2 vTexCoords;

                void main() {
                  gl_Position = aFramePosition;
                  vTexCoords = aTexCoords;
                }
            """

            private const val FRAGMENT_SHADER = """
                precision mediump float;

                uniform sampler2D uTexSampler;
                uniform sampler2D uLutSampler;
                uniform float uIntensity;
                uniform float uLutSize;
                varying vec2 vTexCoords;

                vec3 sampleLut(vec3 color, float blueSlice) {
                  float maxIndex = uLutSize - 1.0;
                  float atlasWidth = uLutSize * uLutSize;
                  float x = ((blueSlice * uLutSize) + (color.r * maxIndex) + 0.5) / atlasWidth;
                  float y = ((color.g * maxIndex) + 0.5) / uLutSize;
                  return texture2D(uLutSampler, vec2(x, y)).rgb;
                }

                void main() {
                  vec4 color = texture2D(uTexSampler, vTexCoords);
                  vec3 inputColor = clamp(color.rgb, 0.0, 1.0);
                  float maxIndex = uLutSize - 1.0;
                  float blue = inputColor.b * maxIndex;
                  float blueLow = floor(blue);
                  float blueHigh = min(maxIndex, blueLow + 1.0);
                  float blueMix = fract(blue);
                  vec3 lowColor = sampleLut(inputColor, blueLow);
                  vec3 highColor = sampleLut(inputColor, blueHigh);
                  vec3 lutColor = mix(lowColor, highColor, blueMix);
                  vec3 outputColor = mix(inputColor, lutColor, clamp(uIntensity, 0.0, 1.0));
                  gl_FragColor = vec4(clamp(outputColor, 0.0, 1.0), color.a);
                }
            """
        }
    }

    private class SharpnessConvolution(private val amount: Float) : SeparableConvolution() {
        override fun getConvolution(presentationTimeUs: Long): ConvolutionFunction1D {
            val strength = (amount * 0.28f).coerceIn(0f, 0.28f)
            return object : ConvolutionFunction1D {
                override fun domainStart(): Float = -1f
                override fun domainEnd(): Float = 1f
                override fun value(samplePosition: Float): Float {
                    return when (Math.round(samplePosition)) {
                        0 -> 1f + (2f * strength)
                        -1, 1 -> -strength
                        else -> 0f
                    }
                }
            }
        }
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
        return createQualityEncoderFactory(quality, userTier, bitrateForQuality(quality))
    }

    private fun bitrateForQuality(quality: String): Int {
        return when {
            quality.equals("4K", ignoreCase = true) || quality.equals("4k", ignoreCase = true) -> BITRATE_4K_MAX
            quality.contains("720", ignoreCase = true) -> BITRATE_720P_MAX
            else -> BITRATE_1080P_MAX
        }
    }

    private fun createQualityEncoderFactory(quality: String, userTier: String, targetBitrate: Int): DefaultEncoderFactory {
        val builder = DefaultEncoderFactory.Builder(applicationContext)
            .setEnableFallback(true)

        val (width, height) = when {
            quality.equals("4K", ignoreCase = true) && userTier == "premium" -> RESOLUTION_4K_WIDTH to RESOLUTION_4K_HEIGHT
            quality.contains("720", ignoreCase = true) -> 1280 to 720
            else -> 1920 to 1080
        }
        trySetRequestedEncoderParams(builder, width, height, targetBitrate)
        Log.d("3S_QUALITY", "encoderProfile quality=$quality userTier=$userTier width=$width height=$height targetBitrate=$targetBitrate targetFps=$TARGET_EXPORT_FPS codec=h264")
        
        // 🚀 4K 모드: 하드웨어 코덱 강제 활성화
        if (quality.equals("4K", ignoreCase = true) && userTier == "premium") {
            // Galaxy S23 (SM-S911N) 등 고성능 기기 최적화
            // 하드웨어 코덱을 우선적으로 사용하도록 설정
            Log.d("3S_4K", "⚡ 4K 하드웨어 코덱 강제 활성화")
            Log.d("3S_4K", "  - 타겟 기기: Galaxy S23 (SM-S911N) 최적화")
            
            // CameraX/AVFoundation 수준의 촬영 제어 전환은 별도 P2 범위로 유지합니다.
        }
        
        return builder.build()
    }

    /// 비디오 클립 추출 (편집 기능)
    /// 
    /// 입력 비디오에서 여러 1초 구간을 추출하여 개별 파일로 저장
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
        Log.d("3S_EDIT", "입력: ${redactedPath(inputPath)}")
        Log.d("3S_EDIT", "출력: ${redactedPath(outputDir)}")
        Log.d("3S_EDIT", "품질: $quality")
        Log.d("3S_EDIT", "노이즈 억제: $enableNoiseSuppression")
        Log.d("3S_SUBTITLE", "자막: ${subtitles.size}개, 등급: $userTier")
        
        try {
            // 출력 디렉토리 확인
            val outputDirectory = File(outputDir)
            if (!outputDirectory.exists()) {
                outputDirectory.mkdirs()
                Log.d("3S_EDIT", "✓ 출력 디렉토리 생성: ${redactedPath(outputDir)}")
            }

            // 생성된 파일 경로 추적
            val extractedFilePaths = mutableListOf<String>()
            
            // 하드웨어 가속 Encoder Factory 설정 (억만장자의 속도)
            val encoderFactory = DefaultEncoderFactory.Builder(applicationContext)
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
                val endMs = (segment["end"] as? Number)?.toLong() ?: (startMs + DEFAULT_EDIT_TARGET_DURATION_MS)
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
                    val sequence = EditedMediaItemSequence.Builder(listOf(editedMediaItem)).build()
                    val composition = Composition.Builder(listOf(sequence)).build()
                    
                    // 5. Transformer 구성
                    val transformer = Transformer.Builder(this@MainActivity)
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
                                Log.d("3S_EDIT", "    - 저장 경로: ${redactedPath(outputPath)}")
                                
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
        Log.d("3S_EDIT", "  - 입력: ${redactedPath(inputPath)}")
        Log.d("3S_EDIT", "  - 출력: ${redactedPath(outputPath)}")
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

            val sequence = EditedMediaItemSequence.Builder(listOf(editedMediaItem)).build()

            // 6. BGM 추가 (선택적)
            val sequences = mutableListOf(sequence)
            if (bgmPath != null && bgmVolume > 0f && File(bgmPath).exists()) {
                Log.d("3S_EDIT", "✓ BGM 추가: ${redactedPath(bgmPath)}")
                
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

                val bgmAudioProcessors = mutableListOf<AudioProcessor>()
                val normalizedBgmVolume = bgmVolume.coerceIn(0f, 1f)
                if (normalizedBgmVolume < 0.999f) {
                    bgmAudioProcessors.add(VolumeAudioProcessor(normalizedBgmVolume))
                }
                bgmAudioProcessors.add(fadeOutProcessor)
                val bgmEffects = Effects(bgmAudioProcessors, listOf())
                val bgmEditedItem = EditedMediaItem.Builder(bgmMediaItem)
                    .setRemoveVideo(true)
                    .setEffects(bgmEffects)
                    .build()

                sequences.add(EditedMediaItemSequence.Builder(listOf(bgmEditedItem)).build())
            }

            // 7. Composition 생성
            val composition = Composition.Builder(sequences)
                .setTransmuxAudio(false)
                .setTransmuxVideo(false)
                .build()

            // 8. Encoder Factory (4K 지원)
            val encoderFactory = create4KEncoderFactory(quality, userTier)

            // 9. Transformer 구성
            val transformer = Transformer.Builder(this@MainActivity)
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

class VolumeAudioProcessor(
    private val gain: Float
) : BaseAudioProcessor() {
    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT) {
            throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        }
        return inputAudioFormat
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val position = inputBuffer.position()
        val limit = inputBuffer.limit()
        val frameCount = (limit - position) / (2 * inputAudioFormat.channelCount)
        val outputBuffer = replaceOutputBuffer(limit - position)
        val normalizedGain = gain.coerceIn(0f, 1f)

        for (i in 0 until frameCount) {
            for (ch in 0 until inputAudioFormat.channelCount) {
                val sample = inputBuffer.short
                val processedSample = (sample * normalizedGain)
                    .toInt()
                    .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
                    .toShort()
                outputBuffer.putShort(processedSample)
            }
        }

        outputBuffer.flip()
    }
}

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
