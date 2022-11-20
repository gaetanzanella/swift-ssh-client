#!/bin/bash

docker-compose -p sftp-integration --file ./sftp-docker-compose.yaml up -d

function waitSFTP {
   until docker logs sftp-integration-sftp-1 2>&1 | grep "Server" >/dev/null; do
      echo Waiting docker sftp to be ready...
      sleep 2
   done
}

function timeout() { perl -e 'alarm shift; exec @ARGV' "$@"; }

export -f waitSFTP

timeout 30 bash -c waitSFTP
