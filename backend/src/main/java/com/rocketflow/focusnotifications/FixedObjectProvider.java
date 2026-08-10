package com.rocketflow.focusnotifications;

import java.util.Iterator;
import java.util.stream.Stream;

import org.springframework.beans.factory.ObjectProvider;

final class FixedObjectProvider<T> implements ObjectProvider<T> {
    private final T value;

    FixedObjectProvider(T value) {
        this.value = value;
    }

    @Override
    public T getObject(Object... args) {
        return value;
    }

    @Override
    public T getObject() {
        return value;
    }

    @Override
    public T getIfAvailable() {
        return value;
    }

    @Override
    public T getIfUnique() {
        return value;
    }

    @Override
    public Iterator<T> iterator() {
        return Stream.of(value).iterator();
    }
}
