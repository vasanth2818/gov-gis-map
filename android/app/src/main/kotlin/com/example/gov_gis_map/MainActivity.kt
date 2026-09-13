package com.example.gov_gis_map

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.IntentSender
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import com.google.android.gms.common.api.ResolvableApiException
import com.google.android.gms.location.*
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.gov_gis_map/location_settings"
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                "resolveLocationSettings" -> {
                    if (pendingResult == null) {
                        pendingResult = result
                        resolveLocationSettings()
                    } else {
                        result.error(
                            "PENDING",
                            "A resolution request is already in progress.",
                            null
                        )
                    }
                }

                "getLastKnownLocation" -> {
                    getLastKnownLocation(result)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    // ---------------------------------------------------------
    // LOCATION SETTINGS
    // ---------------------------------------------------------

    private fun resolveLocationSettings() {

        val locationRequest =
            LocationRequest.Builder(
                Priority.PRIORITY_HIGH_ACCURACY,
                1000
            ).build()

        val settingsRequest =
            LocationSettingsRequest.Builder()
                .addLocationRequest(locationRequest)
                .setAlwaysShow(true)
                .build()

        val settingsClient =
            LocationServices.getSettingsClient(this)

        settingsClient.checkLocationSettings(settingsRequest)
            .addOnSuccessListener {

                pendingResult?.success("enabled")
                pendingResult = null
            }
            .addOnFailureListener { exception ->

                if (exception is ResolvableApiException) {

                    try {
                        exception.startResolutionForResult(
                            this,
                            1001
                        )
                    } catch (sendEx: IntentSender.SendIntentException) {

                        pendingResult?.error(
                            "ERROR",
                            "Failed to show resolution dialog.",
                            null
                        )

                        pendingResult = null
                    }

                } else {

                    pendingResult?.error(
                        "ERROR",
                        "Unresolvable error occurred.",
                        null
                    )

                    pendingResult = null
                }
            }
    }

    // ---------------------------------------------------------
    // GET ANDROID CACHED LOCATION
    // ---------------------------------------------------------

    private fun getLastKnownLocation(
        result: MethodChannel.Result
    ) {

        if (
            ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_FINE_LOCATION
            ) != PackageManager.PERMISSION_GRANTED &&
            ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_COARSE_LOCATION
            ) != PackageManager.PERMISSION_GRANTED
        ) {

            result.error(
                "PERMISSION_DENIED",
                "Location permission has not been granted.",
                null
            )

            return
        }

        val fusedLocationClient =
            LocationServices.getFusedLocationProviderClient(this)

        fusedLocationClient.lastLocation
            .addOnSuccessListener { location ->

                if (location != null) {

                    val locationData = hashMapOf<String, Any>(
                        "latitude" to location.latitude,
                        "longitude" to location.longitude,
                        "accuracy" to location.accuracy.toDouble()
                    )

                    result.success(locationData)

                } else {

                    // Android has no cached location.
                    result.success(null)
                }
            }
            .addOnFailureListener { exception ->

                result.error(
                    "LOCATION_ERROR",
                    exception.message ?: "Unable to get last known location.",
                    null
                )
            }
    }

    // ---------------------------------------------------------
    // LOCATION SETTINGS RESULT
    // ---------------------------------------------------------

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ) {

        super.onActivityResult(
            requestCode,
            resultCode,
            data
        )

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