#!/usr/bin/env python3.11
"""Apply the deploy-side adaptations the rust functionsystem needs to run under
the Python yrexp CLI. Run ON each cluster node AFTER pip-installing the wheels
and AFTER staging config.toml into /home/disk/yr-workspace/.

Idempotent. Patches the INSTALLED files in site-packages + workspace, and
creates the runtime-path symlinks. See SKILL.md "Known adaptations" for why
each is needed (validated against build #32 / functionsystem rust-rewrite 566f6f6;
re-verify against the version you deploy — upstream may have fixed some).
"""
import os, re, shutil, site, sys

SP = os.path.join(site.getsitepackages()[0], "yr")
JINJA = os.path.join(SP, "cli", "config.toml.jinja")
CONFIG = "/home/disk/yr-workspace/config.toml"

def backup(p):
    if os.path.exists(p) and not os.path.exists(p + ".orig"):
        shutil.copy(p, p + ".orig")

def section_filter(path, section, drop_prefixes):
    """Remove lines starting with any drop_prefix, but only inside [section]."""
    if not os.path.exists(path):
        print(f"  SKIP {path} (missing)"); return
    backup(path)
    out, sec, removed = [], None, []
    for line in open(path).read().splitlines(keepends=True):
        s = line.strip()
        if s.startswith("[") and s.endswith("]"): sec = s
        if sec == section and any(s.startswith(p) for p in drop_prefixes):
            removed.append(s[:48]); continue
        out.append(line)
    open(path, "w").write("".join(out))
    print(f"  {path} [{section}] removed: {removed or 'none'}")

def section_add_after(path, section, anchor_prefix, new_line):
    """Insert new_line after the first anchor_prefix line inside [section], if absent."""
    if not os.path.exists(path):
        print(f"  SKIP {path} (missing)"); return
    text = open(path).read()
    m = re.search(r'\[' + re.escape(section.strip('[]')) + r'\.args\](.*?)(?:\n\[|\Z)', text, re.S) \
        if section.endswith(".args]") else None
    key = new_line.split("=")[0].strip()
    # already present in that section?
    blk = re.search(r'\[' + re.escape(section.strip('[]')) + r'\](.*?)(?:\n\[|\Z)', text, re.S)
    if blk and re.search(r'(?m)^\s*' + re.escape(key) + r'\s*=', blk.group(1)):
        print(f"  {path} [{section}] {key}: already present"); return
    backup(path)
    out, sec, done = [], None, False
    for line in text.splitlines(keepends=True):
        s = line.strip()
        if s.startswith("[") and s.endswith("]"): sec = s
        out.append(line)
        if sec == section and s.startswith(anchor_prefix) and not done:
            out.append(new_line if new_line.endswith("\n") else new_line + "\n"); done = True
    open(path, "w").write("".join(out))
    print(f"  {path} [{section}] added {key}: {'ok' if done else 'ANCHOR NOT FOUND'}")

def symlink(target, link):
    os.makedirs(os.path.dirname(link), exist_ok=True)
    if os.path.islink(link) or os.path.exists(link):
        try: os.remove(link)
        except IsADirectoryError: shutil.rmtree(link)
    os.symlink(target, link)
    ok = os.path.exists(link)
    print(f"  symlink {link} -> {target} : {'OK' if ok else 'FAILED'}")

print("== 1. function_proxy: drop duplicate data_system_* (alias of cache_storage_*) ==")
section_filter(JINJA, "[function_proxy.args]", ("data_system_host", "data_system_port"))

print("== 3. function_agent: add data_system_host (CLI template omits it -> C++ runtime ':31501') ==")
section_add_after(JINJA, "[function_agent.args]", "data_system_port",
                  'data_system_host = "{{ values.ds_worker.ip }}"')

print("== 2. function_agent: RUNTIME_METRICS_CONFIG must be env-only, not an --arg ==")
section_filter(CONFIG, "[function_agent.args]", ("RUNTIME_METRICS_CONFIG",))

print("== 4. runtime path symlinks (wheel installs python at yr/main, cpp at yr/cpp) ==")
symlink(SP, os.path.join(SP, "runtime", "service", "python", "yr"))             # python runtime
symlink(os.path.join(SP, "cpp"), os.path.join(SP, "runtime", "service", "cpp")) # cpp runtime (bin+lib)

print("== verify ==")
print("  python runtime entry:", "OK" if os.path.exists(os.path.join(SP,"runtime/service/python/yr/main/yr_runtime_main.py")) else "MISSING")
print("  cpp runtime bin:", "OK" if os.path.exists(os.path.join(SP,"runtime/service/cpp/bin/runtime")) else "MISSING")
print("DONE")
