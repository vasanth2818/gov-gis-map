package com.example.gov_gis_map
import com.google.android.gms.common.api.ResolvableApiException
import android.app.Activity
import android.content.Intent
import android.content.IntentSender
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.android.gms.location.*

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.gov_gis_map/location_settings"
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "resolveLocationSettings") {
                if (pendingResult == null) {
                    pendingResult = result
                    resolveLocationSettings()
                } else {
                    result.error("PENDING", "A resolution request is already in progress.", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun resolveLocationSettings() {
        val locationRequest = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 1000).build()
        val settingsRequest = LocationSettingsRequest.Builder()
            .addLocationRequest(locationRequest)
            .setAlwaysShow(true)
            .build()

        val settingsClient = LocationServices.getSettingsClient(this)
        settingsClient.checkLocationSettings(settingsRequest)
            .addOnSuccessListener {
                pendingResult?.success("enabled")
                pendingResult = null
            }
            .addOnFailureListener { exception ->
                if (exception is ResolvableApiException) {
                    try {
                        exception.startResolutionForResult(this, 1001)
                    } catch (sendEx: IntentSender.SendIntentException) {
                        pendingResult?.error("ERROR", "Failed to show resolution dialog.", null)
                        pendingResult = null
                    }
                } else {
                    pendingResult?.error("ERROR", "Unresolvable error occurred.", null)
                    pendingResult = null
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 1001) {
            if (resultCode == Activity.RESULT_OK) {
                pendingResult?.success("enabled")
            } else {
                pendingResult?.success("cancelled")
            }
            pendingResult = null
        }
    }
}
