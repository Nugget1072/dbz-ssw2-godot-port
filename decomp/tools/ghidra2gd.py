#!/usr/bin/env python3
"""ghidra2gd: translate Ghidra-decompiled C (one function per chunk, from ghidra_DecompAll.java) into GDScript
that runs on an emulated DS memory image (PackedByteArray `M`, base 0x02000000, covering 0x02000000-0x027FFFFF).

Semantics preserved: C integer widths/signedness (values kept canonical per type), pointer arithmetic
scaling, memory layout (all structs stay byte-addressed at their DS addresses), indirect calls through a
dispatch table, literal-pool constants folded from arm9.bin.

usage: ghidra2gd.py FUNCS_JSON ARM9_BIN OUT_GD ADDR [ADDR ...] | --list file
Functions that cannot be translated are emitted as stubs that push_error() once, and listed in the report.
"""
import json, os, re, struct, sys
from pycparser import c_parser, c_ast
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "transpile"))
import image

BASE = 0x02000000
MEM_END = 0x02800000
TYPEDEFS = """
typedef unsigned char byte; typedef unsigned char uchar; typedef unsigned char undefined; typedef unsigned char undefined1;
typedef unsigned short ushort; typedef unsigned short undefined2; typedef unsigned int uint; typedef unsigned int undefined4;
typedef unsigned int undefined3; typedef unsigned long long undefined5; typedef unsigned long long undefined6;
typedef unsigned long long undefined7; typedef unsigned long long undefined8; typedef unsigned long ulong;
typedef long long longlong; typedef unsigned long long ulonglong; typedef int bool; typedef unsigned char code;
typedef unsigned int uint3; typedef unsigned short wchar_t; typedef unsigned int uintptr_t;
typedef unsigned long long uint5; typedef unsigned long long uint6; typedef unsigned long long uint7;
typedef int int3; typedef long long int5; typedef long long int6; typedef long long int7;
typedef signed char sbyte; typedef unsigned char uint1; typedef signed char int1;
"""
NAMES2T = {
    "char": ("int", 1, True), "signed char": ("int", 1, True), "unsigned char": ("int", 1, False),
    "byte": ("int", 1, False), "uchar": ("int", 1, False), "undefined": ("int", 1, False), "undefined1": ("int", 1, False),
    "bool": ("int", 1, False), "code": ("int", 1, False),
    "short": ("int", 2, True), "ushort": ("int", 2, False), "undefined2": ("int", 2, False), "unsigned short": ("int", 2, False),
    "wchar_t": ("int", 2, False),
    "int": ("int", 4, True), "long": ("int", 4, True), "uint": ("int", 4, False), "ulong": ("int", 4, False),
    "unsigned int": ("int", 4, False), "unsigned long": ("int", 4, False), "undefined4": ("int", 4, False),
    "undefined3": ("int", 4, False), "uint3": ("int", 4, False), "uintptr_t": ("int", 4, False),
    "longlong": ("int", 8, True), "long long": ("int", 8, True), "ulonglong": ("int", 8, False),
    "unsigned long long": ("int", 8, False), "undefined8": ("int", 8, False), "undefined5": ("int", 8, False),
    "undefined6": ("int", 8, False), "undefined7": ("int", 8, False),
    "uint5": ("int", 8, False), "uint6": ("int", 8, False), "uint7": ("int", 8, False),
    "sbyte": ("int", 1, True), "uint1": ("int", 1, False), "int1": ("int", 1, True),
    "int3": ("int", 4, True), "int5": ("int", 8, True), "int6": ("int", 8, True), "int7": ("int", 8, True),
    "void": ("void",), "float": ("int", 4, True), "double": ("int", 8, True),
}
INT = ("int", 4, True)
UINT = ("int", 4, False)


def ptr(t):
    return ("ptr", t)


def sidx(code, t):
    """pointer offsets are 32-bit two's complement: an unsigned 32-bit index such as -(n + 1) computed in uint
    (Ghidra types it unsigned) must step backwards, so it is sign-extended before scaling"""
    if t and t[0] == "int" and t[1] == 4 and not t[2]:
        return f"((({code}) + 0x80000000 & 0xFFFFFFFF) - 0x80000000)"
    return code


def is_ptr(t):
    return t[0] == "ptr"


def is_int(t):
    return t[0] == "int"


def sizeof(t):
    if t[0] == "int":
        return t[1]
    if t[0] == "ptr":
        return 4
    if t[0] == "arr":
        return t[2] * sizeof(t[1])
    return 1  # void


class Unsupported(Exception):
    pass


def type_from_decl(node):
    """pycparser type node -> our type tuple"""
    if isinstance(node, c_ast.TypeDecl):
        return type_from_decl(node.type)
    if isinstance(node, c_ast.IdentifierType):
        n = " ".join(node.names)
        if n not in NAMES2T:
            raise Unsupported("type " + n)
        return NAMES2T[n]
    if isinstance(node, c_ast.PtrDecl):
        return ptr(type_from_decl(node.type))
    if isinstance(node, c_ast.ArrayDecl):
        dim = int(node.dim.value, 0) if node.dim is not None else 0
        return ("arr", type_from_decl(node.type), dim)
    if isinstance(node, c_ast.FuncDecl):
        return ("func",)
    if isinstance(node, c_ast.Typename):
        return type_from_decl(node.type)
    raise Unsupported("decl " + type(node).__name__)


def promote(t):
    if t[0] == "int" and t[1] < 4:
        return INT
    return t


def arith(a, b):
    a, b = promote(a), promote(b)
    if a[1] == 8 or b[1] == 8:
        return ("int", 8, a[2] and b[2]) if a[1] == b[1] else (a if a[1] == 8 else b)
    if not a[2] or not b[2]:
        return UINT
    return INT


def wrap_expr(code, t):
    """make `code` canonical for integer type t"""
    if t[0] == "ptr":
        t = UINT
    if t[0] != "int":
        return code
    size, signed = t[1], t[2]
    if size >= 8:
        return code  # GDScript ints are 64-bit; 64-bit C values are used only for long multiplies here
    mask = (1 << (8 * size)) - 1
    if not signed:
        return f"(({code}) & 0x{mask:X})"
    half = 1 << (8 * size - 1)
    return f"((({code}) + 0x{half:X} & 0x{mask:X}) - 0x{half:X})"


WATCH = bool(os.environ.get("WATCH"))
ARM7 = os.environ.get("TARGET", "arm9") == "arm7"   # ARM7 binary: DSGame7 on DSCore7Base, every access dynamic
PROFILE = bool(os.environ.get("PROFILE"))   # debug build: calls and self time per function (DSCoreBase.prof_*)
TRACE = bool(os.environ.get("TRACE"))   # debug build: optional call trace at every function entry   # debug build: every RAM store goes through _st (write watchpoints)


