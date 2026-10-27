package com.example.health_connect_demo

import android.app.Activity
import android.os.Bundle
import android.widget.TextView

// Health Connect's permission screen links here on both older and newer Android.
class PrivacyActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(TextView(this).apply {
            text = "Health Integration — privacy\n\n" +
                "This app reads steps, heart rate and sleep sessions only after " +
                "you grant permission. Data is displayed on this device and is " +
                "not uploaded, shared or saved by this app.\n\n" +
                "You can revoke access in Health Connect → App permissions → " +
                "Health Integration.\n\nUse Android Back to return."
            textSize = 18f
            val padding = (24 * resources.displayMetrics.density).toInt()
            setPadding(padding, padding, padding, padding)
        })
    }
}
