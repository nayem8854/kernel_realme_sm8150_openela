#!/bin/bash
# Port A16/LOS23.2 eBPF+net stack from LineageOS android_kernel_oneplus_sm8150
# Usage:
#   REF=/path/to/android_kernel_oneplus_sm8150 ./scripts/port_ebpf_from_oneplus_sm8150.sh
set -euo pipefail
REF="${REF:-/tmp/ref_oneplus_sm8150}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
test -d "$REF/kernel/bpf" || { echo "missing REF=$REF"; exit 1; }

rsync -a --delete "$REF/kernel/bpf/" "$ROOT/kernel/bpf/"

FILES=(
  include/linux/bpf.h include/linux/bpf_types.h include/linux/bpf_verifier.h
  include/linux/bpf_trace.h include/linux/bpf-cgroup.h include/linux/bpf-netns.h
  include/linux/bpf_lsm.h include/linux/bpf_local_storage.h include/linux/bpf_lirc.h
  include/linux/bpfilter.h include/linux/btf.h include/linux/btf_ids.h
  include/linux/filter.h include/linux/cookie.h include/linux/error-injection.h
  include/linux/rcupdate_trace.h include/linux/lsm_hooks.h include/linux/security.h
  include/linux/cgroup.h include/linux/cgroup-defs.h
  include/linux/netdevice.h include/linux/skbuff.h include/linux/perf_event.h
  include/linux/tracepoint.h include/linux/net.h
  include/uapi/linux/bpf.h include/uapi/linux/bpf_common.h
  include/uapi/linux/bpf_perf_event.h include/uapi/linux/btf.h
  include/uapi/linux/if_xdp.h include/uapi/linux/xdp_diag.h include/uapi/linux/bpfilter.h
  include/uapi/linux/perf_event.h
  include/net/bpf_sk_storage.h include/net/xdp.h include/net/xdp_sock.h
  include/net/netns/bpf.h include/net/netns/xdp.h include/net/cls_cgroup.h
  include/net/page_pool.h include/net/sock.h include/net/tcp.h include/net/udp.h
  include/net/inet_connection_sock.h include/net/inet_sock.h include/net/inet_hashtables.h
  include/net/inet_common.h
  include/net/ip.h include/net/sch_generic.h include/net/flow_dissector.h
  include/net/net_namespace.h include/trace/bpf_probe.h include/trace/perf.h
  net/core/filter.c net/core/xdp.c net/core/sock_map.c net/core/bpf_sk_storage.c
  net/core/lwt_bpf.c net/core/sysctl_net_core.c net/core/Makefile
  net/core/skmsg.c net/core/sock_reuseport.c net/core/flow_dissector.c
  net/core/page_pool.c net/core/dev.c net/core/sock.c net/core/skbuff.c
  net/core/net_namespace.c
  net/sched/cls_bpf.c net/sched/act_bpf.c
  net/ipv4/tcp_bpf.c net/ipv4/bpf_tcp_ca.c net/ipv4/Makefile
  net/ipv4/af_inet.c net/ipv4/tcp.c net/ipv4/udp.c
  net/ipv4/tcp_output.c net/ipv4/tcp_input.c net/ipv4/syncookies.c
  net/ipv4/inet_connection_sock.c net/ipv4/tcp_minisocks.c net/ipv4/tcp_timer.c
  net/ipv6/af_inet6.c net/ipv6/tcp_ipv6.c
  net/netlink/af_netlink.c net/Makefile net/Kconfig
  net/bpfilter
  arch/arm64/net/bpf_jit_comp.c arch/arm64/net/bpf_jit.h
  kernel/trace/bpf_trace.c kernel/trace/Kconfig
  kernel/cgroup/cgroup.c kernel/sysctl.c kernel/events/core.c
  kernel/rcu/tasks.h
  init/Kconfig lib/Kconfig.debug
  security/security.c security/Makefile security/Kconfig security/bpf
  tools/include/uapi/linux/bpf.h tools/include/uapi/linux/bpf_common.h
)

for f in "${FILES[@]}"; do
  if [ -e "$REF/$f" ]; then
    mkdir -p "$(dirname "$ROOT/$f")"
    if [ -d "$REF/$f" ]; then
      rsync -a "$REF/$f/" "$ROOT/$f/"
    else
      cp -a "$REF/$f" "$ROOT/$f"
    fi
    echo "OK $f"
  else
    echo "SKIP $f"
  fi
done

echo "Done. Merge los23_a16_ebpf.config and set cmdline androidboot.selinux=permissive"
