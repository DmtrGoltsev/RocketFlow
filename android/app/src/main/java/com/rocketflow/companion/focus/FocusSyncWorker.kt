package com.rocketflow.companion.focus

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.rocketflow.companion.BuildConfig
import com.rocketflow.companion.auth.AuthRepository
import com.rocketflow.companion.auth.SessionStore
import com.rocketflow.companion.network.ApiException
import com.rocketflow.companion.network.HttpJsonClient
import com.rocketflow.companion.planning.PlanningLocalStore
import java.util.concurrent.TimeUnit

class FocusSyncScheduler(context: Context) : FocusSyncEnqueuer {
    private val workManager = WorkManager.getInstance(context)

    override fun enqueueFocusSync() {
        val request = OneTimeWorkRequestBuilder<FocusSyncWorker>()
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .build()
        workManager.enqueueUniqueWork(WORK_NAME, ExistingWorkPolicy.KEEP, request)
    }

    companion object {
        private const val WORK_NAME = "rocketflow-focus-sync"
    }
}

class FocusSyncWorker(appContext: Context, params: WorkerParameters) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        return try {
            val auth = AuthRepository(HttpJsonClient(BuildConfig.ROCKETFLOW_API_BASE_URL), SessionStore(applicationContext))
            val session = auth.bootstrapSession() ?: return Result.failure()
            val repository = FocusRepository(
                auth,
                FocusLocalDataSource(PlanningLocalStore(applicationContext))
            )
            repository.syncPending(session)
            Result.success()
        } catch (error: ApiException) {
            if (isRetryableFocusSyncFailure(error)) Result.retry() else Result.failure()
        } catch (error: Exception) {
            if (isRetryableFocusSyncFailure(error)) Result.retry() else Result.failure()
        }
    }
}

internal fun isRetryableFocusSyncFailure(error: Throwable): Boolean {
    return error !is ApiException || error.status == 409 || error.status == 429 || error.status >= 500
}
