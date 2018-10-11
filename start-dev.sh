#!/bin/sh
exec erl \
    -pa ebin deps/*/ebin \
    -boot start_sasl \
    -sname msync_dev \
    -s msync \
    -s reloader
