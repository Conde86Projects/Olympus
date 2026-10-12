package com.example.player

import android.Manifest
import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import java.io.ByteArrayOutputStream
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "player/media_permission"
    private val permRequestCode = 4411
    private var pendingResult: MethodChannel.Result? = null

    private fun mediaPermission(): String =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
            Manifest.permission.READ_MEDIA_VIDEO
        else
            Manifest.permission.READ_EXTERNAL_STORAGE

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(currentStatus())
                    "request" -> requestAccess(result)
                    else -> result.notImplemented()
                }
            }
        setupThumbnails(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "player/tv_info")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTv" -> result.success(isTvDevice())
                    else -> result.notImplemented()
                }
            }
    }

    private fun setupThumbnails(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "player/thumbnails")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "frame" -> extractFrame(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun extractFrame(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val positionMs = call.argument<Number>("positionMs")?.toLong() ?: 3000L
        val maxWidth = call.argument<Number>("maxWidth")?.toInt() ?: 320
        if (path.isNullOrEmpty()) {
            result.success(null)
            return
        }
        var retriever: MediaMetadataRetriever? = null
        try {
            retriever = MediaMetadataRetriever()
            retriever.setDataSource(path)
            val frame = retriever.getFrameAtTime(
                positionMs * 1000,
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC
            ) ?: retriever.getFrameAtTime(0)
            if (frame == null) {
                result.success(null)
                return
            }
            val scaled = if (frame.width > maxWidth) {
                val h = (frame.height * maxWidth / frame.width.toFloat())
                    .toInt().coerceAtLeast(1)
                Bitmap.createScaledBitmap(frame, maxWidth, h, true)
            } else {
                frame
            }
            val out = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.JPEG, 85, out)
            if (scaled !== frame) frame.recycle()
            scaled.recycle()
            result.success(out.toByteArray())
        } catch (_: Exception) {
            // Falha vira ausência: o card mostra o placeholder.
            result.success(null)
        } finally {
            try {
                retriever?.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun isTvDevice(): Boolean {
        if (packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)) {
            return true
        }
        val uiMode = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        return uiMode?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
    }

    private fun currentStatus(): String =
        if (ContextCompat.checkSelfPermission(this, mediaPermission()) ==
            PackageManager.PERMISSION_GRANTED
        ) "granted" else "denied"

    private fun requestAccess(result: MethodChannel.Result) {
        if (currentStatus() == "granted") {
            result.success("granted")
            return
        }
        if (pendingResult != null) {
            result.error("BUSY", "Permission request already in progress", null)
            return
        }
        pendingResult = result
        ActivityCompat.requestPermissions(this, arrayOf(mediaPermission()), permRequestCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permRequestCode) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingResult?.success(if (granted) "granted" else "denied")
        pendingResult = null
    }
}
