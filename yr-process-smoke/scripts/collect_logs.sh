#!/usr/bin/env bash
# Run ON the laptop. Pull all smoke logs from the 3 nodes into a local dir.
# Usage: collect_logs.sh [outdir]   (default /tmp/yr_smoke_logs)
set -euo pipefail
OUT="${1:-/tmp/yr_smoke_logs}"; mkdir -p "$OUT"; cd "$OUT"
PORTS=(22227 22226 22225)
for p in "${PORTS[@]}"; do
  ip=$(ssh -o ConnectTimeout=20 -p "$p" root@1.95.199.126 'hostname -I 2>/dev/null | awk "{print \$1}"' 2>/dev/null | grep -v Warning)
  echo "== node :$p ($ip) =="
  ssh -o ConnectTimeout=25 -p "$p" root@1.95.199.126 '
    SD=$(ls -dt /tmp/yr_sessions/2026* | head -1)
    tar czf /tmp/yrlogs.tar.gz --warning=no-file-changed \
      --exclude="*/rocksdb/*" --exclude="*/third_party/etcd/*" \
      "$SD/logs" /home/disk/yr-workspace/actor-*.log /home/disk/yr-workspace/yr-start-*.log 2>/dev/null
    du -h /tmp/yrlogs.tar.gz | cut -f1' 2>&1 | grep -v "Warning: Permanently"
  scp -P "$p" -o ConnectTimeout=25 root@1.95.199.126:/tmp/yrlogs.tar.gz "$OUT/node-${ip}-fs.tar.gz" 2>&1 | grep -v "Warning: Permanently"
done
# per-case logs (java surefire / cpp gtest / python pytest) live only on the test host .173
ssh -o ConnectTimeout=25 -p 22227 root@1.95.199.126 'tar czf /tmp/testlogs.tar.gz /tmp/test_logs 2>/dev/null; du -h /tmp/testlogs.tar.gz|cut -f1' 2>&1 | grep -v "Warning: Permanently"
scp -P 22227 -o ConnectTimeout=25 root@1.95.199.126:/tmp/testlogs.tar.gz "$OUT/test_logs-173.tar.gz" 2>&1 | grep -v "Warning: Permanently"
echo "=== collected into $OUT ==="; ls -lh "$OUT"
