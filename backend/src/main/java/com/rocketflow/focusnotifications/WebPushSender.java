package com.rocketflow.focusnotifications;

import java.time.Duration;

interface WebPushSender {
    Result send(WebPushSubscription subscription, FocusPushPayload payload);

    record Result(Outcome outcome, String providerResponse, Duration retryAfter) {
        static Result sent(String response) { return new Result(Outcome.SENT, response, null); }
        static Result retry(String response, Duration retryAfter) { return new Result(Outcome.RETRY, response, retryAfter); }
        static Result deactivate(String response) { return new Result(Outcome.DEACTIVATE, response, null); }
        static Result permanentFailure(String response) { return new Result(Outcome.PERMANENT_FAILURE, response, null); }
        static Result configFailure(String response) { return new Result(Outcome.CONFIG_FAILURE, response, null); }
    }

    enum Outcome {
        SENT,
        RETRY,
        DEACTIVATE,
        PERMANENT_FAILURE,
        CONFIG_FAILURE
    }
}
