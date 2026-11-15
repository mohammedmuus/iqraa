package tz.or.iqraa

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/**
 * Home screen light bulb. It glows bright while the reader opens Iqraa, then dims over a week away,
 * and the verse beside it grows firmer as it dims.
 */
class LampWidget : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { manager.updateAppWidget(it, build(context)) }
    }

    companion object {
        private const val PREFS = "iqraa_lamp"
        private const val KEY = "data"

        private val lamps = intArrayOf(R.drawable.lamp_0, R.drawable.lamp_1, R.drawable.lamp_2, R.drawable.lamp_3)
        private val cards = intArrayOf(R.drawable.lamp_card_0, R.drawable.lamp_card_1, R.drawable.lamp_card_2, R.drawable.lamp_card_3)
        private val heading = intArrayOf(0xFF1F6B4A.toInt(), 0xFF8A6A2E.toInt(), 0xFFE3CF9F.toInt(), 0xFFE3CF9F.toInt())
        private val words = intArrayOf(0xFF0B0B0C.toInt(), 0xFF2B2925.toInt(), Color.WHITE, Color.WHITE)
        private val small = intArrayOf(0xFF6E6E68.toInt(), 0xFF6E6E68.toInt(), 0xFFC9C6BC.toInt(), 0xFFA3A39E.toInt())

        /** Called by the app through the tz.or.iqraa/widget channel each time it opens. */
        fun save(context: Context, json: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, json).apply()
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, LampWidget::class.java))
            ids.forEach { manager.updateAppWidget(it, build(context)) }
        }

        private fun stageFor(days: Long): Int = when {
            days <= 1 -> 0
            days <= 3 -> 1
            days <= 6 -> 2
            else -> 3
        }

        private fun build(context: Context): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.lamp_widget)
            val open = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            views.setOnClickPendingIntent(R.id.lamp_root, PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))

            val saved = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
            val data = saved?.let { runCatching { JSONObject(it) }.getOrNull() }
            if (data == null) {
                show(views, 3, "", context.getString(R.string.lamp_widget_empty), "")
                return views
            }
            val zone = ZoneId.systemDefault()
            val opened = Instant.ofEpochMilli(data.optLong("opened")).atZone(zone).toLocalDate()
            val today = LocalDate.now(zone)
            val days = ChronoUnit.DAYS.between(opened, today).coerceAtLeast(0)
            val stage = stageFor(days)
            val labels = data.optJSONObject("labels") ?: JSONObject()
            val label = when {
                days == 0L -> labels.optString("today")
                days == 1L -> labels.optString("one")
                stage < 3 -> labels.optString("days")
                else -> labels.optString("out")
            }.replace("{n}", days.toString())

            var verse = ""
            var reference = ""
            val stages = data.optJSONArray("stages")
            val choices = stages?.optJSONArray(stage)
            if (choices != null && choices.length() > 0) {
                val pick = choices.optJSONObject((today.dayOfYear % choices.length()))
                verse = pick?.optString("text").orEmpty()
                reference = pick?.optString("ref").orEmpty()
            }
            if (verse.isEmpty()) {
                verse = labels.optString("empty")
            }
            show(views, stage, label, verse, reference)
            val direction = if (data.optBoolean("rtl")) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR
            views.setInt(R.id.lamp_root, "setLayoutDirection", direction)
            return views
        }

        private fun show(views: RemoteViews, stage: Int, label: String, verse: String, reference: String) {
            views.setInt(R.id.lamp_root, "setBackgroundResource", cards[stage])
            views.setImageViewResource(R.id.lamp_image, lamps[stage])
            views.setTextViewText(R.id.lamp_label, label)
            views.setTextColor(R.id.lamp_label, heading[stage])
            views.setViewVisibility(R.id.lamp_label, if (label.isEmpty()) View.GONE else View.VISIBLE)
            views.setTextViewText(R.id.lamp_verse, verse)
            views.setTextColor(R.id.lamp_verse, words[stage])
            views.setTextViewText(R.id.lamp_ref, reference)
            views.setTextColor(R.id.lamp_ref, small[stage])
            views.setViewVisibility(R.id.lamp_ref, if (reference.isEmpty()) View.GONE else View.VISIBLE)
        }
    }
}
