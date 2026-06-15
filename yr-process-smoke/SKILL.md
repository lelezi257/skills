---
name: yr-process-smoke
description: Use when building, deploying, or running the openYuanrong 3-node process-mode actor smoke test (python/java/cpp) against the test cluster at bastion 1.95.199.126 — covers triggering a yuanrong-jcl buildkite package build, pulling OBS wheels, deploying+patching the rust functionsystem under the Python CLI, running the actor suites, and collecting logs.
---

# YuanRong Process-Mode Actor Smoke

End-to-end runbook to take a functionsystem change → release package → deployed 3-node cluster → python/java/cpp actor smoke → collected results. Validated this works; every gotcha below cost real time.

**Pipeline:** build (buildkite) → OBS wheels → deploy 5-patch → start cluster → framework install → run suites → collect.

Scripts live in `scripts/` next to this file. Set `SKILL_DIR` to this directory.

## Inputs / secrets (ASK THE USER — never bake into the repo)
None of these are committed. At the start of a run, check what's already configured; if anything
needed for the steps you're about to do is missing, **ask the user for it via the interaction window**
(AskUserQuestion), then wire it in locally. Do not hardcode tokens/keys in scripts or commits.
- **Buildkite token** (Step 1, package build) — provided by the **yr-buildkite** skill at
  `~/.config/yr-buildkite/config.env`. If absent, ask the user (have them run yr-buildkite's setup or paste it).
- **Bastion SSH key** (Steps 3-6) — `~/.ssh/id_rsa_minhui` + the `Host 1.95.199.126` ssh-config block
  below. If the key file is missing, ask the user to drop it at that path (or supply their own authorized key).
  Egress IP must be allowlisted on the bastion; if SSH is filtered, ask the user to get the egress IP whitelisted.
- **GitCode token** (only if you pull cases/source yourself) — ask the user; used for case/source repos.

## Cluster access (READ FIRST)

- **Bastion:** `root@1.95.199.126`. Three SSH ports map to the three nodes:
  - `-p 22227` → `192.168.0.173` (`test02-ylp`) — **test host + master**, runs the actor suites
  - `-p 22226` → `192.168.0.4` (`-5a34`)
  - `-p 22225` → `192.168.0.31` (`-84bc`)
- **Key:** `~/.ssh/id_rsa_minhui` (songminhui's, already authorized on all nodes). Wire it in so the plain `ssh`/`scp` in the scripts use it:
  ```bash
  grep -q 'Host 1.95.199.126' ~/.ssh/config || cat >> ~/.ssh/config <<'EOF'

  Host 1.95.199.126
    IdentityFile ~/.ssh/id_rsa_minhui
    IdentitiesOnly yes
    StrictHostKeyChecking no
  EOF
  ```
- **fail2ban gotcha:** many rapid SSH connections get the egress IP banned → `kex_exchange_identification: Connection closed` (TCP opens, SSH drops at handshake). **Back off ~4 min, don't hammer** (retries extend the ban). Batch commands into FEWER ssh calls. If a fresh allowlist is needed, add the egress IP (`curl -s ifconfig.me`) to the bastion's fail2ban ignoreip.
- **Self-match gotcha:** `pkill -f "<pattern>"` and `pgrep -fc "<pattern>"` MATCH YOUR OWN remote shell when the pattern string is in its command line (e.g. `start --master`, `run_java_actor_test`). Use **exact-name** `pkill -x <comm>` or kill by PID; don't trust `pgrep -fc` counts of those strings.

## Step 1 — Build a release package (skip if you already have a build #)

The package pipeline is **buildkite `yuanrong-jcl`**, building from **`ChamberlainJI/yuanrong`** (private fork). Reference build **#30** (canonical green) / #32 (rust-rewrite). Uses yr-buildkite skill's token (`~/.config/yr-buildkite/config.env`).

```bash
cd <yuanrong-superproject>                       # the repo with the functionsystem submodule
git submodule update --remote --init functionsystem   # pull latest openeuler rust-rewrite tip
git add functionsystem && git commit -m "chore(functionsystem): bump submodule ...
Signed-off-by: ChamberlainJI <jichenglin1@huawei.com>"
git push chamberlain HEAD:refs/heads/codex/merge-sandbox-to-master   # remote 'chamberlain' = ChamberlainJI/yuanrong.git
```
Trigger the build (env copied from build #30 — `ENABLE_RUNTIME_X86`, sandbox package, `FUNCTIONSYSTEM_BRANCH=rust-rewrite`, etc.). The exact env JSON is in build #30's `meta_data`; POST it to `…/pipelines/yuanrong-jcl/builds`. Watch with `yr-bk status <n>`. ~50 min. **jcl builds expose NO buildkite artifacts** — packages are on OBS only.

> If `Build X86` fails on a vendor patch (e.g. `spdlog/ignore_rename_exception.patch` Hunk FAILED) it's a third-party/build-infra break in that functionsystem tip, not deployable — fix the patch or pick another tip.

## Step 2 — Resolve OBS package URLs

```bash
source "$SKILL_DIR/scripts/get_obs_urls.sh" <build_number>   # prints VERSION + WHEEL_* + TARBALL
# export them for the install step:
eval "$(bash "$SKILL_DIR/scripts/get_obs_urls.sh" <build_number> | grep -E '^(VERSION|WHEEL_|TARBALL)=')"
```

## Step 3 — Deploy the cluster (per node)

A process-mode master needs 6 wheels: `openyuanrong` (Python CLI + cli configs), `runtime` (goruntime), `functionsystem` (rust bins), `datasystem` (worker+etcd), `sdk` cp311, `faas`. **Do NOT install `openyuanrong_full`** — it ships the Go CLI; the default `openyuanrong` wheel gives `yr=yr.cli.main:main` (the Python yrexp CLI, what we need).

```bash
for P in 22227 22226 22225; do
  # 3a. install wheels
  ssh -p $P root@1.95.199.126 \
    "WHEEL_openyuanrong='$WHEEL_openyuanrong' WHEEL_runtime='$WHEEL_runtime' WHEEL_functionsystem='$WHEEL_functionsystem' WHEEL_datasystem='$WHEEL_datasystem' WHEEL_faas='$WHEEL_faas' WHEEL_sdk='$WHEEL_sdk' bash -s" < "$SKILL_DIR/scripts/node_install.sh"
  # 3b. stage per-node config from the last good deploy backup (3-node etcd topology, per-node labels)
  ssh -p $P root@1.95.199.126 'b=$(ls -dt /tmp/yr-process-deploy-backup/*/ | head -1); cp -a "$b"config.toml "$b"services.yaml "$b"metrics.json /home/disk/yr-workspace/'
  # 3c. apply the 5 rust adaptations (see "Known adaptations")
  ssh -p $P root@1.95.199.126 'python3.11 -' < "$SKILL_DIR/scripts/apply_patches.py"
done
```

## Step 4 — Start the cluster (all nodes, for etcd quorum)

The CLI is config-driven: `yr -c config.toml start --master`. Start all 3 (multi-master etcd needs quorum). The daemon supervises components.

```bash
TS=$(date +%H%M%S)
for P in 22227 22226 22225; do
  ssh -p $P root@1.95.199.126 "cd /home/disk/yr-workspace; export MY_ENV=myenv LD_LIBRARY_PATH=:/testEnv PYTHONPATH=:/testpythonpayh; \
    setsid bash -c 'yr -c /home/disk/yr-workspace/config.toml start --master > yr-start-$TS.log 2>&1' </dev/null >/dev/null 2>&1 &"
done
# verify (on .173):
ssh -p 22227 root@1.95.199.126 "grep -m1 'All components are healthy' /home/disk/yr-workspace/yr-start-$TS.log; \
  ~/.../yr/third_party/etcd/etcdctl --endpoints=http://192.168.0.173:32379,http://192.168.0.4:32379,http://192.168.0.31:32379 endpoint health; \
  curl -s -o /dev/null -w 'master:%{http_code}\n' http://192.168.0.173:22770/global-scheduler/healthy"
```
Expect `✅ All components are healthy!`, 3 healthy etcd, master/proxy HTTP `200`, and `function_master/proxy/agent + meta_service + goruntime + etcd` per node.

**Restart/stop cleanly** (config changes like the data_system_host patch need a restart): `yr -c config.toml stop` first; if components are orphaned (daemon already gone) hard-kill by exact name `for n in function_master function_proxy function_agent meta_service datasystem_worker goruntime etcd runtime_manager; do pkill -KILL -x "$n"; done`; ensure port 31501 is free (`ss -lnt | grep :31501`) before restart or `check_port()` shifts ds_worker to a random port.

## Step 5 — Run the actor smoke

Suites connect to the running cluster via `/root/.yr/config.ini` (already points at `192.168.0.173:22773` etc.). **java/cpp use the WORKSPACE SDK** (not site-packages), so refresh it from the MATCHING tarball first; **python uses site-packages** so it works without this.

```bash
# 5a. framework install from the matching tarball (java/cpp SDK). NOTE: auto_install rejects -s.
ssh -p 22227 root@1.95.199.126 "cd \$W/.../scripts/shell; curl -fsSL -o /home/disk/yr-workspace/openyuanrong-$VERSION.tar.gz '$TARBALL'; \
  rm -rf \$W/output/openyuanrong; sh auto_install_test_framework.sh -w \$W -v '$VERSION'"
# 5b. jar-naming fix (tarball ships yr-api-sdk-v0.0.1.jar; install expects yr-api-sdk-<VERSION>.jar), then resume:
ssh -p 22227 root@1.95.199.126 "JD=\$W/output/openyuanrong/runtime/sdk/java; ln -sf yr-api-sdk-v0.0.1.jar \$JD/yr-api-sdk-$VERSION.jar; \
  bash install_yuanrong.sh -w \$W -v '$VERSION' -s 192.168.0.173 -d PROCESS -a in_cluster; \
  bash config_framework.sh -w \$W -v '$VERSION' -s 192.168.0.173 -d PROCESS -a in_cluster -k false -b local"
# 5b'. the framework install pip-reinstalls site-packages -> RE-APPLY apply_patches.py on all 3 nodes, then restart cluster.
# 5c. run suites (java BEFORE cpp — cpp deletes *.so incl java's libcross.so)
scp -P 22227 ... "$SKILL_DIR/scripts/run_lang.sh" root@1.95.199.126:/home/disk/yr-workspace/
ssh -p 22227 root@1.95.199.126 'bash /home/disk/yr-workspace/run_lang.sh python run_python_actor_test.sh'
ssh -p 22227 root@1.95.199.126 'bash /home/disk/yr-workspace/run_lang.sh java   run_java_actor_test.sh'
ssh -p 22227 root@1.95.199.126 'bash /home/disk/yr-workspace/run_lang.sh cpp    run_cpp_actor_test.sh'
```
Suites are slow (10–30 min each). `collie` framework can hang BETWEEN cases (no pytest subproc, log mtime stale >10 min) — if so it's a framework stall, not a rust hang; kill `collie`/`run_*_actor_test` and move on.

## Step 6 — Collect

```bash
bash "$SKILL_DIR/scripts/collect_logs.sh"   # -> /tmp/yr_smoke_logs/{node-<ip>-fs.tar.gz, test_logs-173.tar.gz}
```
Per-case detail: `/tmp/test_logs/<run>/<Case>/` on .173 (java surefire / cpp gtest / python pytest). FS+runtime: `/tmp/yr_sessions/<latest>/logs/` per node (`function_{master,proxy,agent}_stdout.log`, `function_agent_stdout.log` = runtime_manager, `rt-*.std{err,out}.log` = per-runtime).

## Known adaptations (why apply_patches.py exists)

The rust functionsystem needs these to run under the latest Python CLI. **Re-verify each against the version you deploy** — upstream may fix some (track in issue #67).

| # | Symptom | Fix (in apply_patches.py) |
|---|---------|---------------------------|
| 1 | `function_proxy`: `--cache_storage_port cannot be used multiple times` | drop `data_system_{host,port}` from `[function_proxy.args]` (rust aliases them to cache_storage_*) |
| 2 | `function_agent`: `unexpected argument --RUNTIME_METRICS_CONFIG` | remove it from `[function_agent.args]` in config.toml (keep in `[function_agent.env]`) |
| 3 | C++ runtime: `Invalid address of datasystem :31501` (java/cpp only) | add `data_system_host` to `[function_agent.args]` jinja; restart |
| 4 | runtime exits / `spawn runtime` fails | symlink `runtime/service/python/yr→yr` and `runtime/service/cpp→cpp` (wheel installs them at yr/main, yr/cpp) |
| 5 | java install: `yr-api-sdk-<VERSION>.jar not exists` | `ln -sf yr-api-sdk-v0.0.1.jar yr-api-sdk-<VERSION>.jar` (step 5b) |

## Known failure classes — GitCode issue #67
Baseline moved over time; **as of `rust-rewrite-sandbox @ 050da50` python is 33/34** (the 1 = `test_caching_actors`, an SDK-layer not-init error-path, NOT rust-FS). Re-measure against the build you deploy; don't trust an old N/34.
- **Fixed since the old baseline:** `yr.resources()` 3002 (`test_yr_resource`, gang) — fixed in build#21 (`3fa0482c`/`d7823fb9`): proxy pushes `signalReq(FunctionMasterEvent)` for driver master-discovery + master fills `ResourceUnit.fragment` + the 22770 compat port serves protobuf `/global-scheduler/resources`.
- **Still real rust-FS gaps:** anti-affinity / gang co-scheduling don't spread (`*anti*` cases land same node). Precise gap: the label-affinity filter/scorer plugins exist+registered in `common/utils/schedule_plugin`, but `schedule_affinity` from the request is **not wired into the scheduler's `AffinityContext`** (proxy only reads it for group strict-pack fingerprint). Mirror C++ `function_master/scaler/utils/parse_helper.cpp::ParseAffinityFromCreateOpts` + `create_agent_decision` to populate it. Also: `yr.wait(num_returns)` partition; runtime working_dir env.
- **Fix discipline:** rust-rewrite is a LANGUAGE REPLACEMENT — for any bug/feature mirror the C++ baseline (openYuanRong `feature/sandbox`, e.g. `9984ab40`); read the C++ source before implementing, keep semantics equivalent.
- **java 0/11 = NOT rust FS:** `2002 <func> not found in FunctionHelper` — java JNI/libcross.so registration bridge; cpp uses the same C++ runtime and passes.
- **Flaky (single-rerun passes, per SKILL):** cpp `ExitTest`, `GetWithParamTest`; python `test_invoke_concurrency`.

## Related skills / refs
- **yr-smoke-aio** — LOCAL multi-node AIO smoke (containerized). Iterate fixes there first (compile
  trio ~40-90s, redeploy ~1-2min) and only come here for the authoritative/remote process-mode run or
  cases the local containerized model can't cover. The stack: edit rust → **yr-smoke-aio** (fast local
  loop) → **this** (remote 3-node truth) → **yr-buildkite** (the package build feeding both).
- **yr-buildkite** — buildkite tokens, triggering/watching jcl builds, logs/artifacts.
- **yr-dev** — GitCode API (file issues / comments, e.g. issue #67), submodule/PR workflow.
- Upstream reference skill (songminhui's machine, has more cluster history): `/Users/songminhui/.codex/skills/yr-process-actor-smoke`.
