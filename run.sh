#!/bin/bash

docker build -t local/meshblu-benchmark . && \
  docker run \
    --rm \
    --publish 80:80 \
    --env MESHBLU_SERVER=172.17.8.1 \
    --env MESHBLU_PORT=3000 \
    local/meshblu-benchmark \
      message-webhook \
        --host 172.17.8.101 \
        --port 80 \
        --number-of-times 100
