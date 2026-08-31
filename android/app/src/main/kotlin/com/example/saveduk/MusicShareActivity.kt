package com.example.saveduk

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * Dedicated trampoline activity for the SaveDuk Music share target.
 *
 * Declared as an independent top-level Activity with its own taskAffinity and
 * ic_launcher_music icon so Android presents it as a distinct standalone item
 * in the system share sheet (rather than grouping it inside a dropdown).
 */
class MusicShareActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val incomingIntent = intent
        val targetIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_SEND
            type = incomingIntent?.type ?: "text/plain"
            putExtra(Intent.EXTRA_TEXT, incomingIntent?.getStringExtra(Intent.EXTRA_TEXT))
            putExtra("saveduk_mode", "music")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        startActivity(targetIntent)
        finish()
    }
}
