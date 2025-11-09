#!/bin/bash
cp /tmp/redis/redis.conf /etc/redis/redis.conf
echo "requirepass ${REDIS_PASSWORD}" >> /etc/redis/redis.conf
echo "masterauth ${REDIS_PASSWORD}" >> /etc/redis/redis.conf
echo "replica-announce-ip ${HOSTNAME}.redis" >> /etc/redis/redis.conf
echo "replica-announce-port 6379" >> /etc/redis/redis.conf

echo "finding master..."
if [ "$(timeout 5 redis-cli -h {{ include "redis-sentinel.fullname" . }}-sentinel -p {{ .Values.sentinel.config.port }} -a ${REDIS_PASSWORD} ping)" != "PONG" ]; then
  echo "sentinel not found, defaulting to {{ include "redis-sentinel.fullname" . }}-redis-0"
  if [ ${HOSTNAME} == "{{ include "redis-sentinel.fullname" . }}-redis-0" ]; then
    echo "this is {{ include "redis-sentinel.fullname" . }}-redis-0, not updating config..."
  else
    echo "updating redis.conf..."
    echo "repl-ping-replica-period 3" >> /etc/redis/redis.conf
    echo "replica-read-only no" >> /etc/redis/redis.conf
    echo "replicaof {{ include "redis-sentinel.fullname" . }}-redis-0.{{ include "redis-sentinel.fullname" . }}-headless 6379" >> /etc/redis/redis.conf
  fi
else
  echo "sentinel found, finding master"
  MASTER="$(redis-cli -h {{ include "redis-sentinel.fullname" . }}-sentinel -p {{ .Values.sentinel.config.port }} -a ${REDIS_PASSWORD} sentinel get-master-addr-by-name {{ .Values.sentinel.config.masterName }} | grep -E '(^{{ include "redis-sentinel.fullname" . }}-redis-*)|([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})')"
  if [ "${HOSTNAME}.redis" == ${MASTER} ]; then
    echo "this is master, not updating config..."
  else
    echo "master found : ${MASTER}, updating redis.conf"
    echo "replica-read-only no" >> /etc/redis/redis.conf
    echo "replicaof ${MASTER} 6379" >> /etc/redis/redis.conf
    echo "repl-ping-replica-period 3" >> /etc/redis/redis.conf
  fi
fi