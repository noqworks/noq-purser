#!/bin/bash
# The maintenance page's live data (purser-ui, read only): disk usage measured now while the disk
# is mounted, and the transfer card's numbers while the nightly job pulls or checks.
# The functions are called directly: status() would ask smartctl about the container's /dev/sda.
. /src/tests/lib/assert.sh
. /src/tests/lib/box.sh
lab_reset
first_night 2026-03-01T03-10Z
eq "first night taken" tamam "$(last)"
u0=$(cat /run/purser/work/used0 2>/dev/null)
ok "the night records the disk's used bytes as the transfer starts" grep -qE '^[0-9]+$' /run/purser/work/used0
ok "used0 is a real reading (more than 0, at most the disk)" test "${u0:-0}" -gt 0 -a "${u0:-0}" -le "$(sed -n 's/^total=//p' "$ST/disk.usage")"

F=/run/purser-test/ui; rm -rf "$F"; mkdir -p "$F/run/work" "$F/net/lab0/statistics" "$F/net/lab1/statistics"
py() {   # py <<< script: runs it with the installed purser-ui loaded as module "u"
  PURSER_NET_ROUTE=$F/route PURSER_NET_DIR=$F/net RUN_DIR=$F/run python3 -I - <<EOF
import importlib.machinery, importlib.util, json, os, sys, time
ld = importlib.machinery.SourceFileLoader("u", "/usr/local/sbin/purser-ui")
sp = importlib.util.spec_from_loader("u", ld); u = importlib.util.module_from_spec(sp); ld.exec_module(u)
$(cat)
EOF
}

# --- disk usage: recorded while the disk is locked, measured while it is mounted ---
ok "disk is locked after the night" locked
out=$(py <<'EOF'
d = u.disk_usage(u.conf()); print(d["live"], d["used"], d["at"])
EOF
)
eq "locked: the recorded value (disk.usage) with its time" \
  "False $(sed -n 's/^used=//p' "$ST/disk.usage") $(sed -n 's/^at=//p' "$ST/disk.usage")" "$out"
mount_disk
out=$(py <<'EOF'
d = u.disk_usage(u.conf()); print(d["live"], d["used"], d["total"])
EOF
)
eq "mounted: measured now, the same numbers as df" "True $(df -P -B1 "$M" | awk 'NR == 2 { print $3, $2 }')" "$out"
umount_disk

# --- the default-route interface ---
{ printf 'Iface\tDestination\tGateway\tFlags\tRefCnt\tUse\tMetric\tMask\n'
  printf 'lab1\t0000A8C0\t00000000\t0001\t0\t0\t0\t00FFFFFF\n'
  printf 'lab1\t00000000\t0100A8C0\t0003\t0\t0\t600\t00000000\n'
  printf 'lab0\t00000000\t0100A8C0\t0003\t0\t0\t100\t00000000\n'
  printf 'down0\t00000000\t0100A8C0\t0002\t0\t0\t1\t00000000\n'; } > "$F/route"
eq "default route: the lowest metric among routes that are up" lab0 "$(py <<<'print(u.default_iface())')"

