package com.rocketflow.companion.planning

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

enum class PlanningSyncReason {
    Startup,
    PendingChange,
    NetworkRestore,
    Manual
}

interface PlanningSyncEnqueuer {
    fun enqueuePlanningSync(reason: PlanningSyncReason)
}

class PlanningSyncScheduler(context: Context) : PlanningSyncEnqueuer {
    private val appContext = context.applicationContext

    override fun enqueuePlanningSync(reason: PlanningSyncReason) {
        val request = OneTimeWorkRequestBuilder<PlanningSyncWorker>()
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
            )
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, BACKOFF_SECONDS, TimeUnit.SECONDS)
            .setInputData(Data.Builder().putString(KEY_REASON, reason.name).build())
            .build()

        WorkManager.getInstance(appContext).enqueueUniqueWork(
            UNIQUE_WORK_NAME,
            if (reason == PlanningSyncReason.Manual) ExistingWorkPolicy.REPLACE else ExistingWorkPolicy.KEEP,
            request
        )
    }

    companion object {
        const val UNIQUE_WORK_NAME = "planning-offline-sync"
        const val KEY_REASON = "reason"
        private const val BACKOFF_SECONDS = 30L
    }
}
