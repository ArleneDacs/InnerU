package com.valenin.inneru.wear

import android.app.Activity
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val scrollView = ScrollView(this).apply {
            isFillViewport = true
            setBackgroundColor(0xFF101614.toInt())
        }

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(20, 24, 20, 24)
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }

        content.addView(label("InnerU", 22f, true))
        content.addView(label("Quick check-in", 13f, false))
        content.addView(tile("Steps", "Track today's movement from your phone."))
        content.addView(tile("Fasting", "Glance at your active timer."))
        content.addView(tile("Meditate", "Start a calm moment."))
        content.addView(tile("Mood", "Remember how you feel right now."))

        scrollView.addView(content)
        setContentView(scrollView)
    }

    private fun label(text: String, size: Float, bold: Boolean): TextView {
        return TextView(this).apply {
            this.text = text
            textSize = size
            setTextColor(0xFFF6FFFA.toInt())
            gravity = Gravity.CENTER
            if (bold) typeface = android.graphics.Typeface.DEFAULT_BOLD
            setPadding(0, 4, 0, 6)
        }
    }

    private fun tile(title: String, subtitle: String): TextView {
        return TextView(this).apply {
            text = "$title\n$subtitle"
            textSize = 13f
            setTextColor(0xFFE7FFF4.toInt())
            setBackgroundResource(R.drawable.watch_tile_background)
            setPadding(16, 12, 16, 12)
            val margin = resources.displayMetrics.density.toInt() * 8
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins(0, margin, 0, 0)
            }
        }
    }
}
