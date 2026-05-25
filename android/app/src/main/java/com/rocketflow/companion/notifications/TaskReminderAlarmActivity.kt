package com.rocketflow.companion.notifications

import android.app.Activity
import android.app.NotificationManager
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.content.ContextCompat
import com.rocketflow.companion.MainActivity

class TaskReminderAlarmActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        configureAlarmWindow()

        val taskId = intent.getStringExtra(NotificationRuntime.EXTRA_TASK_ID).orEmpty()
        val title = intent.getStringExtra(NotificationRuntime.EXTRA_TITLE)
            ?.takeIf { it.isNotBlank() }
            ?: "RocketFlow reminder"
        val body = intent.getStringExtra(NotificationRuntime.EXTRA_BODY)
            ?.takeIf { it.isNotBlank() }
            ?: "Open the task in RocketFlow Companion."

        setContentView(
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER_HORIZONTAL
                setPadding(dp(24), dp(48), dp(24), dp(32))
                setBackgroundColor(Color.parseColor("#FFFDF7"))
                layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )

                addView(TextView(context).apply {
                    text = title
                    textSize = 28f
                    setTextColor(Color.parseColor("#20201D"))
                    setTypeface(typeface, Typeface.BOLD)
                    gravity = Gravity.CENTER
                    maxLines = 3
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT
                    )
                })
                addView(TextView(context).apply {
                    text = body
                    textSize = 17f
                    setTextColor(Color.parseColor("#716B61"))
                    gravity = Gravity.CENTER
                    setPadding(0, dp(18), 0, dp(28))
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT
                    )
                })
                addView(Button(context).apply {
                    text = "Open"
                    setOnClickListener { openTask(taskId) }
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT
                    )
                })
                addView(Button(context).apply {
                    text = "Dismiss"
                    setOnClickListener { dismissAlarm() }
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT
                    ).apply { topMargin = dp(10) }
                })
            }
        )
    }

    private fun configureAlarmWindow() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
        )
    }

    private fun openTask(taskId: String) {
        cancelNotification()
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(NotificationRuntime.EXTRA_TASK_ID, taskId)
            data = NotificationIntents.taskDeepLink(taskId)
        }
        startActivity(openIntent)
        finish()
    }

    private fun dismissAlarm() {
        cancelNotification()
        finish()
    }

    private fun cancelNotification() {
        val notificationId = intent.getIntExtra(NotificationRuntime.EXTRA_NOTIFICATION_ID, 0)
        if (notificationId != 0) {
            ContextCompat.getSystemService(this, NotificationManager::class.java)
                ?.cancel(notificationId)
        }
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }
}
