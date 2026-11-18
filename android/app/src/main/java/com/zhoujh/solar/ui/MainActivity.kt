package com.zhoujh.solar.ui

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.*
import com.zhoujh.solar.data.Config
import com.zhoujh.solar.data.DeviceKind
import com.zhoujh.solar.data.Prefs

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent {
            var config by remember { mutableStateOf(Prefs.load(this)) }
            var selected by remember { mutableStateOf<DeviceKind?>(null) }
            var showSettings by remember { mutableStateOf(false) }

            fun saveCfg(url: String, token: String) {
                Prefs.save(this, url, token)
                config = Prefs.load(this)
                com.zhoujh.solar.widget.SolarWidgetProvider.refreshNow(this)
            }

            when (selected) {
                null -> MainScreen(
                    config = config,
                    onOpenSettings = { showSettings = true },
                    onOpenDevice = { selected = it }
                )
                else -> DetailScreen(
                    kind = selected!!,
                    config = config,
                    onBack = { selected = null }
                )
            }

            if (showSettings) {
                SettingsSheet(
                    initial = config,
                    onDismiss = { showSettings = false },
                    onSave = { u, t -> saveCfg(u, t); showSettings = false }
                )
            }
        }
    }
}