class FuncTx:
    def __init__(self, tx, addr, name, src):
        self.tx = tx
        self.addr = addr
        self.name = name
        self.src = src
        self.vars = {}          # name -> type
        self.addr_taken = set()
        self.mem_locals = {}    # name -> (offset, type) in the frame
        self.frame = 0
        self.lines = []
        self.tmp = 0
        self.globals = {}
        self.labels = []
        self.loop_stack = []    # 'loop' / 'switch'
        self.tainted = set()
        self.const_assign = {}          # variable -> constants assigned to it (indirect call targets)
        self.dynamic = addr in tx.dyn   # all computed addresses dispatched at run time (receives IO pointers)

    # ------------------------------------------------------------- helpers
    def newtmp(self):
        self.tmp += 1
        return f"_t{self.tmp}"

    def emit(self, ind, s):
        self.lines.append("\t" * ind + s)

    # ------------------------------------------------------------- memory access code
    def const_value(self, node):
        """constant-fold simple integer expressions (literals, DAT constants); None if not constant"""
        if isinstance(node, c_ast.Constant):
            return self.literal(node)[0]
        if isinstance(node, c_ast.ID) and node.name.startswith("DAT_"):
            a = int(node.name[4:], 16)
            if self.tx.is_const_pool(a):
                return self.tx.word(a)
        if isinstance(node, c_ast.Cast):
            return self.const_value(node.expr)
        if isinstance(node, c_ast.BinaryOp) and node.op in "+-":
            l, r = self.const_value(node.left), self.const_value(node.right)
            if l is not None and r is not None:
                return (l + r) if node.op == "+" else (l - r)
        return None

    def is_tainted_strict(self, code):
        return bool(self.tainted) and any(re.search(r"\b" + re.escape(n) + r"\b", code) for n in self.tainted)

    IO_LIT = re.compile(r"\b0x(?:[4-7]|1FF)[0-9A-F]{6}\b")

    def is_tainted(self, code):
        if self.dynamic or self.IO_LIT.search(code):
            return True
        return bool(self.tainted) and any(re.search(r"\b" + re.escape(n) + r"\b", code) for n in self.tainted)

    def mem_read(self, addr_code, t, const_addr=None):
        if ARM7:   # the ARM7 memory map (mirrors, WRAM, its own IO) is resolved at run time by DSCore7Base
            if t[0] == "ptr":
                t = UINT
            return f"_ld({addr_code}, {t[1]}, {'true' if t[2] else 'false'})"
        if const_addr is not None and not (BASE <= const_addr < MEM_END):
            return f"io_read({addr_code}, {sizeof(t)})" if not (t[0] == "int" and t[2]) else \
                wrap_expr(f"io_read({addr_code}, {sizeof(t)})", t)
        if t[0] == "ptr":
            t = UINT
        sz, sg = t[1], t[2]
        if const_addr is None and self.is_tainted(addr_code):
            return f"_ld({addr_code}, {sz}, {'true' if sg else 'false'})"
        fn = {(1, False): "decode_u8", (1, True): "decode_s8", (2, False): "decode_u16", (2, True): "decode_s16",
              (4, False): "decode_u32", (4, True): "decode_s32", (8, False): "decode_s64", (8, True): "decode_s64"}[(sz, sg)]
        return f"M.{fn}({addr_code} - 0x2000000)"

    def mem_write(self, addr_code, t, val_code, const_addr=None):
        if ARM7:
            if t[0] == "ptr":
                t = UINT
            return f"_st({addr_code}, {t[1]}, {val_code})"
        if const_addr is not None and not (BASE <= const_addr < MEM_END):
            return f"io_write({addr_code}, {sizeof(t)}, {val_code})"
        if t[0] == "ptr":
            t = UINT
        if const_addr is None and self.is_tainted(addr_code):
            return f"_st({addr_code}, {t[1]}, {val_code})"
        if WATCH:
            return f"_st({addr_code}, {t[1]}, {val_code})"
        fn = {1: "encode_u8", 2: "encode_u16", 4: "encode_u32", 8: "encode_s64"}[t[1]]
        if t[1] < 8:
            m = (1 << (8 * t[1])) - 1
            val_code = f"({val_code}) & 0x{m:X}"
        return f"M.{fn}({addr_code} - 0x2000000, {val_code})"

    # ------------------------------------------------------------- expressions
    def literal(self, node):
        if node.type in ("char",):
            s = node.value[1:-1]
            if s.startswith("\\x"):
                return int(s[2:], 16), INT
            if s.startswith("\\") and len(s) > 1:
                esc = {"0": 0, "n": 10, "t": 9, "r": 13, "\\": 92, "'": 39, "a": 7, "b": 8, "f": 12, "v": 11, '"': 34}
                if s[1] in esc and len(s) == 2:
                    return esc[s[1]], INT
                return int(s[1:], 8), INT
            return ord(s), INT
        if node.type == "string":
            raise Unsupported("string literal")
        v = node.value.rstrip("uUlL")
        val = int(v, 0) if not (v.startswith("0") and len(v) > 1 and v[1] not in "xX") else int(v, 8)
        unsigned = "u" in node.value.lower() or val > 0x7FFFFFFF
        if val > 0xFFFFFFFF:
            return val, ("int", 8, not unsigned)
        return val, (UINT if unsigned else INT)

    def lvalue(self, node):
        """returns ('var', name, type) or ('mem', addr_code, type, const_addr)"""
        if isinstance(node, c_ast.ID):
            n = node.name
            if n in self.mem_locals:
                off, t = self.mem_locals[n]
                return ("mem", f"(_fp + {off})", t, None)
            if n in self.vars:
                return ("var", n, self.vars[n])
            if n.startswith("DAT_"):
                a = int(n[4:], 16)
                t = self.global_type(n)
                return ("mem", f"0x{a:X}", t, a)
            raise Unsupported("unknown lvalue " + n)
        if isinstance(node, c_ast.UnaryOp) and node.op == "*":
            code, t = self.expr(node.expr)
            if not is_ptr(t):
                raise Unsupported("deref non-pointer")
            ca = self.const_value(node.expr)
            return ("mem", code, t[1], ca)
        if isinstance(node, c_ast.ArrayRef):
            base, bt = self.expr(node.name)
            idx, it = self.expr(node.subscript)
            el = bt[1] if bt[0] in ("ptr", "arr") else None
            if el is None:
                raise Unsupported("index non-pointer")
            sz = sizeof(el)
            idx = sidx(idx, it)
            return ("mem", f"({base} + ({idx}) * {sz})" if sz != 1 else f"({base} + ({idx}))", el, None)
        if isinstance(node, c_ast.StructRef):
            # Ghidra partial access var._OFF_SIZE_ (little endian byte offset / size)
            m = re.match(r"_(\d+)_(\d+)_$", node.field.name)
            if not m:
                raise Unsupported("lvalue StructRef")
            off, sz = int(m.group(1)), int(m.group(2))
            pt = ("int", sz, False)
            base = self.lvalue(node.name)
            if base[0] == "mem":
                return ("mem", f"({base[1]} + {off})", pt, None if base[3] is None else base[3] + off)
            if base[0] == "var":
                return ("part", base[1], pt, off, base[2])
            raise Unsupported("nested partial lvalue")
        raise Unsupported("lvalue " + type(node).__name__)

    def global_type(self, name):
        tn = self.globals.get(name)
        if tn is None:
            return UINT
        stars = tn.count("*")
        base = tn.replace("*", "").strip()
        t = NAMES2T.get(base, UINT)
        if t == ("void",):
            t = ("int", 1, False)
        for _ in range(stars):
            t = ptr(t)
        return t

    def expr(self, node):
        """-> (code, type). Code has no side effects (side effects are hoisted by stmt_expr)."""
        if isinstance(node, c_ast.Constant):
            v, t = self.literal(node)
            if v >= 1 << 63:
                return f"(-0x{(1 << 64) - v:X})", t
            return (str(v) if v < 10 else f"0x{v:X}"), t
        if isinstance(node, c_ast.ID):
            n = node.name
            if n in self.mem_locals:
                off, t = self.mem_locals[n]
                if t[0] == "arr":
                    return f"(_fp + {off})", ptr(t[1])
                return self.mem_read(f"(_fp + {off})", t), t
            if n in self.vars:
                t = self.vars[n]
                if t[0] == "arr":
                    raise Unsupported("array var not in memory")
                return n, t
            if n == "register0x00000054":   # sp
                return "_sp", UINT
            if n.startswith("DAT_"):
                a = int(n[4:], 16)
                t = self.global_type(n)
                if self.tx.is_const_pool(a):
                    v = self.tx.word(a)
                    if t[0] == "int" and t[1] < 4:
                        v &= (1 << (8 * t[1])) - 1
                    if t[0] == "int" and t[2] and t[1] <= 4 and v >= 1 << (8 * min(t[1], 4) - 1):
                        return f"({v - (1 << (8 * min(t[1], 4)))})", t   # signed literal-pool constant (e.g. -723)
                    return f"0x{v:X}", t
                return self.mem_read(f"0x{a:X}", t, a), t
            if n.startswith("FUN_") or n.startswith("LAB_"):
                return f"0x{int(n[4:], 16):X}", ptr(("int", 1, False))
            if n in ("true", "false"):
                return ("1" if n == "true" else "0"), INT
            raise Unsupported("unknown id " + n)
        if isinstance(node, c_ast.Cast):
            code, t = self.expr(node.expr)
            to = type_from_decl(node.to_type)
            if to == ("void",):
                return code, INT
            return self.convert(code, t, to), to
        if isinstance(node, c_ast.UnaryOp):
            op = node.op
            if op == "*":
                lv = self.lvalue(node)
                return self.mem_read(lv[1], lv[2], lv[3]), lv[2]
            if op == "&":
                inner = node.expr
                if isinstance(inner, c_ast.ID):
                    if inner.name in self.mem_locals:
                        off, t = self.mem_locals[inner.name]
                        return f"(_fp + {off})", ptr(t if t[0] != "arr" else t[1])
                    if inner.name.startswith("DAT_"):
                        if inner.name in self.byte_globals:
                            return f"0x{int(inner.name[4:], 16):X}", ptr(("int", 1, False))
                        return f"0x{int(inner.name[4:], 16):X}", ptr(self.global_type(inner.name))
                    if inner.name.startswith("FUN_") or inner.name.startswith("LAB_"):
                        return f"0x{int(inner.name[4:], 16):X}", ptr(("int", 1, False))
                    raise Unsupported("address of register var " + inner.name)
                lv = self.lvalue(inner)
                if lv[0] != "mem":
                    raise Unsupported("&var")
                return lv[1], ptr(lv[2])
            if op == "-":
                c, t = self.expr(node.expr)
                t = promote(t)
                return wrap_expr(f"-({c})", t), t
            if op == "~":
                c, t = self.expr(node.expr)
                t = promote(t)
                return wrap_expr(f"~({c})", t), t
            if op == "!":
                c, t = self.cond(node.expr)
                return f"(0 if {c} else 1)", INT
            if op == "sizeof":
                raise Unsupported("sizeof")
            if op in ("p++", "p--", "++", "--"):
                raise Unsupported("inc in expr")
            raise Unsupported("unary " + op)
        if isinstance(node, c_ast.BinaryOp):
            op = node.op
            if op in ("&&", "||"):
                a, _ = self.cond(node.left)
                b, _ = self.cond(node.right)
                return f"(1 if ({a} {'and' if op == '&&' else 'or'} {b}) else 0)", INT
            l, lt = self.expr(node.left)
            r, rt = self.expr(node.right)
            if op in ("==", "!=", "<", ">", "<=", ">="):
                return f"(1 if ({l} {op} {r}) else 0)", INT
            # pointer arithmetic
            if op in ("+", "-") and (is_ptr(lt) or lt[0] == "arr" or is_ptr(rt) or rt[0] == "arr"):
                if lt[0] == "arr":
                    lt = ptr(lt[1])
                if rt[0] == "arr":
                    rt = ptr(rt[1])
                if is_ptr(lt) and is_ptr(rt):
                    sz = sizeof(lt[1]) or 1
                    return f"(({l}) - ({r})) / {sz}", INT
                if is_ptr(rt):
                    l, lt, r, rt = r, rt, l, lt
                sz = sizeof(lt[1]) if lt[1][0] != "void" else 1
                r = sidx(r, rt)
                scaled = f"({r}) * {sz}" if sz != 1 else f"({r})"
                return f"(({l}) {op} {scaled})", lt
            t = arith(lt, rt)
            if op in ("<<", ">>"):
                t = promote(lt)
                if self.const_value(node.right) is None:
                    # register shift amounts can reach 255 (ARM: >= 32 gives 0 / the sign); GDScript ints are 64-bit
                    # and the host masks the count to 6 bits, so clamp: <<63 then the 32-bit wrap = 0, >>63 = 0/-1
                    r = f"clampi({r}, 0, 63)"
                if op == ">>":
                    return f"(({l}) >> ({r}))", t
                return wrap_expr(f"({l}) << ({r})", t), t
            if op == "/":
                return f"_div({l}, {r})", t
            if op == "%":
                return f"_mod({l}, {r})", t
            if op in ("&", "|", "^"):
                code = f"(({l}) {op} ({r}))"
                # both canonical non-negative or sign-consistent: & | ^ of signed values stays in range
                if t[2] or op == "&":
                    return code, t
                return wrap_expr(code, t), t
            if op in ("+", "-", "*"):
                small = promote(lt) == INT and promote(rt) == INT and lt[0] == "int" and rt[0] == "int" \
                    and lt[1] <= 2 and rt[1] <= 2 and op != "*"
                code = f"({l}) {op} ({r})"
                return (f"({code})" if small else wrap_expr(code, t)), t
            raise Unsupported("binop " + op)
        if isinstance(node, c_ast.ArrayRef):
            lv = self.lvalue(node)
            return self.mem_read(lv[1], lv[2], lv[3]), lv[2]
        if isinstance(node, c_ast.StructRef):
            m = re.match(r"_(\d+)_(\d+)_$", node.field.name)
            if not m:
                raise Unsupported("expr StructRef")
            off, sz = int(m.group(1)), int(m.group(2))
            pt = ("int", sz, False)
            try:
                lv = self.lvalue(node)
            except Unsupported:
                lv = None
            if lv is not None and lv[0] == "mem":
                return self.mem_read(lv[1], lv[2], lv[3]), pt
            c, _ = self.expr(node.name)
            return f"((({c}) >> {8 * off}) & 0x{(1 << (8 * sz)) - 1:X})", pt
        if isinstance(node, c_ast.TernaryOp):
            c, _ = self.cond(node.cond)
            a, at = self.expr(node.iftrue)
            b, bt = self.expr(node.iffalse)
            return f"({a} if {c} else {b})", at
        if isinstance(node, c_ast.FuncCall):
            raise Unsupported("call inside expression (should be hoisted)")
        if isinstance(node, c_ast.Assignment):
            raise Unsupported("assignment inside expression (should be hoisted)")
        if isinstance(node, c_ast.ExprList):
            raise Unsupported("comma expression")
        raise Unsupported("expr " + type(node).__name__)

    def convert(self, code, frm, to):
        if to[0] == "arr":
            to = ptr(to[1])
        if frm[0] == "arr":
            frm = ptr(frm[1])
        f2 = UINT if frm[0] == "ptr" else frm
        t2 = UINT if to[0] == "ptr" else to
        if f2[0] != "int" or t2[0] != "int":
            return code
        if t2[1] > f2[1] and (not f2[2] or t2[2]):
            return code  # widening, value fits
        if t2 == f2:
            return code
        return wrap_expr(code, t2)

    def cond(self, node):
        """condition -> (gdscript boolean code, type)"""
        if isinstance(node, c_ast.BinaryOp) and node.op in ("==", "!=", "<", ">", "<=", ">="):
            l, lt = self.expr(node.left)
            r, rt = self.expr(node.right)
            # compare in C semantics: if one side unsigned 32 and other signed negative constant, convert
            t = arith(lt if lt[0] == "int" else UINT, rt if rt[0] == "int" else UINT)
            if t[0] == "int" and not t[2]:
                if lt[0] == "int" and lt[2]:
                    l = wrap_expr(l, ("int", max(4, t[1]), False))
                if rt[0] == "int" and rt[2]:
                    r = wrap_expr(r, ("int", max(4, t[1]), False))
            return f"({l} {node.op} {r})", INT
        if isinstance(node, c_ast.BinaryOp) and node.op in ("&&", "||"):
            a, _ = self.cond(node.left)
            b, _ = self.cond(node.right)
            return f"({a} {'and' if node.op == '&&' else 'or'} {b})", INT
        if isinstance(node, c_ast.UnaryOp) and node.op == "!":
            a, _ = self.cond(node.expr)
            return f"(not {a})", INT
        c, t = self.expr(node)
        return f"({c} != 0)", INT

    # ------------------------------------------------------------- side-effect lowering
    def has_side_effects(self, node):
        found = []

        class V(c_ast.NodeVisitor):
            def visit_FuncCall(s, n): found.append(n)
            def visit_Assignment(s, n): found.append(n)
            def visit_ExprList(s, n): found.append(n)

            def visit_UnaryOp(s, n):
                if n.op in ("p++", "p--", "++", "--"):
                    found.append(n)
                s.generic_visit(n)
        V().visit(node)
        return bool(found)

    def lower(self, node, ind):
        """Evaluate side effects of `node` into statements; return a side-effect-free AST node standing for its value."""
        if isinstance(node, c_ast.FuncCall):
            res = self.call(node, ind)
            tname = self.newtmp()
            self.vars[tname] = res[1]
            self.emit(ind, f"{tname} = {res[0]}")
            return c_ast.ID(tname)
        if isinstance(node, c_ast.Assignment):
            self.assign(node, ind)
            return node.lvalue
        if isinstance(node, c_ast.ExprList):
            for e in node.exprs[:-1]:
                self.stmt_expr(e, ind)
            return self.lower(node.exprs[-1], ind)
        if isinstance(node, c_ast.BinaryOp) and node.op in ("&&", "||") and self.has_side_effects(node.right):
            # short-circuit with side effects on the right: materialise into a temp
            tname = self.newtmp()
            self.vars[tname] = INT
            left = self.lower(node.left, ind)
            lc, _ = self.cond(left)
            self.emit(ind, f"{tname} = 1 if {lc} else 0")
            self.emit(ind, f"if {'' if node.op == '&&' else 'not '}{tname}:")
            n0 = len(self.lines)
            right = self.lower(node.right, ind + 1)
            rc, _ = self.cond(right)
            self.emit(ind + 1, f"{tname} = 1 if {rc} else 0")
            return c_ast.ID(tname)
        if isinstance(node, c_ast.UnaryOp) and node.op in ("p++", "p--"):
            tname = self.newtmp()
            c, t = self.expr(node.expr)
            self.vars[tname] = t
            self.emit(ind, f"{tname} = {c}")
            self.assign(c_ast.Assignment("+=" if node.op == "p++" else "-=", node.expr, c_ast.Constant("int", "1")), ind)
            return c_ast.ID(tname)
        if isinstance(node, c_ast.UnaryOp) and node.op in ("++", "--"):
            self.assign(c_ast.Assignment("+=" if node.op == "++" else "-=", node.expr, c_ast.Constant("int", "1")), ind)
            return node.expr
        # recurse into children
        for attr in ("left", "right", "expr", "cond", "iftrue", "iffalse", "name", "subscript"):
            if hasattr(node, attr) and getattr(node, attr) is not None and isinstance(getattr(node, attr), c_ast.Node):
                child = getattr(node, attr)
                if self.has_side_effects(child):
                    setattr(node, attr, self.lower(child, ind))
        return node

    def call(self, node, ind):
        args = []
        if node.args:
            for a in node.args.exprs:
                a2 = self.lower(a, ind) if self.has_side_effects(a) else a
                args.append(self.expr(a2)[0])
        fn = node.name
        while isinstance(fn, c_ast.Cast):
            fn = fn.expr
        if isinstance(fn, c_ast.ID):
            n = fn.name
            if n.startswith("FUN_"):
                a = int(n[4:], 16)
                self.tx.called.add(a)
                for an, ac in zip(node.args.exprs if node.args else [], args):
                    cv = self.const_value(an)
                    if (cv is not None and (cv & 0xFFFFFFFF) >= 0x01000000 and not (BASE <= (cv & 0xFFFFFFFF) < MEM_END)) \
                            or (self.dynamic and re.search(r"\bparam_\d+\b", ac)) or self.is_tainted_strict(ac) \
                            or self.IO_LIT.search(ac):
                        self.tx.dyn_req.add(a)
                return f"{self.tx.fname(a)}({', '.join(args)})", self.tx.ret_type(a)
            if n == "UNRECOVERED_JUMPTABLE":
                return f"_unrecovered(0x{self.addr:X})", UINT
            m = re.match(r"SUB(\d)(\d)$", n)
            if m:   # SUBxy(v, c): bytes c.. of an x-byte value, truncated to y bytes
                c = self.const_value(node.args.exprs[1])
                return f"((({args[0]}) >> {8 * c}) & 0x{(1 << (8 * int(m.group(2)))) - 1:X})", ("int", int(m.group(2)), False)
            m = re.match(r"(ZEXT|SEXT)(\d)(\d)$", n)
            if m:
                fr, to = int(m.group(2)), int(m.group(3))
                t = ("int", fr, m.group(1) == "SEXT")
                return wrap_expr(args[0], t), ("int", to, m.group(1) == "SEXT")
            m = re.match(r"CONCAT(\d)(\d)$", n)
            if m and n not in self.tx.intrinsics:   # CONCATxy(hi, lo): x-byte hi above y-byte lo
                hx, ly = int(m.group(1)), int(m.group(2))
                return (f"((({args[0]}) & 0x{(1 << (8 * hx)) - 1:X}) << {8 * ly} | (({args[1]}) & 0x{(1 << (8 * ly)) - 1:X}))",
                        ("int", 8 if hx + ly > 4 else 4, False))
            if n.startswith("coproc_"):   # cache / write-buffer maintenance: no effect on the port
                return "0", UINT
            if n in self.tx.intrinsics:
                return f"{n}({', '.join(args)})", UINT
            if n in self.vars or n.startswith("DAT_") or n in self.mem_locals:
                targets = set(self.const_assign.get(n, ()))
                if n.startswith("DAT_"):
                    cv = self.const_value(fn)
                    if cv is not None:
                        targets.add(cv & 0xFFFFFFFE)
                for a in targets:
                    for an, ac in zip(node.args.exprs if node.args else [], args):
                        cv = self.const_value(an)
                        if (cv is not None and (cv & 0xFFFFFFFF) >= 0x01000000 and not (BASE <= (cv & 0xFFFFFFFF) < MEM_END)) \
                                or (self.dynamic and re.search(r"\bparam_\d+\b", ac)) or self.is_tainted_strict(ac) \
                                or self.IO_LIT.search(ac):
                            self.tx.dyn_req.add(a)
                c, _ = self.expr(fn)
                return f"_icall({c}{', ' if args else ''}{', '.join(args)})", UINT
            raise Unsupported("call to " + n)
        if isinstance(fn, c_ast.UnaryOp) and fn.op == "*":
            c, _ = self.expr(fn.expr)
            return f"_icall({c}{', ' if args else ''}{', '.join(args)})", UINT
        raise Unsupported("call form")

    def assign(self, node, ind):
        rhs = node.rvalue
        if self.has_side_effects(rhs):
            if isinstance(rhs, c_ast.FuncCall):
                code, rt = self.call(rhs, ind)
            else:
                rhs = self.lower(rhs, ind)
                code, rt = self.expr(rhs)
        else:
            code, rt = self.expr(rhs)
        lv = self.lvalue(node.lvalue)
        lt = lv[2]
        if node.op != "=":
            op = node.op[:-1]
            cur = self.expr(node.lvalue)
            fake = c_ast.BinaryOp(op, node.lvalue, c_ast.ID("__rhs__"))
            self.vars["__rhs__"] = rt
            tmp_code = code
            bcode, bt = self.expr(fake)
            bcode = bcode.replace("__rhs__", f"({tmp_code})")
            del self.vars["__rhs__"]
            code, rt = bcode, bt
        val = self.convert(code, rt, lt)
        if lv[0] == "var":
            self.emit(ind, f"{lv[1]} = {val}")
        elif lv[0] == "part":
            _, name, pt, off, vt = lv
            m = (1 << (8 * pt[1])) - 1
            sh = 8 * off
            merged = f"(({name}) & ~0x{m << sh:X}) | ((({val}) & 0x{m:X}) << {sh})"
            self.emit(ind, f"{name} = {wrap_expr(merged, vt) if vt[0] == 'int' else merged}")
        else:
            self.emit(ind, self.mem_write(lv[1], lt, val, lv[3]))

    def stmt_expr(self, node, ind):
        if isinstance(node, c_ast.Assignment):
            self.assign(node, ind)
        elif isinstance(node, c_ast.FuncCall):
            self.emit(ind, self.call(node, ind)[0])
        elif isinstance(node, c_ast.UnaryOp) and node.op in ("p++", "p--", "++", "--"):
            self.assign(c_ast.Assignment("+=" if node.op in ("p++", "++") else "-=", node.expr,
                                         c_ast.Constant("int", "1")), ind)
        elif isinstance(node, c_ast.ExprList):
            for e in node.exprs:
                self.stmt_expr(e, ind)
        else:
            if self.has_side_effects(node):
                self.lower(node, ind)
            # pure expression statement: drop

    # ------------------------------------------------------------- statements
    def void_return(self, ind):
        """`return;` in a function Ghidra typed void. On ARM r0 still holds whatever the last call returned,
        and for tail calls (b/bx to another function) that value IS the caller-visible result, so a call
        immediately before the return passes its value through."""
        rv = "0"
        if self.lines:
            last = self.lines[-1]
            body = last.lstrip("\t")
            if len(last) - len(body) == ind and re.match(r"(f_[0-9a-f]{8}|_icall|_hle)\(", body):
                tname = self.newtmp()
                self.lines[-1] = "\t" * ind + f"{tname} = {body}"
                rv = tname
        if self.frame:
            self.emit(ind, "_sp = _fp")
        self.emit(ind, f"return {rv}")

    def block(self, node, ind):
        n0 = len(self.lines)
        items = node.block_items if isinstance(node, c_ast.Compound) else [node]
        for it in items or []:
            self.stmt(it, ind)
        if len(self.lines) == n0:
            self.emit(ind, "pass")

    def cond_stmt(self, node, ind):
        if self.has_side_effects(node):
            node = self.lower(node, ind)
        return self.cond(node)[0]

    def ends_flow(self, stmts):
        if not stmts:
            return False
        last = stmts[-1]
        return isinstance(last, (c_ast.Break, c_ast.Return, c_ast.Goto, c_ast.Continue))

    def stmt(self, node, ind):
        if isinstance(node, c_ast.Decl):
            return  # handled up front
        if isinstance(node, (c_ast.Assignment, c_ast.FuncCall, c_ast.UnaryOp, c_ast.ExprList, c_ast.BinaryOp,
                             c_ast.Cast, c_ast.ID, c_ast.Constant)):
            self.stmt_expr(node, ind)
        elif isinstance(node, c_ast.Compound):
            self.block(node, ind)
        elif isinstance(node, c_ast.If):
            c = self.cond_stmt(node.cond, ind)
            self.emit(ind, f"if {c}:")
            self.block(node.iftrue, ind + 1)
            if node.iffalse is not None:
                self.emit(ind, "else:")
                self.block(node.iffalse, ind + 1)
        elif isinstance(node, c_ast.While):
            if self.has_side_effects(node.cond):
                self.emit(ind, "while true:")
                c = self.cond_stmt(node.cond, ind + 1)
                self.emit(ind + 1, f"if not {c}:")
                self.emit(ind + 2, "break")
            else:
                self.emit(ind, f"while {self.cond(node.cond)[0]}:")
            self.loop_stack.append(("loop", None))
            self.block(node.stmt, ind + 1)
            self.loop_stack.pop()
        elif isinstance(node, c_ast.DoWhile):
            self.emit(ind, "while true:")
            self.loop_stack.append(("do", node.cond))
            self.block(node.stmt, ind + 1)
            self.loop_stack.pop()
            c = self.cond_stmt(node.cond, ind + 1)
            self.emit(ind + 1, f"if not {c}:")
            self.emit(ind + 2, "break")
        elif isinstance(node, c_ast.For):
            if node.init is not None:
                if isinstance(node.init, c_ast.DeclList):
                    raise Unsupported("for decl")
                self.stmt_expr(node.init, ind)
            self.emit(ind, "while true:")
            if node.cond is not None:
                c = self.cond_stmt(node.cond, ind + 1)
                self.emit(ind + 1, f"if not {c}:")
                self.emit(ind + 2, "break")
            self.loop_stack.append(("for", node.next))
            self.block(node.stmt, ind + 1)
            self.loop_stack.pop()
            if node.next is not None:
                self.stmt_expr(node.next, ind + 1)
        elif isinstance(node, c_ast.Switch):
            self.switch(node, ind)
        elif isinstance(node, c_ast.Break):
            self.emit(ind, "break")
        elif isinstance(node, c_ast.Continue):
            # find innermost real loop; through switch wrappers use flag
            kinds = [k for k, _ in self.loop_stack]
            inner = self.loop_stack[-1] if self.loop_stack else None
            if inner and inner[0] == "switch":
                raise Unsupported("continue inside switch")
            if inner and inner[0] == "for" and inner[1] is not None:
                self.stmt_expr(inner[1], ind)
            if inner and inner[0] == "do":
                c = self.cond_stmt(inner[1], ind)
                self.emit(ind, f"if not {c}:")
                self.emit(ind + 1, "break")
            self.emit(ind, "continue")
        elif isinstance(node, c_ast.Return):
            if node.expr is not None:
                e = node.expr
                if self.has_side_effects(e):
                    e = self.lower(e, ind)
                c, t = self.expr(e)
                rv = self.convert(c, t, self.ret_type) if self.ret_type[0] == 'int' else c
                if self.frame:
                    tname = self.newtmp()
                    self.emit(ind, f"{tname} = {rv}")
                    self.emit(ind, "_sp = _fp")
                    rv = tname
                self.emit(ind, f"return {rv}")
            else:
                self.void_return(ind)
        elif isinstance(node, c_ast.Label):
            raise Unsupported("label/goto")
        elif isinstance(node, c_ast.Goto):
            raise Unsupported("label/goto")
        elif isinstance(node, c_ast.EmptyStatement):
            pass
        else:
            raise Unsupported("stmt " + type(node).__name__)

    def switch(self, node, ind):
        val = self.cond_stmt(node.cond, ind) if False else None
        e = node.cond
        if self.has_side_effects(e):
            e = self.lower(e, ind)
        code, _ = self.expr(e)
        items = node.stmt.block_items or []
        # group: list of (labels, stmts); default label = None
        groups = []
        cur_labels, cur_stmts = [], []

        def flush():
            if cur_labels:
                groups.append((list(cur_labels), list(cur_stmts)))

        for it in items:
            if isinstance(it, (c_ast.Case, c_ast.Default)):
                # nested case labels: case A: case B: stmt
                labels = []
                n = it
                while isinstance(n, (c_ast.Case, c_ast.Default)):
                    labels.append(None if isinstance(n, c_ast.Default) else n.expr)
                    stmts = n.stmts or []
                    if len(stmts) == 1 and isinstance(stmts[0], (c_ast.Case, c_ast.Default)):
                        n = stmts[0]
                        continue
                    break
                if cur_labels and not cur_stmts:
                    cur_labels += labels
                    cur_stmts = list(stmts)
                else:
                    flush()
                    cur_labels, cur_stmts = labels, list(stmts)
            else:
                cur_stmts.append(it)
        flush()
        # resolve fallthrough by appending following groups' statements
        full = []
        for i, (labels, stmts) in enumerate(groups):
            body = list(stmts)
            j = i
            while not self.ends_flow(body) and j + 1 < len(groups):
                j += 1
                body += groups[j][1]
            full.append((labels, body))
        sv = self.newtmp()
        self.vars[sv] = INT
        self.emit(ind, f"{sv} = {code}")
        self.emit(ind, "while true:")
        self.loop_stack.append(("switch", None))
        first = True
        default_body = None
        for labels, body in full:
            if None in labels:
                default_body = body
                labels = [l for l in labels if l is not None]
                if not labels:
                    continue
            conds = []
            for l in labels:
                lc, _ = self.expr(l)
                conds.append(f"{sv} == {lc}")
            self.emit(ind + 1, f"{'if' if first else 'elif'} {' or '.join(conds)}:")
            first = False
            self.block(c_ast.Compound(body), ind + 2)
        if default_body is not None:
            if first:
                self.block(c_ast.Compound(default_body), ind + 1)
            else:
                self.emit(ind + 1, "else:")
                self.block(c_ast.Compound(default_body), ind + 2)
        self.emit(ind + 1, "break")
        self.loop_stack.pop()

    # ------------------------------------------------------------- function
    def translate(self):
        src = self.src
        m = re.search(r"//@globals (.*)", src)
        if m:
            for kv in m.group(1).split(";"):
                if "=" in kv:
                    k, v = kv.split("=", 1)
                    k = re.sub(r"/\*.*?\*/", "", k)
                    k = re.sub(r"^PTR_\w*?_([0-9a-f]{8})$", r"DAT_\1", k)   # renamed in the body below too
                    self.globals[k] = v
        body = src[src.index("\n", src.index("//@globals")) + 1:] if "//@globals" in src else src
        body = re.sub(r"/\*.*?\*/", "", body, flags=re.S)
        if re.search(r"\bUNRECOVERED_JUMPTABLE\s*=[^=]", body):
            # computed tail call through a register that Ghidra could follow: keep it as a variable
            body = re.sub(r"\bcode \*UNRECOVERED_JUMPTABLE;", "uint _jt;", body)
            body = re.sub(r"\(\*UNRECOVERED_JUMPTABLE\)", "_jt", body)
            body = re.sub(r"\bUNRECOVERED_JUMPTABLE\b", "_jt", body)
        body = re.sub(r"\bPTR_\w*?_([0-9a-f]{8})\b", r"DAT_\1", body)
        # small constants that happen to equal the ARM exception vector addresses get vector labels
        vec = {"Reset": 0, "UndefinedInstruction": 4, "SupervisorCall": 8, "PrefetchAbort": 0xC, "DataAbort": 0x10,
               "AddressException": 0x14, "IRQ": 0x18, "FIQ": 0x1C}
        body = re.sub(r"\(\w+ \*\)&(" + "|".join(vec) + r")\b", lambda m: str(vec[m.group(1)]), body)
        body = re.sub(r"&(" + "|".join(vec) + r")\b", lambda m: str(vec[m.group(1)]), body)
        body = re.sub(r"\(\*UNRECOVERED_JUMPTABLE\)", "UNRECOVERED_JUMPTABLE", body)
        body = re.sub(r"\bcode \*UNRECOVERED_JUMPTABLE;", "", body)
        # `code` stays a byte type: Ghidra does byte arithmetic on code pointers (e.g. list links at +4)
        body = re.sub(r"\bswi\(", "__swi(", body)
        body = re.sub(r"\bthunk_FUN_", "FUN_", body)
        # `_DAT_x` = a wider access overlapping the byte-sized symbol DAT_x: Ghidra does not list its type, but
        # it is used as a 32-bit value (e.g. _DAT_04000000 = DISPCNT)
        # The byte symbol keeps byte arithmetic in `&DAT_x + n` (e.g. MI_StopDma 0x020AB738 writes DMAxCNT's top
        # halfword at &DAT_040000b0 + ch*12+10; scaled by 4 it hit 0x04000168 and the card DMA never stopped).
        self.byte_globals = set()
        for m in set(re.findall(r"\b_DAT_([0-9a-f]{8})", body)):
            if self.globals.get("DAT_" + m, "undefined").replace("*", "") in ("undefined", "undefined1", "byte", "char"):
                if "*" not in self.globals.get("DAT_" + m, ""):
                    self.globals["DAT_" + m] = "undefined4"
                    self.byte_globals.add("DAT_" + m)
        body = re.sub(r"&_DAT_([0-9a-f]{8})\b", r"(undefined4 *)&DAT_\1", body)
        body = re.sub(r"\b_DAT_([0-9a-f]{8})", r"DAT_\1", body)
        body = re.sub(r"\b_param_(\d+)\b", r"param_\1", body)   # wider view of a stack parameter
        body = re.sub(r"\b[a-z]*Ram([0-9a-f]{8})\b", r"DAT_\1", body)
        body = re.sub(r"\bfunc_0x([0-9a-f]{8})\b", r"FUN_\1", body)
        self.flat = "goto " in body
        parser = c_parser.CParser()
        ast = parser.parse(TYPEDEFS + body, filename="<f>")
        fdef = ast.ext[-1]
        if not isinstance(fdef, c_ast.FuncDef):
            raise Unsupported("no funcdef")
        ftype = fdef.decl.type
        self.ret_type = type_from_decl(ftype.type)
        params = []
        if ftype.args:
            for p in ftype.args.params:
                if isinstance(p, c_ast.Typename):
                    continue  # (void)
                if isinstance(p, c_ast.EllipsisParam):
                    continue
                t = type_from_decl(p.type)
                self.vars[p.name] = t
                params.append(p.name)
        # locals
        decls = [it for it in (fdef.body.block_items or []) if isinstance(it, c_ast.Decl)]

        class AddrV(c_ast.NodeVisitor):
            def __init__(s): s.names = set()

            def visit_UnaryOp(s, n):
                if n.op == "&" and isinstance(n.expr, c_ast.ID):
                    s.names.add(n.expr.name)
                s.generic_visit(n)
        av = AddrV()
        av.visit(fdef.body)
        undeclared = set()

        class IdV(c_ast.NodeVisitor):
            def __init__(s): s.ids = set()
            def visit_ID(s, n): s.ids.add(n.name)
        iv = IdV()
        iv.visit(fdef.body)
        # variables that ever hold a non-RAM constant address (IO registers, VRAM, ITCM...): derefs through
        # them must be dispatched at run time (_ld/_st), since the same variable is also used for RAM sometimes
        fx = self

        class TaintV(c_ast.NodeVisitor):
            def visit_Assignment(s, n):
                if n.op == "=" and isinstance(n.lvalue, c_ast.ID):
                    cv = fx.const_value(n.rvalue)
                    if cv is not None:
                        fx.const_assign.setdefault(n.lvalue.name, set()).add(cv & 0xFFFFFFFF)
                    if cv is not None and not (BASE <= (cv & 0xFFFFFFFF) < MEM_END) and (cv & 0xFFFFFFFF) >= 0x01000000:
                        fx.tainted.add(n.lvalue.name)
                s.generic_visit(n)
        TaintV().visit(fdef.body)

        # propagate through plain copies (p = q) until nothing changes
        class CopyV(c_ast.NodeVisitor):
            def __init__(s): s.changed = False

            def visit_Assignment(s, n):
                if n.op == "=" and isinstance(n.lvalue, c_ast.ID):
                    r = n.rvalue
                    while isinstance(r, c_ast.Cast):
                        r = r.expr
                    if isinstance(r, c_ast.ID) and r.name in fx.tainted and n.lvalue.name not in fx.tainted:
                        fx.tainted.add(n.lvalue.name)
                        s.changed = True
                s.generic_visit(n)
        while self.tainted:
            cv_ = CopyV()
            cv_.visit(fdef.body)
            if not cv_.changed:
                break
        # Ghidra names stack locals by their offset below the entry SP (local_18, uStack_44, auStack_30): when any
        # of them is used through a pointer, lay ALL of them out like the original frame, because the callee may
        # write neighbouring locals that Ghidra split into separate variables (e.g. a 4 x u16 struct).
        def sx32(v):
            return v - (1 << 32) if v & 0x80000000 else v
        stack_off = {}   # name -> offset relative to the SP at function entry
        for d in decls:
            m = re.match(r"^(?:local|[a-z]*Stack)_([0-9a-f]+)$", d.name)
            if m:
                stack_off[d.name] = -int(m.group(1), 16)
            m = re.match(r"^[a-z]*Stack([0-9a-f]{8})$", d.name)
            if m:
                stack_off[d.name] = sx32(int(m.group(1), 16))
        raw_stack = {n: sx32(int(n[7:], 16)) for n in iv.ids if re.match(r"^stack0x[0-9a-f]{8}$", n)}
        self.incoming = None
        if raw_stack or any(n in av.names or type_from_decl(d.type)[0] == "arr" for d in decls
                            for n in [d.name] if n in stack_off):
            offs = list(stack_off.values()) + list(raw_stack.values())
            # a large frame allocated with `sub sp, sp, <literal>` shows up as `iVar = -DAT_x; &stack0x.. + iVar` or
            # `&local_4 + -DAT_x`:
            # the locals live up to that many bytes below the named offsets, so the frame must cover them too
            # (else they overwrote the callers' frames: e.g. the story select's map-clear count 0x02047AFC)
            big = [self.tx.word(a) for a in {int(x, 16) for x in re.findall(r"[=+(,]\s*-DAT_([0-9a-f]{8})\b", body)}
                   if self.tx.is_const_pool(a) and 0 < self.tx.word(a) < 0x10000]
            if big:
                offs.append(min(offs + [0]) - max(big))
            top = (max([-o for o in offs if o < 0] + [0]) + 7) & ~7
            pos = [o for o in offs if o >= 0]
            inc = ((max(pos) + 8 + 7) & ~7) if pos else 0
            for d in decls:
                if d.name in stack_off:
                    self.mem_locals[d.name] = (top + stack_off[d.name], type_from_decl(d.type))
            for n, o in raw_stack.items():
                self.mem_locals[n] = (top + o, ("int", 1, False))
            self.frame = top + inc
            if inc:
                self.incoming = top
        for d in decls:
            if d.name in self.mem_locals:
                continue
            t = type_from_decl(d.type)
            if t[0] == "arr" or d.name in av.names:
                al = 4
                self.frame = (self.frame + al - 1) & ~(al - 1)
                self.mem_locals[d.name] = (self.frame, t)
                self.frame += max(4, sizeof(t))
            else:
                self.vars[d.name] = t
        for p in params:
            if p in av.names:
                raise Unsupported("address of parameter")
        for n in iv.ids:
            if (n.startswith("in_") or n.startswith("unaff_") or n.startswith("extraout_")) and n not in self.vars:
                self.vars[n] = UINT
                undeclared.add(n)
        self.frame = (self.frame + 7) & ~7
        # emit
        sig = ", ".join(f"{p}: int = 0" for p in params)
        nparams = len(params)
        pad = ", ".join(f"_x{i}: int = 0" for i in range(nparams, 12))
        allp = ", ".join(x for x in (sig, pad) if x)
        self.emit(0, f"func {self.name}({allp}) -> int:")
        body_lines_start = len(self.lines)
        if TRACE:
            self.emit(1, f"if _tracing or _break_on: _trace(0x{self.addr:X}, [{', '.join(params[:4])}])")
        for p in params:
            t = self.vars[p]
            if t[0] == "int" and t[1] < 4 or (t[0] == "int" and t[2]):
                self.emit(1, f"{p} = {wrap_expr(p, t)}")
        for n, t in self.vars.items():
            if n in params:
                continue
            self.emit(1, f"var {n}: int = 0")
        decl_at = len(self.lines)
        if self.frame:
            self.emit(1, f"var _fp: int = _sp")
            self.emit(1, f"_sp += {self.frame}")
            if self.incoming is not None:   # stack-passed parameters live above the entry SP
                for i, p in enumerate(params[4:]):
                    if ARM7:
                        self.emit(1, f"_st(_fp + {self.incoming + 4 * i}, 4, {p} & 0xFFFFFFFF)")
                    else:
                        self.emit(1, f"M.encode_u32(_fp + {self.incoming + 4 * i} - 0x2000000, {p} & 0xFFFFFFFF)")
        if self.flat:
            self.flat_function(fdef.body.block_items or [])
        else:
            for it in fdef.body.block_items or []:
                self.stmt(it, 1)
            self.void_return(1)
        # temporaries are function-scoped (a lowered expression node can be emitted in several branches)
        self.lines[decl_at:decl_at] = [f"\tvar _t{k}: int = 0" for k in range(1, self.tmp + 1)]
        if TRACE:   # loop heads report too, so a busy loop without calls can be located
            out = []
            for ln in self.lines:
                out.append(ln)
                m = re.match(r"^(\t*)while .*:$", ln)
                if m:
                    out.append(m.group(1) + f"\tif _tracing: _trace(0x{self.addr:X}, [-1])")
            self.lines = out
        return "\n".join(self.lines)

    # ------------------------------------------------------------- goto-flattened functions
    FI = 4  # indentation of statements inside a block

    def new_block(self):
        bid = len(self.blocks)
        self.blocks.append([])
        return bid

    def set_block(self, bid):
        self.cur = bid
        self.lines = self.blocks[bid]

    def fjump(self, target):
        self.emit(self.FI, f"_pc = {target}")
        self.emit(self.FI, "continue")

    def flabel(self, name):
        if name not in self.label_ids:
            self.label_ids[name] = self.new_block()
        return self.label_ids[name]

    def flat_function(self, items):
        main_lines = self.lines
        self.blocks = []
        self.label_ids = {}
        self.fbreak = []
        self.fcont = []
        self.set_block(self.new_block())
        for it in items:
            self.fstmt(it)
        if self.frame:
            self.emit(self.FI, "_sp = _fp")
        self.emit(self.FI, "return 0")
        self.lines = main_lines
        self.emit(1, "var _pc: int = 0")
        self.emit(1, "while true:")
        self.emit(2, "match _pc:")
        for bid, lines in enumerate(self.blocks):
            self.emit(3, f"{bid}:")
            if not lines:
                self.emit(self.FI, "pass")
            self.lines.extend(lines)
        self.emit(1, "return 0")

    def fstmt(self, node):
        I = self.FI
        if isinstance(node, c_ast.Compound):
            for it in node.block_items or []:
                self.fstmt(it)
        elif isinstance(node, c_ast.If):
            c = self.cond_stmt(node.cond, I)
            lt, lend = self.new_block(), self.new_block()
            lf = self.new_block() if node.iffalse is not None else lend
            self.emit(I, f"_pc = {lt} if {c} else {lf}")
            self.emit(I, "continue")
            self.set_block(lt); self.fstmt(node.iftrue); self.fjump(lend)
            if node.iffalse is not None:
                self.set_block(lf); self.fstmt(node.iffalse); self.fjump(lend)
            self.set_block(lend)
        elif isinstance(node, c_ast.While):
            ltop, lbody, lend = self.new_block(), self.new_block(), self.new_block()
            self.fjump(ltop)
            self.set_block(ltop)
            c = self.cond_stmt(node.cond, I)
            self.emit(I, f"_pc = {lbody} if {c} else {lend}")
            self.emit(I, "continue")
            self.fbreak.append(lend); self.fcont.append(ltop)
            self.set_block(lbody); self.fstmt(node.stmt); self.fjump(ltop)
            self.fbreak.pop(); self.fcont.pop()
            self.set_block(lend)
        elif isinstance(node, c_ast.DoWhile):
            lbody, lcond, lend = self.new_block(), self.new_block(), self.new_block()
            self.fjump(lbody)
            self.fbreak.append(lend); self.fcont.append(lcond)
            self.set_block(lbody); self.fstmt(node.stmt); self.fjump(lcond)
            self.fbreak.pop(); self.fcont.pop()
            self.set_block(lcond)
            c = self.cond_stmt(node.cond, I)
            self.emit(I, f"_pc = {lbody} if {c} else {lend}")
            self.emit(I, "continue")
            self.set_block(lend)
        elif isinstance(node, c_ast.For):
            if node.init is not None:
                self.stmt_expr(node.init, I)
            ltop, lbody, lnext, lend = self.new_block(), self.new_block(), self.new_block(), self.new_block()
            self.fjump(ltop)
            self.set_block(ltop)
            if node.cond is not None:
                c = self.cond_stmt(node.cond, I)
                self.emit(I, f"_pc = {lbody} if {c} else {lend}")
                self.emit(I, "continue")
            else:
                self.fjump(lbody)
            self.fbreak.append(lend); self.fcont.append(lnext)
            self.set_block(lbody); self.fstmt(node.stmt); self.fjump(lnext)
            self.fbreak.pop(); self.fcont.pop()
            self.set_block(lnext)
            if node.next is not None:
                self.stmt_expr(node.next, I)
            self.fjump(ltop)
            self.set_block(lend)
        elif isinstance(node, c_ast.Switch):
            e = node.cond
            if self.has_side_effects(e):
                e = self.lower(e, I)
            code, _ = self.expr(e)
            sv = self.newtmp()
            self.vars[sv] = INT
            lend = self.new_block()
            # collect case entry points: walk items, each Case/Default starts a block
            entries = []   # (labels, block)
            body_seq = []  # sequence of ('block', bid) / ('stmt', node)

            def walk_case(n):
                labels = []
                while isinstance(n, (c_ast.Case, c_ast.Default)):
                    labels.append(None if isinstance(n, c_ast.Default) else n.expr)
                    st = n.stmts or []
                    if len(st) == 1 and isinstance(st[0], (c_ast.Case, c_ast.Default)):
                        n = st[0]; continue
                    return labels, st
                return labels, []
            for it in node.stmt.block_items or []:
                if isinstance(it, (c_ast.Case, c_ast.Default)):
                    labels, st = walk_case(it)
                    bid = self.new_block()
                    entries.append((labels, bid))
                    body_seq.append(("block", bid))
                    body_seq += [("stmt", x) for x in st]
                else:
                    body_seq.append(("stmt", it))
            self.emit(I, f"{sv} = {code}")
            first = True
            default = lend
            for labels, bid in entries:
                conds = []
                for l in labels:
                    if l is None:
                        default = bid
                    else:
                        conds.append(f"{sv} == {self.expr(l)[0]}")
                if conds:
                    self.emit(I, f"{'if' if first else 'elif'} {' or '.join(conds)}:")
                    self.emit(I + 1, f"_pc = {bid}")
                    first = False
            if first:
                self.emit(I, f"_pc = {default}")
            else:
                self.emit(I, "else:")
                self.emit(I + 1, f"_pc = {default}")
            self.emit(I, "continue")
            self.fbreak.append(lend)
            started = False
            for kind, x in body_seq:
                if kind == "block":
                    if started:
                        self.fjump(x)   # fallthrough
                    self.set_block(x)
                    started = True
                elif started:
                    self.fstmt(x)
            if started:
                self.fjump(lend)
            self.fbreak.pop()
            self.set_block(lend)
        elif isinstance(node, c_ast.Break):
            self.fjump(self.fbreak[-1])
            self.set_block(self.new_block())
        elif isinstance(node, c_ast.Continue):
            self.fjump(self.fcont[-1])
            self.set_block(self.new_block())
        elif isinstance(node, c_ast.Goto):
            self.fjump(self.flabel(node.name))
            self.set_block(self.new_block())
        elif isinstance(node, c_ast.Label):
            lb = self.flabel(node.name)
            self.fjump(lb)
            self.set_block(lb)
            if node.stmt is not None:
                self.fstmt(node.stmt)
        elif isinstance(node, c_ast.Return):
            self.stmt(node, I)
            self.set_block(self.new_block())
        elif isinstance(node, c_ast.Decl):
            pass
        else:
            self.stmt(node, I)


