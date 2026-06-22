#!/bin/bash
# Container-internal crash replay — persistent + restart dual-mode
# No set -e: server crashes must NOT kill this script

SEED="$1"; PROTO="$2"; PORT="$3"; WORKDIR="$4"
PRE_CMD="${5:-}"; SRV_CMD="$6"; HEALTH_CHECK="${7:-true}"
MAX="${8:-5}"

cd "$WORKDIR"
export ASAN_OPTIONS="abort_on_error=1:symbolize=0:detect_leaks=0:detect_stack_use_after_return=1"

log() { echo "[$(date +%H:%M:%S)] $*"; }

check_crash() {
    # Returns 0 if server died unexpectedly, 1 if still alive
    if ! kill -0 $1 2>/dev/null; then
        local ec=0
        wait $1 2>/dev/null; ec=$?
        # sig=143=we killed it ourselves, ok=startup died before check
        # Any other state means the server exited abnormally = crash
        echo "CRASH_DETECTED exit_code=$ec"
        return 0
    fi
    return 1
}

# Phase A: Persistent — start ONCE, replay N times
log "Phase A: Persistent mode (start once, replay $MAX times)..."
eval "$PRE_CMD" 2>/dev/null || true
eval "$SRV_CMD" &
SPID=$!

READY=0
for a in $(seq 1 30); do
    if check_crash $SPID; then log "Server crashed during startup"; exit 0; fi
    if eval "$HEALTH_CHECK" 2>/dev/null; then READY=1; break; fi
    sleep 0.5
done

if [ $READY -eq 1 ]; then
    log "Server ready (PID $SPID)"
    for rep in $(seq 1 $MAX); do
        /home/ubuntu/chatafl-opt/aflnet-replay "$SEED" "$PROTO" "$PORT" 0 >/dev/null 2>&1 || true
        if check_crash $SPID; then
            log "persistent replay #$rep"
            exit 0
        fi
    done
    log "Survived $MAX persistent replays."
fi

kill $SPID 2>/dev/null || true
wait $SPID 2>/dev/null || true
sleep 0.3

# Phase B: Restart — fresh server each iteration
log "Phase B: Restart mode (fresh server, $MAX attempts)..."
for rep in $(seq 1 $MAX); do
    eval "$PRE_CMD" 2>/dev/null || true
    eval "$SRV_CMD" &
    SPID=$!

    READY=0
    for a in $(seq 1 30); do
        if check_crash $SPID; then log "startup crash, restart replay #$rep"; exit 0; fi
        if eval "$HEALTH_CHECK" 2>/dev/null; then READY=1; break; fi
        sleep 0.5
    done

    [ $READY -eq 0 ] && { kill $SPID 2>/dev/null || true; wait $SPID 2>/dev/null || true; continue; }

    /home/ubuntu/chatafl-opt/aflnet-replay "$SEED" "$PROTO" "$PORT" 0 >/dev/null 2>&1 || true

    if check_crash $SPID; then
        log "restart replay #$rep"
        exit 0
    fi

    kill $SPID 2>/dev/null || true
    wait $SPID 2>/dev/null || true
done

log "Both modes exhausted. Crash NOT reproduced in standalone Docker."
echo "CRASH_NOT_REPRODUCED"
