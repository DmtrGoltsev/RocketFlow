package com.rocketflow.companion.planning

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.rocketflow.companion.BuildConfig
import com.rocketflow.companion.auth.AuthRepository
import com.rocketflow.companion.auth.SessionStore
import com.rocketflow.companion.network.ApiException
import com.rocketflow.companion.network.HttpJsonClient

class PlanningSyncWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        return try {
            val authRepository = AuthRepository(
                httpJsonClient = HttpJsonClient(BuildConfig.ROCKETFLOW_API_BASE_URL),
                sessionStore = SessionStore(applicationContext)
            )
            val session = authRepository.bootstrapSession() ?: return Result.failure()
            val repository = PlanningRepository(
                authRepository = authRepository,
                localStore = PlanningLocalStore(applicationContext)
            )
            val result = repository.syncAndLoad(session)
            if (result.snapshot.offline) boundedRetry() else Result.success()
        } catch (error: ApiException) {
            if (error.status == 401) Result.failure() else boundedRetry()
        } catch (_: Exception) {
            boundedRetry()
        }
    }

    private fun boundedRetry(): Result {
        return if (runAttemptCount >= MAX_RETRY_ATTEMPTS) {
            Result.failure()
        } else {
            Result.retry()
        }
    }

    companion object {
        private const val MAX_RETRY_ATTEMPTS = 5
    }
}
