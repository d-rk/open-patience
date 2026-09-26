package io.github.d_rk.openpatience

import android.content.Context
import android.content.res.Configuration
import android.view.OrientationEventListener
import android.view.Surface
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "open_patience/physical_orientation",
        ).setStreamHandler(PhysicalOrientationHandler(this))
    }
}

/**
 * Streams how the device is physically held — "portrait", "landscape", or
 * null when unknown (lying flat, or tilted in between) — independent of the
 * display rotation and of the system auto-rotate setting. Used by the Dart
 * `OrientationKeeper` to tell when the player really turned the device.
 * The sensor only runs while Dart listens.
 */
private class PhysicalOrientationHandler(private val context: Context) :
    EventChannel.StreamHandler {
    private var listener: OrientationEventListener? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        val naturalIsPortrait = naturalOrientationIsPortrait()
        var last: String? = null
        var sentAny = false
        val l = object : OrientationEventListener(context) {
            override fun onOrientationChanged(degrees: Int) {
                val reading = classify(degrees, naturalIsPortrait)
                if (sentAny && reading == last) return
                sentAny = true
                last = reading
                events.success(reading)
            }
        }
        if (!l.canDetectOrientation()) {
            events.endOfStream()
            return
        }
        listener = l
        l.enable()
    }

    override fun onCancel(arguments: Any?) {
        listener?.disable()
        listener = null
    }

    /** Degrees are clockwise from the device's natural "up"; ±30° bands. */
    private fun classify(degrees: Int, naturalIsPortrait: Boolean): String? {
        if (degrees == OrientationEventListener.ORIENTATION_UNKNOWN) return null
        val d = degrees % 360
        val upright = d <= 30 || d >= 330 || d in 150..210
        val sideways = d in 60..120 || d in 240..300
        return when {
            upright -> if (naturalIsPortrait) "portrait" else "landscape"
            sideways -> if (naturalIsPortrait) "landscape" else "portrait"
            else -> null
        }
    }

    private fun naturalOrientationIsPortrait(): Boolean {
        @Suppress("DEPRECATION")
        val rotation = (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager)
            .defaultDisplay.rotation
        val portraitNow =
            context.resources.configuration.orientation == Configuration.ORIENTATION_PORTRAIT
        val rotated = rotation == Surface.ROTATION_90 || rotation == Surface.ROTATION_270
        return portraitNow != rotated
    }
}
