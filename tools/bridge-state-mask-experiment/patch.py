#!/usr/bin/env python3
"""Diagnostic-only patch: toggle each of 21 b-bridge redundant-setter checks with a bitmask.

Run only against the exact pinned gutbash/b-bridge revision. Never used for releases.
bit N = bypass redundant setter suppression for the Nth check in source order.
"""
from pathlib import Path
import argparse

p=argparse.ArgumentParser()
p.add_argument("--source", type=Path, required=True)
args=p.parse_args()
s=args.source.read_text(encoding="utf-8")
old="GlobalOptions::getEliminateRedundantSetterCalls()"
assert s.count(old)==21, f"Expected 21 optimization checks, got {s.count(old)}"
anchor="#define GET_PRES_PARAM()"
assert s.count(anchor)==1, "Missing insertion marker"

# Evaluate once per client process; settings take effect on the NEXT game launch.
helper = """
// Diagnostic-only source patch: one bit per redundant setter check.
// clientRedundantBypassMask is a UINT32 decimal bitmask in bridge.conf.
// Bit 1 means do NOT omit that call, even when eliminateRedundantSetterCalls=True.
// Only the client reads this setting. Default zero preserves the pinned bridge behavior.
static inline bool BridgeSelectiveOptimizerEnabled(uint32_t site) {
  static const uint32_t bypassMask =
    bridge_util::Config::getOption<uint32_t>("clientRedundantBypassMask", 0);
  return GlobalOptions::getEliminateRedundantSetterCalls()
      && (bypassMask & (uint32_t(1) << site)) == 0;
}

"""
for n in range(21):
    assert old in s
    s=s.replace(old,f"BridgeSelectiveOptimizerEnabled({n})",1)
s=s.replace(anchor, helper+anchor,1)
assert s.count(old)==1, "Only the helper must still use the original getter"
assert s.count("BridgeSelectiveOptimizerEnabled(")==22
args.source.write_text(s,encoding="utf-8")
print("PASS: 21 redundant-state callsites patched, zero mask preserves original behavior")
for group,indices in {
 "transforms_lights":[0,1,2,3,4,5,6],
 "render_states":[7,8],
 "texture_and_sampler":[9,10,11,12,13],
 "shader_bindings_streams":[14,15,16,17,18,19],
 "float_shader_constants":[20],
}.items():
 print(f"{group}: mask={sum(1<<n for n in indices)} site_bits={indices}")
