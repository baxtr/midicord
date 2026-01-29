package com.tunoodle.app

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val shareChannelName = "com.midicord/share"
    private val videoChannelName = "com.midicord/video"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Share channel for file sharing
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "shareFile") {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("INVALID_ARGS", "Path required", null)
                        return@setMethodCallHandler
                    }
                    shareFile(path, result)
                } else {
                    result.notImplemented()
                }
            }

        // Video channel for video export
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, videoChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "createVideo") {
                    val framesData = call.argument<List<ByteArray>>("frames")
                    val outputPath = call.argument<String>("outputPath")
                    val fps = call.argument<Int>("fps")
                    val width = call.argument<Int>("width")
                    val height = call.argument<Int>("height")
                    val audioPath = call.argument<String>("audioPath")

                    if (framesData == null || outputPath == null || fps == null || width == null || height == null) {
                        result.error("INVALID_ARGS", "Missing required arguments", null)
                        return@setMethodCallHandler
                    }

                    thread {
                        createVideo(framesData, outputPath, fps, width, height, audioPath) { success, error ->
                            Handler(Looper.getMainLooper()).post {
                                if (success) {
                                    result.success(true)
                                } else {
                                    result.error("VIDEO_ERROR", error ?: "Unknown error", null)
                                }
                            }
                        }
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun shareFile(path: String, result: MethodChannel.Result) {
        val file = File(path)
        if (!file.exists()) {
            result.error("FILE_NOT_FOUND", "File does not exist", null)
            return
        }

        try {
            val uri = FileProvider.getUriForFile(
                this,
                "${applicationContext.packageName}.fileprovider",
                file
            )

            val mimeType = when {
                path.endsWith(".mp4") -> "video/mp4"
                path.endsWith(".mid") || path.endsWith(".midi") -> "audio/midi"
                path.endsWith(".wav") -> "audio/wav"
                path.endsWith(".m4a") -> "audio/mp4"
                else -> "*/*"
            }

            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = mimeType
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }

            startActivity(Intent.createChooser(shareIntent, "Share file"))
            result.success(true)
        } catch (e: Exception) {
            result.error("SHARE_ERROR", e.message, null)
        }
    }

    private fun createVideo(
        framesData: List<ByteArray>,
        outputPath: String,
        fps: Int,
        width: Int,
        height: Int,
        audioPath: String?,
        completion: (Boolean, String?) -> Unit
    ) {
        if (framesData.isEmpty()) {
            completion(false, "No frames provided")
            return
        }

        try {
            // Delete existing file if present
            val outputFile = File(outputPath)
            if (outputFile.exists()) {
                outputFile.delete()
            }

            // Create temp file for video without audio
            val tempVideoPath = if (audioPath != null) {
                outputPath.replace(".mp4", "_temp.mp4")
            } else {
                outputPath
            }
            val tempFile = File(tempVideoPath)
            if (tempFile.exists()) {
                tempFile.delete()
            }

            // Configure MediaCodec for H.264 encoding
            val mimeType = MediaFormat.MIMETYPE_VIDEO_AVC
            val format = MediaFormat.createVideoFormat(mimeType, width, height).apply {
                setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
                setInteger(MediaFormat.KEY_BIT_RATE, 4_000_000) // 4 Mbps
                setInteger(MediaFormat.KEY_FRAME_RATE, fps)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            }

            val encoder = MediaCodec.createEncoderByType(mimeType)
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            encoder.start()

            val muxer = MediaMuxer(tempVideoPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            var videoTrackIndex = -1
            var muxerStarted = false

            val frameDurationUs = 1_000_000L / fps
            var presentationTimeUs = 0L
            var frameIndex = 0

            val bufferInfo = MediaCodec.BufferInfo()

            // Process all frames
            while (frameIndex < framesData.size || !isEncoderDrained(encoder, bufferInfo)) {
                // Feed input if available
                if (frameIndex < framesData.size) {
                    val inputBufferIndex = encoder.dequeueInputBuffer(10_000)
                    if (inputBufferIndex >= 0) {
                        val inputBuffer = encoder.getInputBuffer(inputBufferIndex)
                        if (inputBuffer != null) {
                            val bitmap = BitmapFactory.decodeByteArray(framesData[frameIndex], 0, framesData[frameIndex].size)
                            if (bitmap != null) {
                                val scaledBitmap = Bitmap.createScaledBitmap(bitmap, width, height, true)
                                val yuvData = bitmapToYuv420(scaledBitmap)
                                inputBuffer.clear()
                                inputBuffer.put(yuvData)
                                encoder.queueInputBuffer(inputBufferIndex, 0, yuvData.size, presentationTimeUs, 0)
                                presentationTimeUs += frameDurationUs
                                frameIndex++
                                if (bitmap != scaledBitmap) {
                                    bitmap.recycle()
                                }
                                scaledBitmap.recycle()
                            }
                        }
                    }
                } else {
                    // Signal end of input
                    val inputBufferIndex = encoder.dequeueInputBuffer(10_000)
                    if (inputBufferIndex >= 0) {
                        encoder.queueInputBuffer(inputBufferIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                    }
                }

                // Drain output
                var outputBufferIndex = encoder.dequeueOutputBuffer(bufferInfo, 10_000)
                while (outputBufferIndex >= 0) {
                    val outputBuffer = encoder.getOutputBuffer(outputBufferIndex)
                    if (outputBuffer != null && bufferInfo.size > 0) {
                        if (!muxerStarted) {
                            val newFormat = encoder.outputFormat
                            videoTrackIndex = muxer.addTrack(newFormat)
                            muxer.start()
                            muxerStarted = true
                        }
                        outputBuffer.position(bufferInfo.offset)
                        outputBuffer.limit(bufferInfo.offset + bufferInfo.size)
                        muxer.writeSampleData(videoTrackIndex, outputBuffer, bufferInfo)
                    }
                    encoder.releaseOutputBuffer(outputBufferIndex, false)

                    if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        break
                    }
                    outputBufferIndex = encoder.dequeueOutputBuffer(bufferInfo, 0)
                }
            }

            encoder.stop()
            encoder.release()
            if (muxerStarted) {
                muxer.stop()
            }
            muxer.release()

            // Merge with audio if provided
            if (audioPath != null && File(audioPath).exists()) {
                mergeVideoWithAudio(tempVideoPath, audioPath, outputPath)
                File(tempVideoPath).delete()
            }

            completion(true, null)
        } catch (e: Exception) {
            completion(false, e.message)
        }
    }

    private fun isEncoderDrained(encoder: MediaCodec, bufferInfo: MediaCodec.BufferInfo): Boolean {
        val outputBufferIndex = encoder.dequeueOutputBuffer(bufferInfo, 0)
        if (outputBufferIndex >= 0) {
            encoder.releaseOutputBuffer(outputBufferIndex, false)
            return bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
        }
        return false
    }

    private fun bitmapToYuv420(bitmap: Bitmap): ByteArray {
        val width = bitmap.width
        val height = bitmap.height
        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)

        val yuvSize = width * height * 3 / 2
        val yuv = ByteArray(yuvSize)

        var yIndex = 0
        var uvIndex = width * height

        for (j in 0 until height) {
            for (i in 0 until width) {
                val pixel = pixels[j * width + i]
                val r = (pixel shr 16) and 0xFF
                val g = (pixel shr 8) and 0xFF
                val b = pixel and 0xFF

                // Y plane
                val y = ((66 * r + 129 * g + 25 * b + 128) shr 8) + 16
                yuv[yIndex++] = y.coerceIn(0, 255).toByte()

                // UV planes (subsampled 2x2)
                if (j % 2 == 0 && i % 2 == 0 && uvIndex < yuvSize - 1) {
                    val u = ((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128
                    val v = ((112 * r - 94 * g - 18 * b + 128) shr 8) + 128
                    yuv[uvIndex++] = u.coerceIn(0, 255).toByte()
                    yuv[uvIndex++] = v.coerceIn(0, 255).toByte()
                }
            }
        }

        return yuv
    }

    private fun mergeVideoWithAudio(videoPath: String, audioPath: String, outputPath: String) {
        try {
            val videoExtractor = android.media.MediaExtractor()
            videoExtractor.setDataSource(videoPath)

            val audioExtractor = android.media.MediaExtractor()
            audioExtractor.setDataSource(audioPath)

            val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

            // Find and add video track
            var videoTrackIndex = -1
            var videoInputTrack = -1
            for (i in 0 until videoExtractor.trackCount) {
                val format = videoExtractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME)
                if (mime?.startsWith("video/") == true) {
                    videoExtractor.selectTrack(i)
                    videoInputTrack = i
                    videoTrackIndex = muxer.addTrack(format)
                    break
                }
            }

            // Find and add audio track
            var audioTrackIndex = -1
            var audioInputTrack = -1
            for (i in 0 until audioExtractor.trackCount) {
                val format = audioExtractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME)
                if (mime?.startsWith("audio/") == true) {
                    audioExtractor.selectTrack(i)
                    audioInputTrack = i
                    audioTrackIndex = muxer.addTrack(format)
                    break
                }
            }

            muxer.start()

            val bufferSize = 1024 * 1024
            val buffer = ByteBuffer.allocate(bufferSize)
            val bufferInfo = MediaCodec.BufferInfo()

            // Write video samples
            if (videoTrackIndex >= 0) {
                while (true) {
                    bufferInfo.offset = 0
                    bufferInfo.size = videoExtractor.readSampleData(buffer, 0)
                    if (bufferInfo.size < 0) break
                    bufferInfo.presentationTimeUs = videoExtractor.sampleTime
                    bufferInfo.flags = videoExtractor.sampleFlags
                    muxer.writeSampleData(videoTrackIndex, buffer, bufferInfo)
                    videoExtractor.advance()
                }
            }

            // Write audio samples
            if (audioTrackIndex >= 0) {
                while (true) {
                    bufferInfo.offset = 0
                    bufferInfo.size = audioExtractor.readSampleData(buffer, 0)
                    if (bufferInfo.size < 0) break
                    bufferInfo.presentationTimeUs = audioExtractor.sampleTime
                    bufferInfo.flags = audioExtractor.sampleFlags
                    muxer.writeSampleData(audioTrackIndex, buffer, bufferInfo)
                    audioExtractor.advance()
                }
            }

            muxer.stop()
            muxer.release()
            videoExtractor.release()
            audioExtractor.release()
        } catch (e: Exception) {
            // If merge fails, copy video-only file
            File(videoPath).copyTo(File(outputPath), overwrite = true)
        }
    }
}
