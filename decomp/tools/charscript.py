#!/usr/bin/env python3
"""Parser for the character behaviour ('c') chunks in chara/charadata.arc.

The bytecode is executed by the ARM9 character VM at 0x02022A60 (jump table 0x02022ADC).
Instruction lengths below were extracted from each handler's `add r8, r8, #n`
(see decomp/notes/charvm_ops_disasm.md). Branch targets are u32 offsets from the
start of the 'c' chunk (VM adds fighter+0x44 = chunk base).

usage: charscript.py charadata_entry.bin [out.json]
"""
import json, struct, sys

# opcode -> length in bytes (fall-through length for conditional/branching ops)
OPLEN = {
    0x00: 10, 0x01: 2, 0x02: 6, 0x03: 8, 0x04: 66, 0x05: 6, 0x06: 10, 0x07: 10, 0x08: 2, 0x09: 2,
    0x0a: 2, 0x0b: 2, 0x0c: 2, 0x0d: 2, 0x0e: 8, 0x0f: 4, 0x10: 2, 0x11: 4, 0x12: 6, 0x13: 6,
    0x14: 2, 0x15: 6, 0x16: 4, 0x18: 2, 0x19: 6, 0x1a: 2, 0x1b: 2, 0x1c: 6, 0x1d: 4,
    0x1e: 6, 0x1f: 4, 0x20: 4, 0x21: 4, 0x22: 2, 0x23: 4, 0x24: 6, 0x25: 4, 0x26: 4, 0x27: 4,
    0x28: 2, 0x29: 2, 0x2a: 2, 0x2b: 4, 0x2c: 8, 0x2d: 2, 0x2e: 6, 0x2f: 4, 0x30: 4, 0x31: 4,
    0x32: 4, 0x33: 2, 0x34: 2, 0x35: 2, 0x36: 4, 0x37: 2, 0x38: 2, 0x39: 2, 0x3a: 10, 0x3b: 2,
    0x3c: 2, 0x3d: 14, 0x3e: 14, 0x3f: 8, 0x40: 2, 0x41: 14, 0x42: 2, 0x43: 6, 0x44: 2, 0x45: 6,
    0x46: 8, 0x47: 2, 0x48: 2, 0x49: 8, 0x4a: 8, 0x4b: 6, 0x4c: 6, 0x4d: 6, 0x4e: 6, 0x4f: 6,
    0x50: 4, 0x51: 2, 0x52: 2, 0x53: 2, 0x54: 6, 0x55: 6, 0x56: 6, 0x57: 4, 0x58: 4, 0x59: 8,
    0x5a: 10, 0x5b: 4, 0x5c: 8, 0x5d: 8, 0x5e: 6, 0x5f: 6, 0x60: 2, 0x63: 6, 0x64: 4,
    0x65: 4, 0x66: 8, 0x67: 6, 0x68: 6, 0x69: 4, 0x6a: 4, 0x6b: 4, 0x6c: 6, 0x6d: 2, 0x6e: 2,
    0x70: 4, 0x71: 6, 0x72: 4, 0x73: 10, 0x74: 4, 0x75: 2, 0x76: 8, 0x77: 8, 0x78: 14,
    0x79: 14, 0x7a: 6, 0x7b: 6, 0x7c: 6, 0x7d: 2, 0x7e: 2, 0x7f: 2, 0x80: 2, 0x81: 2, 0x82: 2,
    0x83: 2, 0x84: 6, 0x85: 14, 0x86: 2, 0x87: 6, 0x88: 6, 0x89: 2, 0x8a: 6, 0x8b: 6, 0x8c: 2,
    0x8d: 2, 0x8e: 6, 0x8f: 2, 0x90: 2, 0x91: 2, 0x92: 6,
}
# ops that never fall through
TERMINAL = {0x01, 0x04, 0x05}
# ops with a u32 branch target (taken path) -> byte offset of the target; fall-through is OPLEN
BRANCH32 = {0x05: 2, 0x12: 2, 0x45: 2, 0x4e: 2, 0x55: 2, 0x63: 2, 0x7a: 2, 0x7c: 2, 0x8e: 2, 0x92: 2,
            0x46: 4, 0x59: 4, 0x66: 4, 0x5a: 6, 0x73: 6}
# names for ops whose meaning is understood (H = verified in code)
NAMES = {
    0x00: "action_header", 0x01: "end_or_loop", 0x03: "show_frame", 0x04: "goto_by_direction",
    0x05: "goto", 0x12: "repeat_n", 0x2b: "wait_until_height", 0x33: "wait_flag40", 0x7b: "random_action",
}


def header(d):
    tag = d[:4].decode("latin-1")
    act_off, unk8, base_off = struct.unpack_from("<3I", d, 4)
    params = list(struct.unpack_from("<4I", d, 0x10))
    acts = []
    p = act_off
    while p + 4 <= len(d):
        v = struct.unpack_from("<I", d, p)[0]
        if v == 0xFFFFFFFF:
            break
        acts.append(v)
        p += 4
    return {"tag": tag, "action_table": act_off, "unk8": unk8, "script_base": base_off,
            "param_blocks": params, "actions": acts, "action_table_end": p}


def decode_op(d, p):
    op = d[p]
    n = OPLEN.get(op)
    if n is None:
        raise ValueError(f"bad opcode {op:#x} at {p:#x}")
    raw = d[p:p + n]
    ins = {"at": p, "op": op, "len": n, "hex": raw.hex()}
    if op in NAMES:
        ins["name"] = NAMES[op]
    if op == 0x03:
        ins["dirtable"] = struct.unpack_from("<I", raw, 2)[0]
        ins["frames"] = list(struct.unpack_from("<16H", d, ins["dirtable"]))
        ins["duration"] = struct.unpack_from("<H", raw, 6)[0]
    if op in BRANCH32:
        ins["target"] = struct.unpack_from("<I", raw, BRANCH32[op])[0]
    if op == 0x04:
        ins["targets"] = list(struct.unpack_from("<16I", raw, 2))
    if op == 0x01:
        ins["mode"] = raw[1]
    return ins


def disasm_from(d, start, seen, maxops=4000):
    """Linear-sweep one code path, queueing branch targets."""
    out, work = [], [start]
    while work:
        p = work.pop()
        while p not in seen and p < len(d) and len(out) < maxops:
            seen.add(p)
            ins = decode_op(d, p)
            out.append(ins)
            for t in [ins.get("target")] + ins.get("targets", []):
                if t:
                    work.append(t)
            if ins["op"] in TERMINAL:
                break
            p += ins["len"]
    return out


def parse(d):
    h = header(d)
    seen, code, errors = set(), {}, []
    for i, a in enumerate(h["actions"]):
        try:
            for ins in disasm_from(d, h["script_base"] + a, seen):
                code[ins["at"]] = ins
        except ValueError as e:
            errors.append(f"action {i}: {e}")
    return h, [code[k] for k in sorted(code)], errors


if __name__ == "__main__":
    d = open(sys.argv[1], "rb").read()
    h, code, errors = parse(d)
    print(h["tag"], "actions:", len(h["actions"]), "ops:", len(code), "errors:", len(errors))
    for e in errors[:20]:
        print("  ", e)
    if len(sys.argv) > 2:
        json.dump({"header": h, "code": code, "errors": errors}, open(sys.argv[2], "w"), indent=0)
