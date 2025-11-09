#!/bin/bash
n=0
while [ $n -ne 10 ]
do
  n=$(($n+1))
  for i in ${REDIS_NODES//,/ }
  do
      echo "finding master at $i"
      MASTER=$(redis-cli --no-auth-warning --raw -h $i -a ${REDIS_PASSWORD} info replication | awk '{print $1}' | grep master_host: | cut -d ":" -f2)
      
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

echo "sentinel monitor {{ .Values.sentinel.config.masterName }} ${MASTER} 6379 {{ .Values.sentinel.config.quorum }}" >> /tmp/master

echo "port {{ .Values.sentinel.config.port }}
sentinel resolve-hostnames yes
sentinel announce-hostnames yes
$(cat /tmp/master)
sentinel down-after-milliseconds {{ .Values.sentinel.config.masterName }} {{ .Values.sentinel.config.downAfterMilliseconds }}
sentinel failover-timeout {{ .Values.sentinel.config.masterName }} {{ .Values.sentinel.config.failoverTimeout }}
sentinel parallel-syncs {{ .Values.sentinel.config.masterName }} {{ .Values.sentinel.config.parallelSyncs }}
sentinel sentinel-pass ${REDIS_PASSWORD}
sentinel auth-pass {{ .Values.sentinel.config.masterName }} ${REDIS_PASSWORD}
requirepass ${REDIS_PASSWORD}
sentinel announce-ip ${HOSTNAME}.sentinel
sentinel announce-port {{ .Values.sentinel.config.port }}
sentinel master-reboot-down-after-period {{ .Values.sentinel.config.masterName }} 10000
" > /etc/redis/sentinel.conf

cat /etc/redis/sentinel.conf