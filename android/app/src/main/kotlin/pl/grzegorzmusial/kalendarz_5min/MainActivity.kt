package pl.grzegorzmusial.kalendarz_5min

import android.Manifest
import android.content.ContentResolver
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.database.Cursor
import android.os.Handler
import android.os.Looper
import android.provider.CalendarContract.Calendars
import android.provider.CalendarContract.Events
import android.provider.CalendarContract.Instances
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private var channel: MethodChannel? = null
    private var permissionReply: MethodChannel.Result? = null
    private var observing = false
    private val permissions = arrayOf(
        Manifest.permission.READ_CALENDAR,
        Manifest.permission.WRITE_CALENDAR
    )
    private val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) {
            channel?.invokeMethod("changed", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "calendar/android")
        channel?.setMethodCallHandler { call, reply ->
            when (call.method) {
                "hasPermission" -> {
                    startObserving()
                    reply.success(hasPermission())
                }
                "requestPermission" -> requestAccess(reply)
                "settings" -> {
                    startActivity(Intent(Settings.ACTION_SYNC_SETTINGS))
                    reply.success(null)
                }
                "appSettings" -> {
                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    intent.data = android.net.Uri.fromParts("package", packageName, null)
                    startActivity(intent)
                    reply.success(null)
                }
                "day", "save" -> worker.execute {
                    try {
                        if (!hasPermission()) throw SecurityException()
                        val value = if (call.method == "day") {
                            readDay(call)
                        } else {
                            save(call)
                            null
                        }
                        runOnUiThread { reply.success(value) }
                    } catch (_: SecurityException) {
                        runOnUiThread { reply.error("permission", null, null) }
                    } catch (error: Exception) {
                        android.util.Log.w("Calendar", "Calendar operation failed", error)
                        runOnUiThread { reply.error("calendar", null, null) }
                    }
                }
                else -> reply.notImplemented()
            }
        }
    }

    private fun hasPermission() =
        permissions.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }

    private fun requestAccess(reply: MethodChannel.Result) {
        if (hasPermission()) {
            startObserving()
            reply.success(true)
        } else if (permissionReply != null) {
            reply.error("pending", null, null)
        } else {
            permissionReply = reply
            requestPermissions(permissions, 42)
        }
    }

    override fun onRequestPermissionsResult(code: Int, names: Array<String>, results: IntArray) {
        super.onRequestPermissionsResult(code, names, results)
        if (code == 42) {
            startObserving()
            permissionReply?.success(hasPermission())
            permissionReply = null
        }
    }

    private fun startObserving() {
        if (!observing && hasPermission()) {
            contentResolver.registerContentObserver(Calendars.CONTENT_URI, true, observer)
            contentResolver.registerContentObserver(Events.CONTENT_URI, true, observer)
            observing = true
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel?.setMethodCallHandler(null)
        channel = null
        if (observing) contentResolver.unregisterContentObserver(observer)
        observing = false
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        worker.shutdown()
        super.onDestroy()
    }

    private fun googleCalendars(): List<Map<String, Any?>> {
        val projection = arrayOf(
            Calendars._ID, Calendars.CALENDAR_DISPLAY_NAME, Calendars.ACCOUNT_NAME,
            Calendars.CALENDAR_COLOR, Calendars.CALENDAR_ACCESS_LEVEL, Calendars.IS_PRIMARY
        )
        val calendars = mutableListOf<Map<String, Any?>>()
        checkNotNull(contentResolver.query(
            Calendars.CONTENT_URI, projection,
            "${Calendars.ACCOUNT_TYPE} = ? AND ${Calendars.SYNC_EVENTS} = 1",
            arrayOf("com.google"),
            "${Calendars.IS_PRIMARY} DESC, ${Calendars.CALENDAR_DISPLAY_NAME} ASC"
        )).use { cursor ->
            while (cursor.moveToNext()) {
                val account = cursor.string(Calendars.ACCOUNT_NAME).orEmpty()
                calendars.add(mapOf(
                    "id" to cursor.long(Calendars._ID),
                    "name" to cursor.string(Calendars.CALENDAR_DISPLAY_NAME).orEmpty(),
                    "account" to account,
                    "color" to cursor.long(Calendars.CALENDAR_COLOR),
                    "primary" to cursor.flag(Calendars.IS_PRIMARY),
                    "writable" to (cursor.long(Calendars.CALENDAR_ACCESS_LEVEL) >= Calendars.CAL_ACCESS_CONTRIBUTOR),
                    "sync" to (ContentResolver.getMasterSyncAutomatically() &&
                        ContentResolver.getSyncAutomatically(
                            android.accounts.Account(account, "com.google"), "com.android.calendar"
                        ))
                ))
            }
        }
        return calendars
    }

    private fun readDay(call: MethodCall): Map<String, Any> {
        val calendars = googleCalendars()
        val calendarIds = calendars.map { it["id"] }.toSet()
        val events = mutableListOf<Map<String, Any?>>()
        val start = call.number("start")
        val end = call.number("end")
        val utcStart = call.number("utcStart")
        val utcEnd = call.number("utcEnd")
        val uri = Instances.CONTENT_URI.buildUpon().also {
            ContentUris.appendId(it, minOf(start, utcStart))
            ContentUris.appendId(it, maxOf(end, utcEnd))
        }.build()
        if (calendars.isNotEmpty()) {
            val projection = arrayOf(
                Instances.EVENT_ID, Instances.CALENDAR_ID, Instances.TITLE, Instances.BEGIN,
                Instances.END, Instances.ALL_DAY, Instances.RRULE, Instances.RDATE,
                Instances.IS_ORGANIZER, Instances.GUESTS_CAN_MODIFY, Instances.EVENT_COLOR
            )
            checkNotNull(contentResolver.query(
                uri, projection,
                "${Calendars.ACCOUNT_TYPE} = ? AND ${Calendars.SYNC_EVENTS} = 1 AND " +
                    "(${Instances.STATUS} IS NULL OR ${Instances.STATUS} != ?)",
                arrayOf("com.google", Events.STATUS_CANCELED.toString()),
                "${Instances.BEGIN} ASC"
            )).use { cursor ->
                while (cursor.moveToNext()) {
                    val eventCalendarId = cursor.long(Instances.CALENDAR_ID)
                    if (eventCalendarId !in calendarIds) continue
                    val rule = cursor.string(Instances.RRULE)
                    val dates = cursor.string(Instances.RDATE)
                    val begin = cursor.long(Instances.BEGIN)
                    val finish = cursor.long(Instances.END)
                    val allDay = cursor.flag(Instances.ALL_DAY)
                    val dayStart = if (allDay) utcStart else start
                    val dayEnd = if (allDay) utcEnd else end
                    if (begin >= dayEnd || (finish <= dayStart && begin < dayStart)) continue
                    events.add(mapOf(
                        "id" to cursor.long(Instances.EVENT_ID),
                        "calendarId" to eventCalendarId,
                        "title" to cursor.string(Instances.TITLE).orEmpty(),
                        "start" to begin,
                        "end" to finish,
                        "allDay" to allDay,
                        "recurring" to !rule.isNullOrEmpty(),
                        "canModify" to ((!rule.isNullOrEmpty() || dates.isNullOrEmpty()) && (cursor.flag(Instances.IS_ORGANIZER) ||
                            cursor.flag(Instances.GUESTS_CAN_MODIFY))),
                        "color" to cursor.optionalLong(Instances.EVENT_COLOR)
                    ))
                }
            }
        }
        return mapOf("calendars" to calendars, "events" to events)
    }

    private fun save(call: MethodCall) {
        val calendarId = call.number("calendarId")
        val calendar = googleCalendars().firstOrNull { it["id"] == calendarId }
        check(calendar?.get("writable") == true)
        val title = checkNotNull(call.argument<String>("title")).trim()
        val start = call.number("start")
        val end = call.number("end")
        require(end > start)
        val id = call.argument<Number>("id")?.toLong()
        val values = ContentValues().apply {
            put(Events.TITLE, title)
            put(Events.DTSTART, start)
            put(Events.DTEND, end)
        }
        if (id == null) {
            require(title.isNotBlank())
            values.put(Events.CALENDAR_ID, calendarId)
            values.put(Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
            checkNotNull(contentResolver.insert(Events.CONTENT_URI, values))
            return
        }
        val uri = ContentUris.withAppendedId(Events.CONTENT_URI, id)
        val columns = arrayOf(
            Events.CALENDAR_ID, Events.ALL_DAY, Events.IS_ORGANIZER,
            Events.GUESTS_CAN_MODIFY, Events.RRULE, Events.RDATE
        )
        val (allDay, recurring) = checkNotNull(contentResolver.query(uri, columns, null, null, null)).use {
            check(it.moveToFirst() && it.long(Events.CALENDAR_ID) == calendarId)
            check(it.flag(Events.IS_ORGANIZER) || it.flag(Events.GUESTS_CAN_MODIFY))
            val hasRule = !it.string(Events.RRULE).isNullOrEmpty()
            check(hasRule || it.string(Events.RDATE).isNullOrEmpty())
            it.flag(Events.ALL_DAY) to hasRule
        }
        if (allDay) {
            val zone = TimeZone.getDefault().id
            values.put(Events.ALL_DAY, 0)
            values.put(Events.EVENT_TIMEZONE, zone)
            values.put(Events.EVENT_END_TIMEZONE, zone)
        }
        if (recurring) {
            // The provider derives the end from DURATION when creating an exception.
            values.remove(Events.DTEND)
            values.put(Events.DURATION, "PT${(end - start) / 1000}S")
            values.put(Events.ORIGINAL_INSTANCE_TIME, call.number("originalStart"))
            val exception = ContentUris.withAppendedId(Events.CONTENT_EXCEPTION_URI, id)
            checkNotNull(contentResolver.insert(exception, values))
        } else {
            check(contentResolver.update(uri, values, null, null) == 1)
        }
    }

    private fun MethodCall.number(key: String) = checkNotNull(argument<Number>(key)).toLong()
    private fun Cursor.index(column: String) = getColumnIndexOrThrow(column)
    private fun Cursor.long(column: String) = getLong(index(column))
    private fun Cursor.flag(column: String) = long(column) == 1L
    private fun Cursor.string(column: String) = getString(index(column))
    private fun Cursor.optionalLong(column: String): Long? =
        index(column).let { if (isNull(it)) null else getLong(it) }
}
