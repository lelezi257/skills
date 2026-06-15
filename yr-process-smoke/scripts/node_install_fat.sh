#!/usr/bin/env bash
# Run ON a cluster node (via ssh ... 'bash -s' < node_install_fat.sh).
# Installs the feature/sandbox FAT wheel layout (1 fat wheel + 1 sdk wheel)
# instead of the legacy jcl 6-wheel layout. Component binaries live under
# site-packages/yr/inner/<component>/ (note the extra "inner/" level).
# Env: WHEEL_main (fat openyuanrong wheel URL), WHEEL_sdk (cp311 sdk wheel URL)
set -uo pipefail
echo "[stop existing cluster processes]"
yr -c /home/disk/yr-workspace/config.toml stop >/dev/null 2>&1 || true
sleep 2
for n in function_master function_proxy function_agent meta_service datasystem_worker goruntime etcd runtime_manager; do
  pkill -KILL -x "$n" 2>/dev/null || true
done
sleep 1
if ss -lnt 2>/dev/null | grep -q ':31501 '; then echo "  WARN: port 31501 still busy"; else echo "  ports clear"; fi
S=/home/disk/yr-package-staging
rm -rf "$S"; mkdir -p "$S"; cd "$S"
for var in WHEEL_main WHEEL_sdk; do
  url="${!var:-}"; [ -n "$url" ] || { echo "MISSING $var"; exit 1; }
  fn=$(basename "${url%%\?*}"); fn="${fn//%2B/+}"
  url="${url//+/%2B}"   # OBS treats a literal '+' in the path as a space -> 403; re-encode
  curl -fsSL -o "$fn" "$url" && echo "  got $fn ($(stat -c%s "$fn") B)" || { echo "  FAIL $url"; exit 1; }
done
echo "[pip uninstall legacy jcl component wheels]"
python3.11 -m pip uninstall --break-system-packages -y \
  openyuanrong openyuanrong-runtime openyuanrong-functionsystem \
  openyuanrong-datasystem openyuanrong-faas openyuanrong-sdk openyuanrong_full \
  >/tmp/pipuninstall.log 2>&1 || true
# legacy layout leftovers under yr/ would shadow/confuse the new CLI; wipe yr pkg dir
sp=$(python3.11 -c 'import site; print(site.getsitepackages()[0])')
rm -rf "$sp/yr"
echo "[pip install --no-deps --force-reinstall]"
python3.11 -m pip install --break-system-packages --force-reinstall --no-cache-dir --no-deps "$S"/*.whl \
  >/tmp/pipinstall.log 2>&1 && echo "  pip OK" || { echo "  pip FAILED"; tail -20 /tmp/pipinstall.log; exit 1; }
echo "[verify] site=$sp"
echo -n "  fs bins: "; ls "$sp/yr/inner/functionsystem/bin/" 2>/dev/null | tr '\n' ' '; echo
for f in inner/third_party/etcd/etcd inner/runtime/service/go/bin/goruntime inner/datasystem/service/datasystem_worker; do
  echo -n "  yr/$f: "; test -x "$sp/yr/$f" && echo present || echo MISSING
done
echo -n "  yr CLI: "; command -v yr >/dev/null && yr --version 2>/dev/null | head -1 || echo "(yr not on PATH)"
python3.11 -m pip show openyuanrong openyuanrong-sdk 2>/dev/null | grep -E '^(Name|Version):' | paste - -
