#!/usr/bin/env python3
"""Diagnostic-only b-bridge client variants. Never used in a release installer."""
import argparse
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--source", type=Path, required=True)
parser.add_argument("--variant", choices=("texture-forward", "shader-cache-only", "shader-forward"), required=True)
args = parser.parse_args()
s = args.source.read_text(encoding="utf-8")
check = "GlobalOptions::getEliminateRedundantSetterCalls()"
texture = "if (GlobalOptions::getEliminateRedundantSetterCalls() && m_state.textures[idx].get() == objectRef.get())"
float_shader = "if (GlobalOptions::getEliminateRedundantSetterCalls() && !m_stateRecording && std::memcmp(set.fConsts[startRegister].data, pConstantData, size) == 0)"
assert s.count(check) == 21, f"Unexpected optimization check count: {s.count(check)}"
assert s.count(texture) == 1, "Texture setter source changed"
assert s.count(float_shader) == 1, "Float shader setter source changed"
if args.variant == "texture-forward":
    # Keep redundancy elimination for every call EXCEPT SetTexture.
    s = s.replace(texture, texture.replace(check, "false"))
elif args.variant == "shader-cache-only":
    # Keep shader float constant caching, forward all other setters unconditionally.
    s = s.replace(check, "false")
    s = s.replace(float_shader.replace(check, "false"), float_shader)
elif args.variant == "shader-forward":
    # Keep all optimizations EXCEPT shader float constant caching.
    s = s.replace(float_shader, float_shader.replace(check, "false"))
assert s.count(check) == (20 if args.variant == "texture-forward" else (1 if args.variant == "shader-cache-only" else 20))
args.source.write_text(s, encoding="utf-8")
print(f"Patched {args.variant}: {s.count(check)} redundancy-elimination checks remain")
