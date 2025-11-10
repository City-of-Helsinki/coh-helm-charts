#!/bin/bash
n=0
while [ $n -ne 10 ]
do
  n=$(($n+1))
  for i in ${REDIS_NODES//,/ }
  do
      echo "finding master at $i"
      MASTER=$(redis-cli --no-auth-warning --raw -h $i -a $REDIS_PASSWORD info replication | awk '{print $1}' | grep master_host: | cut -d ":" -f2)

      if [ "${MASTER}" == "" ]; then
          MASTER=
      else
          break
      fi
  done
  if [ "${MASTER}" == "" ]; then
      echo "No master found. Retrying..."
  else
      echo "found ${MASTER}"
      break
  fi
  sleep 5
done

echo "sentinel monitor ${SENTINEL_MASTER_NAME} ${MASTER} 6379 ${SENTINEL_QUORUM}" >> /tmp/master

echo "port ${SENTINEL_PORT}
sentinel resolve-hostnames yes
sentinel announce-hostnames yes
$(cat /tmp/master)
sentinel down-after-milliseconds ${SENTINEL_MASTER_NAME} ${SENTINEL_DOWN_AFTER_MS}
sentinel failover-timeout ${SENTINEL_MASTER_NAME} ${SENTINEL_FAILOVER_TIMEOUT}
sentinel parallel-syncs ${SENTINEL_MASTER_NAME} ${SENTINEL_PARALLEL_SYNCS}
sentinel sentinel-pass \${REDIS_PASSWORD}
sentinel auth-pass ${SENTINEL_MASTER_NAME} \${REDIS_PASSWORD}
requirepass \${REDIS_PASSWORD}
sentinel announce-ip ${HOSTNAME}.sentinel
sentinel announce-port ${SENTINEL_PORT}
sentinel master-reboot-down-after-period ${SENTINEL_MASTER_NAME} 10000
" > /etc/redis/sentinel.conf

cat /etc/redis/sentinel.conf