class Transpiler:
    intrinsics = {"__swi", "CONCAT11", "CONCAT22", "CONCAT31", "CONCAT44", "CARRY4", "SCARRY4", "SBORROW4", "LZCOUNT",
                  "coprocessor_moveto", "coprocessor_movefrom", "software_interrupt"}

    def __init__(self, funcs, arm9):
        self.dyn = set()
        self.dyn_req = set()
        self.funcs = funcs
        self.arm9 = arm9
        self.called = set()
        self.code_end = BASE + 0xB7000

    ITCM, ITCM_SRC, ITCM_SIZE = 0x01FF8000, 0x020DD4C0, 0x3C0   # autoload (module params)

    def word(self, a):
        if ARM7:
            return image.word(a)
        if self.ITCM <= a < self.ITCM + self.ITCM_SIZE:
            a = a - self.ITCM + self.ITCM_SRC
        return struct.unpack_from("<I", self.arm9, a - BASE)[0]

    def is_const_pool(self, a):
        if ARM7:
            return image.in_code(a)
        return BASE <= a < self.code_end or self.ITCM <= a < self.ITCM + self.ITCM_SIZE

    def fname(self, a):
        return f"f7_{a:08x}" if ARM7 else f"f_{a:08x}"

    def ret_type(self, a):
        src = self.funcs.get(f"{a:08x}", "")
        m = re.search(r"\n\s*([A-Za-z_][A-Za-z0-9_ ]*?)\s*(\**)\s*FUN_[0-9a-f]{8}\(", src)
        if not m:
            return UINT
        base, stars = m.group(1).strip(), m.group(2)
        t = NAMES2T.get(base, UINT)
        if t == ("void",):
            return UINT if not stars else ptr(("int", 1, False))
        for _ in stars:
            t = ptr(t)
        return t

    def translate(self, addr):
        key = f"{addr:08x}"
        src = self.funcs.get(key)
        if src is None:
            raise Unsupported("no decompilation")
        ft = FuncTx(self, addr, self.fname(addr), src)
        return ft.translate()


