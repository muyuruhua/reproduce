#!/bin/bash
# Container-internal crash replay — pure persistent mode
# Two rounds: start server, replay N times against same process, repeat once

SEED="$1"; PROTO="$2"; PORT="$3"; WORKDIR="$4"
PRE_CMD="${5:-}"; SRV_CMD="$6"; HEALTH_CHECK="${7:-true}"
MAX="${8:-5}"

cd "$WORKDIR"
export ASAN_OPTIONS="abort_on_error=1:symbolize=0:detect_leaks=0:detect_stack_use_after_return=1"

log() { echo "[$(date +%H:%M:%S)] $*"; }

replay_round() {
    local round="$1"
    log "Round $round: Starting server..."
    eval "$PRE_CMD" 2>/dev/null || true
    eval "$SRV_CMD" &
    local SPID=$!

    local READY=0
    for a in $(seq 1 60); do
        if ! kill -0 $SPID 2>/dev/null; then wait $SPID 2>/dev/null; local ec=$?; echo "CRASH_DETECTED exit_code=$ec"; exit 0; fi
        if eval "$HEALTH_CHECK" 2>/dev/null; then READY=1; break; fi
        sleep 0.5
    done

    if [ $READY -ne 1 ]; then
        log "Server failed to start in round $round"
        kill $SPID 2>/dev/null || true; wait $SPID 2>/dev/null || true
        return 1
    fi

    log "Server ready (PID $SPID), replaying $MAX times..."
    for rep in $(seq 1 $MAX); do
        /home/ubuntu/chatafl-opt/aflnet-replay "$SEED" "$PROTO" "$PORT" 0 >/dev/null 2>&1 || true
        if ! kill -0 $SPID 2>/dev/null; then
            wait $SPID 2>/dev/null; local ec=$?
            echo "CRASH_DETECTED exit_code=$ec replay=#$rep round=$round"
            exit 0
        fi
    done
    log "Round $round: survived $MAX replays."
    kill $SPID 2>/dev/null || true; wait $SPID 2>/dev/null || true
    sleep 0.5
    return 0
}

replay_round 1 || true
replay_round 2 || true

log "All rounds exhausted. Crash NOT reproduced."
echo "CRASH_NOT_REPRODUCED"
