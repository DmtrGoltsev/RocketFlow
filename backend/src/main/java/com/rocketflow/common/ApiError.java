package com.rocketflow.common;

import java.util.List;

public record ApiError(ErrorBody error) {

    public static ApiError of(String code, String message) {
        return new ApiError(new ErrorBody(code, message, List.of(), null));
    }

    public static ApiError of(String code, String message, List<ErrorDetail> details) {
        return new ApiError(new ErrorBody(code, message, details, null));
    }

    public record ErrorBody(String code, String message, List<ErrorDetail> details, String traceId) {
    }

    public record ErrorDetail(String field, String message) {
    }
}