HEADER = '''# AUTO-GENERATED by decomp/tools/ghidra2gd.py from Ghidra output — do not edit by hand.
# Each f_XXXXXXXX is the DS function at that ARM9 address, running on the emulated memory image M.
extends DSCoreBase
'''


# Pure memory utility functions of the NitroSDK with a native fast path (DSCoreBase._fast_call, native/
# ds_mem_native.cpp): MIi_CpuClear16/Copy16/Clear32/Copy32/ClearFast/CopyFast, MI_CpuFill8/Copy8,
# MI_UncompressLZ8, MI_UncompressRL8. The translated body stays as the fallback (other address ranges, no native library).
# Also the CARD ROM read loop 0x020B23F0 (moves each transfer's words in one go; DSCoreBase._fast_card_read)
# and OS_SpinWait 0x020AB3DC (lets emulated time pass instead of counting down; DSMachine._spin_wait),
# and FSi_FindPath 0x020ADF08 (file name table walk; native/src/ds_fs_native.cpp).
FASTPATH = {0x020ABB30, 0x020ABB48, 0x020ABB64, 0x020ABB78, 0x020ABB90, 0x020ABBDC, 0x020ABC4C, 0x020ABCE0,
            0x020ABE18, 0x020ABF84, 0x020B23F0, 0x020AB3DC, 0x020ADF08}


