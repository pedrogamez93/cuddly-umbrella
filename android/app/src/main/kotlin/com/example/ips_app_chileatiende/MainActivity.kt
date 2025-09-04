package com.example.ips_app_chileatiende

import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val callingPackage = callingActivity?.packageName
        if (callingPackage != null && callingPackage != packageName) {
            Log.w("MainActivity", "Unauthorized launch attempt from $callingPackage")
            finish()
        }
    }
}