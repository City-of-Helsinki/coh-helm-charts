#!/bin/bash
set -e

# Copy base config
cp /tmp/redis/redis.conf /etc/redis/redis.conf
printf "\n" >> /etc/redis/redis.conf

# Add authentication and replication settings
echo "requirepass ${REDIS_PASSWORD}" >> /etc/redis/redis.conf
echo "masterauth ${REDIS_PASSWORD}" >> /etc/redis/redis.conf
echo "replica-announce-ip ${HOSTNAME}.${REDIS_HEADLESS_SERVICE}" >> /etc/redis/redis.conf
echo "replica-announce-port 6379" >> /etc/redis/redis.conf

# Get pod index from hostname (e.g., "redis-sentinel-redis-2" -> "2")
POD_INDEX="${HOSTNAME##*-}"

echo "=== Redis Initialization ==="
echo "Pod: $HOSTNAME, Index: $POD_INDEX"

# For the first pod (index 0), start as master
if [ "$POD_INDEX" -eq "0" ]; then
    echo "I am the first pod (${HOSTNAME}), starting as MASTER"
    echo "replica-read-only no" >> /etc/redis/redis.conf
    # No replicaof command for master
    
else
    echo "I am replica pod (${HOSTNAME}), configuring as SLAVE"
    
    MASTER_NODE="${REDIS_SERVICE}-0.${REDIS_HEADLESS_SERVICE}"
    
    # Wait for master to be ready
    echo "Waiting for master ${MASTER_NODE} to be ready..."
    until redis-cli -h ${MASTER_NODE} -a ${REDIS_PASSWORD} --no-auth-warning ping | grep -q PONG; do
        echo "Master not ready yet, retrying..."
        sleep 5
    done
    
    echo "Master is ready, configuring as replica..."
    echo "replica-read-only no" >> /etc/redis/redis.conf
    echo "repl-ping-replica-period 3" >> /etc/redis/redis.conf
    echo "replicaof ${MASTER_NODE} 6379" >> /etc/redis/redis.conf
    
    echo "✅ Configured as replica of ${MASTER_NODE}"
fi

echo "=== Final Redis Configuration ==="
echo "replica-announce-ip: ${HOSTNAME}.${REDIS_HEADLESS_SERVICE}"
if [ "$POD_INDEX" -eq "0" ]; then
    echo "role: MASTER"
else
    echo "role: SLAVE of ${MASTER_NODE}"
fi

echo "✅ Redis initialization completed"