def fast_wrap(code, a):
    first, rest = code.split("\n", 1)
    m = re.match(r"^func (\w+)\((.*)\) -> int:$", first)
    if not m:
        return code
    names = [x.split(":")[0].strip() for x in m.group(2).split(",") if x.strip()]
    args = ", ".join(names[:3])
    return (first + "\n"
            f"\tif _fast_on:\n"
            f"\t\tvar _fr: Variant = _fast_call(0x{a:X}, {args})\n"
            f"\t\tif _fr != null:\n"
            f"\t\t\treturn _fr\n" + rest)


def profile_wrap(code, a):
    """PROFILE builds: f_X becomes _pf_X behind a wrapper that measures its time (DSCoreBase._prof_enter/leave)"""
    first, rest = code.split("\n", 1)
    m = re.match(r"^func (\w+)\((.*)\) -> int:$", first)
    if not m:
        return code
    name, sig = m.group(1), m.group(2)
    args = ", ".join(x.split(":")[0].strip() for x in sig.split(",") if x.strip())
    return (f"func {name}({sig}) -> int:\n"
            f"\tvar _pt: int = _prof_enter()\n"
            f"\tvar _pr: int = _pf{name[1:]}({args})\n"
            f"\t_prof_leave(0x{a:X}, _pt)\n"
            f"\treturn _pr\n\n"
            f"func _pf{name[1:]}({sig}) -> int:\n" + rest)


