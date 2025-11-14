#!/bin/bash
set -e

echo "Starting Sentinel initialization..."

# Create directory
mkdir -p /etc/redis

REDIS_PORT=${REDIS_PORT}

# Now find the actual master
n=0
MASTER_HOST=""

while [ $n -ne 10 ]
do
  n=$(($n+1))
  for NODE_HOST in ${REDIS_NODES//,/ }
  do
      echo "Finding master at $NODE_HOST:$REDIS_PORT"
      
      # Test connection first (with auth)
      if ! redis-cli --no-auth-warning --raw -h $NODE_HOST -p $REDIS_PORT -a ${REDIS_PASSWORD} ping 2>/dev/null | grep -q PONG; then
          echo "  ❌ Cannot connect to $NODE_HOST:$REDIS_PORT"
          continue
      fi
      
      # Get replication info (with auth)
      REPLICATION_INFO=$(redis-cli --no-auth-warning --raw -h $NODE_HOST -p $REDIS_PORT -a ${REDIS_PASSWORD} info replication 2>/dev/null)
      if [ $? -ne 0 ]; then
          echo "  ❌ Failed to get replication info from $NODE_HOST:$REDIS_PORT"
          continue
      fi
      
      ROLE=$(echo "$REPLICATION_INFO" | grep "role:" | cut -d ":" -f2 | tr -d '\r')
      echo "  ✅ Connected to $NODE_HOST:$REDIS_PORT - Role: $ROLE"
      
      if [ "$ROLE" == "master" ]; then
          echo "Found actual master at: $NODE_HOST:$REDIS_PORT"
          MASTER_HOST=$NODE_HOST
          break 2
      fi
  done
  echo "No master found. Retrying... ($n/10)"
  sleep 5
done

# If no master found after retries, use first node
if [ -z "$MASTER_HOST" ]; then
    echo "No master found after retries, defaulting to first node"
    MASTER_HOST="${REDIS_NODES%%,*}"
    echo "Using fallback master: $MASTER_HOST:$REDIS_PORT"
fi

# Create the final sentinel.conf
cat > /etc/redis/sentinel.conf << EOF
port 26379
dir /tmp
bind 0.0.0.0

# OpenShift compatibility
sentinel resolve-hostnames yes
sentinel announce-hostnames yes

# Authentication
requirepass ${REDIS_PASSWORD}

# Master configuration
sentinel monitor ${SENTINEL_MASTER_NAME} ${MASTER_HOST} ${REDIS_PORT} ${SENTINEL_QUORUM}
sentinel down-after-milliseconds ${SENTINEL_MASTER_NAME} ${SENTINEL_DOWN_AFTER_MS}
sentinel failover-timeout ${SENTINEL_MASTER_NAME} ${SENTINEL_FAILOVER_TIMEOUT}
sentinel parallel-syncs ${SENTINEL_MASTER_NAME} ${SENTINEL_PARALLEL_SYNCS}
sentinel auth-pass ${SENTINEL_MASTER_NAME} ${REDIS_PASSWORD}

# Use proper headless service DNS name for announce-ip
sentinel announce-ip ${HOSTNAME}.${SENTINEL_HEADLESS_SERVICE}
EOF

echo "=== Final Sentinel Config ==="
cat /etc/redis/sentinel.conf

echo "Sentinel initialization completed successfully"
echo "Configured master: $MASTER_HOST:$REDIS_PORT"