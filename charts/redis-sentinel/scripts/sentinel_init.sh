#!/bin/bash
# Copy the base sentinel configuration first
cp /tmp/sentinel/sentinel.conf /etc/redis/sentinel.conf

# Process environment variables in the config file
envsubst < /etc/redis/sentinel.conf > /etc/redis/sentinel.conf.tmp
mv /etc/redis/sentinel.conf.tmp /etc/redis/sentinel.conf

# Then proceed with master discovery and configuration updates
n=0
MASTER=""
while [ $n -ne 10 ]
do
  n=$(($n+1))
  for i in ${REDIS_NODES//,/ }
  do
      echo "finding master at $i"
      
      # Test connection first (with auth)
      if ! redis-cli --no-auth-warning --raw -h $i -a ${REDIS_PASSWORD} ping 2>/dev/null | grep -q PONG; then
          echo "  ❌ Cannot connect to $i"
          continue
      fi
      
      # Get replication info (with auth)
      REPLICATION_INFO=$(redis-cli --no-auth-warning --raw -h $i -a ${REDIS_PASSWORD} info replication 2>/dev/null)
      if [ $? -ne 0 ]; then
          echo "  ❌ Failed to get replication info from $i"
          continue
      fi
      
      ROLE=$(echo "$REPLICATION_INFO" | grep "role:" | cut -d ":" -f2 | tr -d '\r')
      echo "  ✅ Connected to $i - Role: $ROLE"
      
      if [ "$ROLE" == "master" ]; then
          echo "Found master at: $i"
          MASTER=$i
          break 2
      fi
  done
  echo "No master found. Retrying... ($n/10)"
  sleep 5
done

# If no master found after retries, default to first node
if [ -z "$MASTER" ]; then
    echo "No master found after retries, defaulting to first node"
    MASTER="${REDIS_NODES%%,*}"
    echo "Using default master: $MASTER"
fi

# Remove any existing sentinel monitor line and add the new one
sed -i '/sentinel monitor .*/d' /etc/redis/sentinel.conf
echo "sentinel monitor ${SENTINEL_MASTER_NAME} ${MASTER} 6379 ${SENTINEL_QUORUM}" >> /etc/redis/sentinel.conf

# Use proper headless service DNS name for announce-ip
echo "sentinel announce-ip ${HOSTNAME}.${SENTINEL_SERVICE}" >> /etc/redis/sentinel.conf

echo "=== Final Sentinel Config ==="
cat /etc/redis/sentinel.conf