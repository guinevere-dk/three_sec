package com.example.three_sec_vlog

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.vlog.app/video_merger"
    private val TAG = "VideoMerger"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "mergeVideos" -> {
                    try {
                        val inputPaths = call.argument<List<String>>("inputPaths")
                        val outputPath = call.argument<String>("outputPath")
                        
                        if (inputPaths == null || outputPath == null) {
                            result.error("INVALID_ARGS", "Input paths or output path is null", null)
                            return@setMethodCallHandler
                        }
                        
                        val mergedPath = mergeVideos(inputPaths, outputPath)
                        result.success(mergedPath)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error merging videos", e)
                        // 에러 메시지에 CLIP_ERROR_INDEX_ 가 포함되어 있으면 그대로 전달
                        result.error("MERGE_ERROR", e.message, e.stackTraceToString())
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun mergeVideos(inputPaths: List<String>, outputPath: String): String {
        val outputFile = File(outputPath)
        outputFile.parentFile?.mkdirs()
        
        if (outputFile.exists()) outputFile.delete()

        var muxer: MediaMuxer? = null
        val extractors = mutableListOf<MediaExtractor>()
        
        try {
            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer.setOrientationHint(90) // 세로 모드 고정
            
            var videoTrackIndex = -1
            var audioTrackIndex = -1
            var currentPositionUs = 0L
            
            // 트랙 포맷 설정을 위한 첫 번째 유효한 추출기 준비
            val firstExtractor = MediaExtractor()
            try {
                firstExtractor.setDataSource(inputPaths[0])
            } catch (e: Exception) {
                throw Exception("CLIP_ERROR_INDEX_0")
            }
            
            for (i in 0 until firstExtractor.trackCount) {
                val format = firstExtractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("video/") && videoTrackIndex == -1) videoTrackIndex = muxer.addTrack(format)
                if (mime.startsWith("audio/") && audioTrackIndex == -1) audioTrackIndex = muxer.addTrack(format)
            }
            firstExtractor.release()
            
            muxer.start()
            
            // 각 파일 순차 병합
            for ((index, inputPath) in inputPaths.withIndex()) {
                val extractor = MediaExtractor()
                try {
                    extractor.setDataSource(inputPath)
                } catch (e: Exception) {
                    throw Exception("CLIP_ERROR_INDEX_$index")
                }
                
                // 비디오 트랙 복사
                if (videoTrackIndex >= 0) {
                    val videoIdx = findTrackIndex(extractor, "video/")
                    if (videoIdx >= 0) {
                        extractor.selectTrack(videoIdx)
                        copyTrack(extractor, muxer, videoTrackIndex, currentPositionUs)
                        extractor.unselectTrack(videoIdx)
                    }
                }
                
                // 오디오 트랙 복사
                if (audioTrackIndex >= 0) {
                    val audioIdx = findTrackIndex(extractor, "audio/")
                    if (audioIdx >= 0) {
                        extractor.selectTrack(audioIdx)
                        extractor.seekTo(0, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
                        copyTrack(extractor, muxer, audioTrackIndex, currentPositionUs)
                        extractor.unselectTrack(audioIdx)
                    }
                }
                
                currentPositionUs += getVideoDuration(inputPath)
                extractor.release()
            }
            
            muxer.stop()
            muxer.release()
            return outputPath
            
        } catch (e: Exception) {
            muxer?.release()
            throw e
        }
    }
    
    private fun findTrackIndex(extractor: MediaExtractor, mimePrefix: String): Int {
        for (i in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(i)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith(mimePrefix)) return i
        }
        return -1
    }
    
    private fun copyTrack(extractor: MediaExtractor, muxer: MediaMuxer, trackIndex: Int, startTimeUs: Long) {
        val buffer = ByteBuffer.allocate(1024 * 1024)
        val bufferInfo = MediaCodec.BufferInfo()
        extractor.seekTo(0, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
        while (true) {
            val sampleSize = extractor.readSampleData(buffer, 0)
            if (sampleSize < 0) break
            bufferInfo.offset = 0
            bufferInfo.size = sampleSize
            bufferInfo.presentationTimeUs = startTimeUs + extractor.sampleTime
            bufferInfo.flags = extractor.sampleFlags
            muxer.writeSampleData(trackIndex, buffer, bufferInfo)
            extractor.advance()
        }
    }
    
    private fun getVideoDuration(path: String): Long {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
            val videoIdx = findTrackIndex(extractor, "video/")
            return if (videoIdx >= 0) extractor.getTrackFormat(videoIdx).getLong(MediaFormat.KEY_DURATION) else 0L
        } catch (e: Exception) { return 0L } finally { extractor.release() }
    }
}