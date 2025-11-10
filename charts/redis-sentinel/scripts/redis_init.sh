#!/bin/bash
cp /tmp/redis/redis.conf /etc/redis/redis.conf
echo "requirepass \${REDIS_PASSWORD}" >> /etc/redis/redis.conf
echo "masterauth \${REDIS_PASSWORD}" >> /etc/redis/redis.conf
echo "replica-announce-ip \${HOSTNAME}.redis" >> /etc/redis/redis.conf
echo "replica-announce-port 6379" >> /etc/redis/redis.conf

echo "finding master..."
if [ "$(timeout 5 redis-cli -h ${SENTINEL_SERVICE} -p ${SENTINEL_PORT} -a \${REDIS_PASSWORD} ping)" != "PONG" ]; then
  echo "sentinel not found, defaulting to ${REDIS_SERVICE}-0"
  if [ "${HOSTNAME}" == "${REDIS_SERVICE}-0" ]; then
    echo "this is ${REDIS_SERVICE}-0, not updating config..."
  else
    echo "updating redis.conf..."
    echo "repl-ping-replica-period 3" >> /etc/redis/redis.conf
    echo "replica-read-only no" >> /etc/redis/redis.conf
    echo "replicaof ${REDIS_SERVICE}-0.${REDIS_HEADLESS_SERVICE} 6379" >> /etc/redis/redis.conf
  fi
else
  echo "sentinel found, finding master"
  MASTER="$(redis-cli -h ${SENTINEL_SERVICE} -p ${SENTINEL_PORT} -a \${REDIS_PASSWORD} sentinel get-master-addr-by-name ${SENTINEL_MASTER_NAME} | head -1)"
  if [ "${HOSTNAME}.redis" == "${MASTER}" ] || [ "${HOSTNAME}" == "${MASTER}" ]; then
    echo "this is master, not updating config..."
  else
    echo "master found : ${MASTER}, updating redis.conf"
    echo "replica-read-only no" >> /etc/redis/redis.conf
    echo "replicaof ${MASTER} 6379" >> /etc/redis/redis.conf
    echo "repl-ping-replica-period 3" >> /etc/redis/redis.conf
  fi
fi