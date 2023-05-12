package com.tigerbeetle;

public final class MaxConcurrencyExceededException extends Exception {

    @Override
    public String getMessage() {
        return toString();
    }

    @Override
    public String toString() {
        return "The maximum configured concurrency for the client has been exceeded.";
    }

}