# --- the transfer card ---
echo 1000000000 > "$F/net/lab0/statistics/rx_bytes"
touch -d '-125 seconds' "$F/run/work/t0"; echo 5000000000 > "$F/run/work/used0"
out=$(py <<'EOF'
rx = os.environ["PURSER_NET_DIR"] + "/lab0/statistics/rx_bytes"
def setrx(v): open(rx, "w").write("%d\n" % v)
live = lambda used: {"used": used, "total": 10**12, "live": True}
w = float(int(time.time()))   # whole seconds: ages add up exactly
print("ready", u.transfer("ready", live(6e9), 100.0, w))
t = u.transfer("pulling", live(7_000_000_000), 100.0, w)
print("first", t["phase"], t["rate"], t["rate_avg"], t["received"], t["since"], 124 <= t["elapsed_s"] <= 127, len(t["samples"]))
setrx(1_020_000_000)
t = u.transfer("pulling", live(7_000_000_000), 102.0, w + 2)
print("second", t["rate"], t["rate_avg"], t["samples"])
setrx(1_090_000_000)
t = u.transfer("pulling", live(7_000_000_000), 102.5, w + 2.5)
print("tooSoon", len(t["samples"]))
t = u.transfer("pulling", live(7_000_000_000), 104.0, w + 4)
print("avg", t["rate"], t["rate_avg"])
t = u.transfer("checking", live(4_000_000_000), 106.0, w + 6)
print("checking", t["phase"], t["received"])
setrx(5)
t = u.transfer("pulling", live(7_000_000_000), 108.0, w + 8)
print("counterReset", len(t["samples"]), t["rate"])
setrx(10_000_005)
t = u.transfer("pulling", live(7_000_000_000), 150.0, w + 50)
print("longGap", len(t["samples"]))
for i in range(1, 71):                     # 140 s of samples every 2 s at 1 MB/s
    setrx(10_000_005 + i * 2_000_000)
    t = u.transfer("pulling", live(7_000_000_000), 150.0 + 2 * i, w + 50 + 2 * i)
print("window", len(t["samples"]), max(a for a, _ in t["samples"]) <= 120, t["rate_avg"])
print("unmounted", u.transfer("pulling", {"used": 1, "total": 2, "live": False}, 401.5, w + 301.5)["received"])
os.utime(os.environ["RUN_DIR"] + "/work/t0", (w - 5, w - 5))
t = u.transfer("pulling", live(7_000_000_000), 403.0, w + 303)
print("newJob", len(t["samples"]), t["rate"])
os.remove(os.environ["RUN_DIR"] + "/work/used0"); os.utime(os.environ["RUN_DIR"] + "/work/t0", (w - 9, w - 9))
t = u.transfer("pulling", live(8_000_000_000), 405.0, w + 305)
print("seen", t["since"], t["received"], t["since_at"] == int(w + 305))
t = u.transfer("pulling", live(8_500_000_000), 407.0, w + 307)
print("seenLater", t["since"], t["received"])
os.remove(os.environ["RUN_DIR"] + "/work/t0")
print("noT0", u.transfer("pulling", live(9e9), 409.0, w + 309), u.transfer("checking", live(9e9), 410.0, w + 310))
json.dumps(t)
EOF
)
printf '%s\n' "$out" > "$LOGDIR/ui-transfer.txt"
line() { sed -n "s/^$1 //p" <<< "$out"; }
eq "no transfer data outside a job" None "$(line ready)"
eq "first sample: phase, no speed yet, received since used0, elapsed from t0" "pulling None None 2000000000 start True 0" "$(line first)"
eq "second sample: 20 MB in 2 s = 10 MB/s" "10000000 10000000 [[0.0, 10000000]]" "$(line second)"
eq "a request under 1 s after the last does not sample" 1 "$(line tooSoon)"
eq "speed 35 MB/s now, 22.5 MB/s over the last 10 s (time-weighted)" "35000000 22500000" "$(line avg)"
eq "checking: phase; received never below 0" "checking 0" "$(line checking)"
eq "a counter that goes back starts a new series" "0 None" "$(line counterReset)"
eq "a gap over 30 s (page closed) starts a new series" 0 "$(line longGap)"
eq "samples older than 2 minutes are dropped (61 kept at 2 s)" "61 True 1000000" "$(line window)"
eq "disk not mounted: no received figure" None "$(line unmounted)"
eq "a new job (t0 changes) forgets the last job's speed" "0 None" "$(line newJob)"
eq "no used0 (older core): counted from the first value this page saw" "seen 0 True" "$(line seen)"
eq "... and from there on" "seen 500000000" "$(line seenLater)"
eq "no t0 (transfer not begun, e.g. first-boot disk preparation shows checking): no card" "None None" "$(line noT0)"

# --- the page ---
ok "the page has the transfer card" grep -q 'id="aktarim"' /usr/local/lib/purser/ui/index.html
eq "transfer strings in Turkish and English" 2 "$(grep -c 'aktarim:"' /usr/local/lib/purser/ui/index.html)"
ok "the flow animation stops for reduced motion" grep -q 'prefers-reduced-motion:reduce.*' /usr/local/lib/purser/ui/index.html
done_testing