def main():
    funcs = json.load(open(sys.argv[1]))
    arm9 = open(sys.argv[2], "rb").read() if sys.argv[2] != "-" else b""
    global HEADER
    if ARM7:
        HEADER = HEADER.replace("extends DSCoreBase", "extends DSCore7Base").replace("ARM9 address", "ARM7 address")
    out = sys.argv[3]
    addrs = []
    if sys.argv[4] == "--list":
        addrs = [int(x, 16) for x in open(sys.argv[5]).read().split() if x.strip()]
    else:
        addrs = [int(x, 16) for x in sys.argv[4:]]
    tx = Transpiler(funcs, arm9)
    parts = [HEADER]
    ok, bad = [], []
    hle = set()
    import os
    hle_file = os.environ.get("HLE_LIST")
    if hle_file:
        hle = set(int(x, 16) for x in open(hle_file).read().split() if x.strip())
    code_of = {}

    # OS_DisableInterrupts / OS_RestoreInterrupts run tens of thousands of times per file load: their HLE (the
    # CPSR I bit, DSCoreBase._set_i) is emitted in place instead of going through the _hle dispatcher
    HLE_INLINE = {0x020AB36C: "_set_i(0x80, 0x80)", 0x020AB380: "_set_i(a0 & 0x80, 0x80)"}

    def tr(a):
        if a in hle and a in HLE_INLINE and not ARM7:
            return (f"func {tx.fname(a)}(" + ", ".join(f"a{i}: int = 0" for i in range(12)) + ") -> int:\n"
                    f"\treturn {HLE_INLINE[a]}"), None
        if a in hle:
            return (f"func {tx.fname(a)}(" + ", ".join(f"a{i}: int = 0" for i in range(12)) + ") -> int:\n"
                    f"\treturn _hle(0x{a:X}, a0, a1, a2, a3, a4, a5, a6, a7)"), None
        try:
            return tx.translate(a), None
        except Exception as e:  # noqa
            return (f"func {tx.fname(a)}(" + ", ".join(f"_a{i}: int = 0" for i in range(12)) + ") -> int:\n"
                    f"\treturn _missing(0x{a:X})  # not translated: {str(e)[:80]}"), f"{type(e).__name__}: {e}"
    errs = {}
    todo = list(addrs)
    while todo:
        for a in todo:
            code_of[a], errs[a] = tr(a)
        # functions that receive IO/VRAM pointers (directly or through a dynamic caller) are retranslated with
        # run-time address dispatch, until nothing new is found
        new_dyn = (tx.dyn_req & set(addrs)) - tx.dyn - hle
        tx.dyn |= new_dyn
        todo = sorted(new_dyn)
    for a in addrs:
        code = fast_wrap(code_of[a], a) if (a in FASTPATH and not ARM7 and a not in hle) else code_of[a]
        parts.append(profile_wrap(code, a) if PROFILE else code)
        (bad.append((a, errs[a])) if errs[a] else ok.append(a))
    print(f"dynamic-address functions: {len(tx.dyn)}")
    # stubs for called functions that are not part of this translation unit (e.g. ITCM code at 0x01FF8000)
    for a in sorted(tx.called - set(addrs)):
        parts.append(f"func {tx.fname(a)}(" + ", ".join(f"_a{i}: int = 0" for i in range(12)) + ") -> int:\n"
                     f"\treturn _missing(0x{a:X})  # external")
    # dispatch table for indirect calls
    parts.append("\nfunc _register_all() -> void:")
    for a in addrs:
        parts.append(f"\t_fn[0x{a:X}] = {tx.fname(a)}")
    # interworking veneers `ldr ip, [pc]; bx ip; .word target` that are only used as callback values (e.g.
    # task callbacks 0x02007544 / 0x02007550) are aliases of their target
    if arm9 and not ARM7:
        have = set(addrs)
        for o in range(0, len(arm9) - 12, 4):
            w0, w1, tgt = struct.unpack_from("<3I", arm9, o)
            va = 0x02000000 + o
            if w0 == 0xE59FC000 and w1 == 0xE12FFF1C and va not in have and (tgt & ~1) in have:
                parts.append(f"\t_fn[0x{va:X}] = {tx.fname(tgt & ~1)}   # veneer")
    if not addrs:
        parts.append("\tpass")
    open(out, "w").write("\n\n".join(parts) + "\n")
    missing_calls = sorted(tx.called - set(addrs))
    report = {"ok": [f"{a:08x}" for a in ok], "failed": [(f"{a:08x}", e) for a, e in bad],
              "called_not_included": [f"{a:08x}" for a in missing_calls]}
    json.dump(report, open(out + ".report.json", "w"), indent=1)
    print(f"translated {len(ok)}, failed {len(bad)}, external calls {len(missing_calls)}")
    for a, e in bad[:30]:
        print(f"  FAIL {a:08x}: {e}")


if __name__ == "__main__":
    main()
