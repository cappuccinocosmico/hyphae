#!/usr/bin/env bash

# Hyphae Rclone Mount Diagnostics Script
# Run as root: sudo ./rclone-debug.sh

echo "=== Hyphae Rclone Mount Diagnostics ==="
echo "Timestamp: $(date)"
echo ""

echo "1. Testing rclone configuration and garage connection..."
echo "================================================"
rclone --config /etc/hyphae/secrets/rclone.conf lsd garage: 2>&1
echo ""

echo "2. Testing specific bucket access..."
echo "=================================="
echo "Listing hyphae-books bucket:"
timeout 10s rclone --config /etc/hyphae/secrets/rclone.conf ls garage:hyphae-books 2>&1
if [ $? -eq 124 ]; then
    echo "TIMEOUT: rclone ls command hung after 10 seconds"
fi
echo ""

echo "3. Checking rclone mount processes..."
echo "===================================="
ps aux | grep rclone | grep -v grep
echo ""

echo "4. Checking systemd mount status..."
echo "=================================="
for bucket in hyphae-books hyphae-data hyphae-shows hyphae-movies hyphae-music; do
    echo "Status for $bucket:"
    systemctl status "etc-hyphae-mounts-${bucket//-/\\x2d}.mount" --no-pager -l
    echo "---"
done
echo ""

echo "5. Recent mount logs..."
echo "====================="
for bucket in hyphae-books hyphae-data hyphae-shows hyphae-movies hyphae-music; do
    echo "Logs for $bucket:"
    journalctl -u "etc-hyphae-mounts-${bucket//-/\\x2d}.mount" -n 5 --no-pager
    echo "---"
done
echo ""

echo "6. Testing Garage API directly..."
echo "==============================="
echo "Garage health check:"
curl -s -w "\nHTTP Status: %{http_code}\nTime: %{time_total}s\n" http://localhost:3900 2>&1
echo ""

echo "7. Network connectivity test..."
echo "============================="
echo "Garage S3 API port test:"
nc -zv localhost 3900 2>&1
echo ""

echo "8. Checking rclone config file..."
echo "==============================="
if [ -f /etc/hyphae/secrets/rclone.conf ]; then
    echo "Config file exists and is readable"
    echo "File permissions: $(ls -la /etc/hyphae/secrets/rclone.conf)"
    echo "Config file size: $(wc -c < /etc/hyphae/secrets/rclone.conf) bytes"
else
    echo "ERROR: rclone.conf not found!"
fi
echo ""

echo "9. Manual mount test..."
echo "====================="
echo "Attempting manual rclone mount (will timeout after 10 seconds):"
mkdir -p /tmp/test-mount 2>/dev/null
timeout 10s rclone mount --config /etc/hyphae/secrets/rclone.conf garage:hyphae-books /tmp/test-mount --vfs-cache-mode writes --allow-other --daemon 2>&1
if [ $? -eq 124 ]; then
    echo "TIMEOUT: Manual mount command hung"
else
    echo "Manual mount completed"
    # Try to list and then unmount
    ls /tmp/test-mount 2>&1 | head -5
    fusermount -u /tmp/test-mount 2>/dev/null
fi
echo ""

echo "=== Diagnostics Complete ==="