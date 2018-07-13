#!/bin/sh
set -x
SOURCE_PORT=5555
SINK_PORT=6666
N_WORKERS=2

remove_resilience_files() {
    rm -rf /tmp/hanging*
}

start_leader(){
  N_WORKERS=$1
  ./leaky_pipeline \
    --in 0.0.0.0:$SOURCE_PORT \
    --out 127.0.0.1:$SINK_PORT \
    --metrics 127.0.0.1:5001 \
    --control 127.0.0.1:12500 \
    --data 127.0.0.1:12501 \
    --external 127.0.0.1:5050 \
    --cluster-initializer --ponythreads=1 \
    --worker-count $N_WORKERS \
    --ponynoblock --ponynopin > worker0.log 2>&1 &
}

start_worker() {
  N=$1
  ./leaky_pipeline \
    --in 0.0.0.0:$((SOURCE_PORT+$N)) \
    --out 127.0.0.1:$SINK_PORT \
    --metrics 127.0.0.1:5001 \
    --control 127.0.0.1:12500 \
    --name worker$N --ponythreads=1 \
    --ponynoblock --ponynopin  > worker$N.log 2>&1 &
}


start_cluster() {
  start_leader $N_WORKERS
  sleep 1
  for i in $(seq $((N_WORKERS-1))); do
      start_worker $i
  done
}

(killall -9 leaky_pipeline ; sleep 0.2)
(killall -9 leaky_pipeline ; sleep 0.2)
remove_resilience_files
start_cluster

