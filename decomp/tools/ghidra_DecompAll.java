// Ghidra headless script: create functions at given addresses, then decompile all functions in a range.
// args: funcs.txt outdir startHex endHex
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.address.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.data.*;
import ghidra.program.model.symbol.SourceType;
import java.util.*;
import java.io.*;
import java.nio.file.*;

public class ghidra_DecompAll extends GhidraScript {
    void sig(AddressSpace sp, long addr, DataType ret, DataType... ps) throws Exception {
        Address ad = sp.getAddress(addr);
        Function f = getFunctionAt(ad);
        if (f == null) { disassemble(ad); f = createFunction(ad, null); }
        if (f == null) { println("sig: no function at " + ad); return; }
        List<Variable> params = new ArrayList<>();
        for (int i = 0; i < ps.length; i++) params.add(new ParameterImpl("p" + i, ps[i], currentProgram));
        f.updateFunction(null, new ReturnParameterImpl(ret, currentProgram), params,
            Function.FunctionUpdateType.DYNAMIC_STORAGE_ALL_PARAMS, true, SourceType.USER_DEFINED);
        f.setNoReturn(false);
    }

    /** callee of a tail call at the end of f (unconditional branch to another function, or a CALL_RETURN override) */
    Function tailCallee(Function f) {
        InstructionIterator fi = currentProgram.getListing().getInstructions(f.getBody(), true);
        Function found = null;
        while (fi.hasNext()) {
            Instruction ins = fi.next();
            ghidra.program.model.symbol.FlowType ft = ins.getFlowType();
            for (ghidra.program.model.symbol.Reference r : ins.getReferencesFrom()) {
                ghidra.program.model.symbol.RefType rt = r.getReferenceType();
                boolean tail = (rt == ghidra.program.model.symbol.RefType.CALL_OVERRIDE_UNCONDITIONAL
                        && ins.getFlowOverride() == ghidra.program.model.listing.FlowOverride.CALL_RETURN)
                    || (ft.isJump() && !ft.isConditional() && rt.isFlow());
                if (!tail) continue;
                Function g = getFunctionAt(r.getToAddress());
                if (g != null && g != f) found = g;
            }
            if (ft.isCall() && ft.isTerminal()) {   // call + return (Ghidra's own tail-call detection)
                for (ghidra.program.model.symbol.Reference r : ins.getReferencesFrom()) {
                    Function g = getFunctionAt(r.getToAddress());
                    if (g != null && g != f) found = g;
                }
            }
        }
        return found;
    }

    void postorder(Function f, Set<Function> seen, List<Function> out, long start, long end) throws Exception {
        // iterative DFS (deep call chains)
        Deque<Object[]> st = new ArrayDeque<>();
        if (!seen.add(f)) return;
        st.push(new Object[]{f, new ArrayList<>(f.getCalledFunctions(monitor)).iterator()});
        while (!st.isEmpty()) {
            Object[] top = st.peek();
            @SuppressWarnings("unchecked") Iterator<Function> it = (Iterator<Function>) top[1];
            if (it.hasNext()) {
                Function c = it.next();
                long ep = c.getEntryPoint().getOffset();
                if (ep < start || ep >= end || !seen.add(c)) continue;
                st.push(new Object[]{c, new ArrayList<>(c.getCalledFunctions(monitor)).iterator()});
            } else {
                st.pop();
                out.add((Function) top[0]);
            }
        }
    }

    @Override
    protected void run() throws Exception {
        String[] a = getScriptArgs();
        String funcsFile = a[0], outDir = a[1];
        long start = Long.decode(a[2]), end = Long.decode(a[3]);
        boolean arm7 = a.length > 4 && a[4].equals("arm7");   // ARM7 binary: no ITCM, no ARM9 runtime signatures
        AddressSpace sp = currentProgram.getAddressFactory().getDefaultAddressSpace();
        // ITCM: 0x3C0 bytes autoloaded from ARM9 0x020DD4C0 to 0x01FF8000 (module params autoload list)
        if (!arm7 && currentProgram.getMemory().getBlock(sp.getAddress(0x01ff8000L)) == null) {
            byte[] itcm = new byte[0x3c0];
            currentProgram.getMemory().getBytes(sp.getAddress(0x020dd4c0L), itcm);
            currentProgram.getMemory().createInitializedBlock("ITCM", sp.getAddress(0x01ff8000L),
                new java.io.ByteArrayInputStream(itcm), 0x3c0, monitor, false);
            println("ITCM block created");
        }
        int created = 0;
        for (String line : Files.readAllLines(Paths.get(funcsFile))) {
            line = line.trim(); if (line.isEmpty()) continue;
            Address ad = sp.getAddress(Long.decode(line));
            if (getFunctionAt(ad) == null) {
                disassemble(ad);
                if (createFunction(ad, null) != null) created++;
            }
        }
        println("created " + created);
        // conditional "bx lr" after a conditional pop is a return, not an indirect jump
        int ov = 0;
        InstructionIterator ii = currentProgram.getListing().getInstructions(true);
        while (ii.hasNext()) {
            Instruction ins = ii.next();
            String m = ins.getMnemonicString().toLowerCase();
            if (m.startsWith("bx") && ins.getNumOperands() == 1 && ins.getDefaultOperandRepresentation(0).equals("lr")) {
                if (ins.getFlowOverride() != ghidra.program.model.listing.FlowOverride.RETURN) {
                    ins.setFlowOverride(ghidra.program.model.listing.FlowOverride.RETURN);
                    ov++;
                }
            }
        }
        println("bx lr overrides " + ov);
        // indirect branches through a literal-pool function address: tell Ghidra the callee so the call uses
        // its signature (pass-through register arguments survive); tail jumps become call+return
        java.io.File icf = new java.io.File(new java.io.File(funcsFile).getParentFile(), "icall_overrides.txt");
        int ico = 0;
        if (icf.exists()) {
            for (String line : Files.readAllLines(icf.toPath())) {
                String[] p = line.trim().split("\\s+");
                if (p.length < 3) continue;
                Address from = sp.getAddress(Long.decode(p[0])), to = sp.getAddress(Long.decode(p[1]));
                Instruction ins = getInstructionAt(from);
                if (ins == null) continue;
                if (p[2].equals("jump")) ins.setFlowOverride(ghidra.program.model.listing.FlowOverride.CALL_RETURN);
                boolean has = false;
                for (ghidra.program.model.symbol.Reference r : ins.getReferencesFrom())
                    if (r.getReferenceType() == ghidra.program.model.symbol.RefType.CALL_OVERRIDE_UNCONDITIONAL) has = true;
                if (!has) currentProgram.getReferenceManager().addMemoryReference(from, to,
                    ghidra.program.model.symbol.RefType.CALL_OVERRIDE_UNCONDITIONAL, SourceType.USER_DEFINED, 0);
                ico++;
            }
        }
        println("indirect call overrides " + ico);
        // compiler runtime helpers return quotient/remainder in r0:r1 -> declare 64-bit returns so callers show
        // the remainder as (int)(x >> 32) instead of a phantom extraout_r1, and always show both arguments
        DataType I = IntegerDataType.dataType, U = UnsignedIntegerDataType.dataType;
        DataType LL = LongLongDataType.dataType, ULL = UnsignedLongLongDataType.dataType;
        if (!arm7) {
        sig(sp, 0x020b5e30L, LL, I, I);        // _s32_div_f
        sig(sp, 0x020b603cL, ULL, U, U);       // _u32_div_f
        sig(sp, 0x020b6044L, ULL, U, U);       // _u32_div_not_0_f
        sig(sp, 0x020b5c28L, ULL, ULL, ULL);   // _ll_udiv
        sig(sp, 0x020b5c34L, ULL, ULL, ULL);   // _ull_mod
        sig(sp, 0x020b5c70L, LL, LL, LL);      // _ll_mod
        sig(sp, 0x020b5c80L, LL, LL, LL);      // _ll_sdiv
        // CPSR helpers (mrs/msr are invisible to the decompiler): keep the saved-state value flowing
        sig(sp, 0x020ab358L, U);               // OS_EnableInterrupts
        sig(sp, 0x020ab36cL, U);               // OS_DisableInterrupts
        sig(sp, 0x020ab380L, U, U);            // OS_RestoreInterrupts(prev)
        sig(sp, 0x020ab398L, U);               // OS_DisableInterrupts_IrqAndFiq
        sig(sp, 0x020ab3acL, U, U);            // OS_RestoreInterrupts_IrqAndFiq(prev)
        sig(sp, 0x020ab3c4L, U);               // OS_GetProcMode
        } else {
        // ARM7: the same Metrowerks runtime division helpers (0x038070E4..0x03807500)
        sig(sp, 0x038072ecL, LL, I, I);        // _s32_div_f
        sig(sp, 0x038074f8L, ULL, U, U);       // _u32_div_f
        sig(sp, 0x03807500L, ULL, U, U);       // _u32_div_not_0_f
        sig(sp, 0x038070e4L, ULL, ULL, ULL);   // _ll_udiv
        sig(sp, 0x038070f0L, ULL, ULL, ULL);   // _ull_mod
        sig(sp, 0x0380712cL, LL, LL, LL);      // _ll_mod
        sig(sp, 0x0380713cL, LL, LL, LL);      // _ll_sdiv
        }
        // BIOS call wrappers (`swi #n; bx lr`): arguments live in r0-r3 and are invisible to the decompiler,
        // so declare f(r0, r1, r2, r3) -> r0 for every short function that contains a swi
        List<Long> biosw = new ArrayList<>();
        for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
            long ep = f.getEntryPoint().getOffset();
            if (ep < start || ep >= end) continue;
            InstructionIterator fi = currentProgram.getListing().getInstructions(f.getBody(), true);
            int n = 0; boolean swi = false;
            while (fi.hasNext()) { Instruction ins = fi.next(); n++; String m = ins.getMnemonicString().toLowerCase();
                if (m.startsWith("swi") || m.startsWith("svc")) swi = true; }
            if (swi && n <= 4) biosw.add(ep);
        }
        for (long ep : biosw) sig(sp, ep, U, U, U, U, U);
        StringBuilder bw = new StringBuilder();
        for (long ep : biosw) bw.append(Long.toHexString(ep)).append(' ');
        println("BIOS wrappers " + biosw.size() + ": " + bw);
        analyzeChanges(currentProgram);
        for (long ep : biosw) sig(sp, ep, U, U, U, U, U);   // again: auto-analysis may have re-derived them
        DecompInterface di = new DecompInterface();
        di.openProgram(currentProgram);
        // parameter ID: decompile everything and commit inferred parameters/returns to the database, so that
        // callers decompiled later show the arguments (otherwise pass-through r0-r3 arguments vanish)
        Set<Long> fixed = new HashSet<>(Arrays.asList(0x020b5e30L, 0x020b603cL, 0x020b6044L, 0x020b5c28L,
            0x020b5c34L, 0x020b5c70L, 0x020b5c80L, 0x020ab358L, 0x020ab36cL, 0x020ab380L, 0x020ab398L, 0x020ab3acL,
            0x020ab3c4L, 0x038072ecL, 0x038074f8L, 0x03807500L, 0x038070e4L, 0x038070f0L, 0x0380712cL, 0x0380713cL));
        fixed.addAll(biosw);
        // computed calls through function pointers: Ghidra cannot see the callee, and it guesses the argument
        // count from the call site (often just r0). Override every such call site with f(r0, r1, r2, r3): the
        // ARM ABI passes the first four arguments in registers, so passing all four is always correct.
        ghidra.program.model.data.FunctionDefinitionDataType gsig = new ghidra.program.model.data.FunctionDefinitionDataType("icall4");
        gsig.setReturnType(UnsignedIntegerDataType.dataType);
        gsig.setArguments(new ghidra.program.model.data.ParameterDefinition[]{
            new ghidra.program.model.data.ParameterDefinitionImpl("a0", UnsignedIntegerDataType.dataType, null),
            new ghidra.program.model.data.ParameterDefinitionImpl("a1", UnsignedIntegerDataType.dataType, null),
            new ghidra.program.model.data.ParameterDefinitionImpl("a2", UnsignedIntegerDataType.dataType, null),
            new ghidra.program.model.data.ParameterDefinitionImpl("a3", UnsignedIntegerDataType.dataType, null)});
        // calls that also pass stack arguments (str rX,[sp,#0..#0xc] just before the call): f(r0..r3, sp[0..k-1])
        ghidra.program.model.data.FunctionDefinitionDataType[] gsigs = new ghidra.program.model.data.FunctionDefinitionDataType[5];
        for (int k = 0; k <= 4; k++) {
            ghidra.program.model.data.FunctionDefinitionDataType d = new ghidra.program.model.data.FunctionDefinitionDataType("icall" + (4 + k));
            d.setReturnType(UnsignedIntegerDataType.dataType);
            ghidra.program.model.data.ParameterDefinition[] pd = new ghidra.program.model.data.ParameterDefinition[4 + k];
            for (int i = 0; i < 4 + k; i++)
                pd[i] = new ghidra.program.model.data.ParameterDefinitionImpl("a" + i, UnsignedIntegerDataType.dataType, null);
            d.setArguments(pd);
            gsigs[k] = d;
        }
        java.util.regex.Pattern spst = java.util.regex.Pattern.compile("^str\\w*\\s+\\w+\\s*,\\s*\\[sp(?:\\s*,\\s*#(0x[0-9a-f]+|\\d+))?\\]$");
        int nstk = 0;
        int nov = 0;
        for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
            long ep = f.getEntryPoint().getOffset();
            if (ep < start || ep >= end) continue;
            InstructionIterator fi = currentProgram.getListing().getInstructions(f.getBody(), true);
            while (fi.hasNext()) {
                Instruction ins = fi.next();
                ghidra.program.model.symbol.FlowType ft = ins.getFlowType();
                if (!(ft.isCall() && ft.isComputed())) continue;
                boolean known = false;
                for (ghidra.program.model.symbol.Reference r : ins.getReferencesFrom())
                    if (r.getReferenceType() == ghidra.program.model.symbol.RefType.CALL_OVERRIDE_UNCONDITIONAL) known = true;
                if (known) continue;
                int k = 0;
                Instruction pi = ins.getPrevious();
                for (int back = 0; back < 16 && pi != null && f.getBody().contains(pi.getAddress()); back++, pi = pi.getPrevious()) {
                    if (pi.getFlowType().isCall()) break;
                    java.util.regex.Matcher mm = spst.matcher(pi.toString().toLowerCase());
                    if (mm.matches()) {
                        int off = mm.group(1) == null ? 0 : Integer.decode(mm.group(1));
                        if (off < 16) k = Math.max(k, off / 4 + 1);
                    }
                }
                if (k > 0) nstk++;
                try {
                    ghidra.program.model.pcode.HighFunctionDBUtil.writeOverride(f, ins.getAddress(), gsigs[k]);
                    nov++;
                } catch (Exception e) { println("override failed at " + ins.getAddress() + ": " + e.getMessage()); }
            }
        }
        println("computed-call signature overrides " + nov + " (" + nstk + " with stack arguments)");
        // reset previously committed prototypes, then commit inferred ones bottom-up (callees before callers),
        // so a caller sees each callee's full parameter list (register arguments passed straight through)
        List<Function> allf = new ArrayList<>();
        for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
            long ep = f.getEntryPoint().getOffset();
            if (ep < start || ep >= end) continue;
            allf.add(f);
            if (fixed.contains(ep) || f.isThunk()) continue;   // a thunk's signature is its target's
            f.replaceParameters(new ArrayList<Variable>(), Function.FunctionUpdateType.DYNAMIC_STORAGE_ALL_PARAMS, true,
                SourceType.DEFAULT);
            f.setReturnType(DataType.DEFAULT, SourceType.DEFAULT);
            f.setSignatureSource(SourceType.DEFAULT);
        }
        List<Function> order = new ArrayList<>();
        Set<Function> seen = new HashSet<>();
        for (Function f : allf) postorder(f, seen, order, start, end);
        int committed = 0, tailfix = 0, voidfix = 0;
        for (Function f : order) {
            long ep = f.getEntryPoint().getOffset();
            if (fixed.contains(ep) || f.isThunk()) continue;
            DecompileResults r = di.decompileFunction(f, 60, monitor);
            if (r == null || r.getHighFunction() == null) continue;
            try {
                ghidra.program.model.pcode.HighFunctionDBUtil.commitParamsToDatabase(r.getHighFunction(), true,
                    ghidra.program.model.pcode.HighFunctionDBUtil.ReturnCommitOption.COMMIT, SourceType.ANALYSIS);
                committed++;
                // a tail call (b / bx to another function) returns the callee's r0: inherit its return type
                if (f.getReturnType() instanceof ghidra.program.model.data.VoidDataType) {
                    Function g = tailCallee(f);
                    if (g != null && !(g.getReturnType() instanceof ghidra.program.model.data.VoidDataType)) {
                        f.setReturnType(g.getReturnType(), SourceType.ANALYSIS);
                        tailfix++;
                    }
                }
                // On ARM every function leaves something in r0 and callers sometimes rely on it where the
                // decompiler's return-value inference says "void" (e.g. results passed through a callee).
                // Declaring r0 as the return value is always faithful: unused values are simply ignored.
                if (f.getReturnType() instanceof ghidra.program.model.data.VoidDataType) {
                    f.setReturnType(ghidra.program.model.data.Undefined4DataType.dataType, SourceType.ANALYSIS);
                    voidfix++;
                }
            } catch (Exception e) { println("commit failed " + f.getName() + ": " + e.getMessage()); }
        }
        println("bottom-up prototypes committed " + committed + ", tail-call return types " + tailfix + ", void->r0 " + voidfix);
        int n = 0;
        StringBuilder all = new StringBuilder();
        for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
            long ep = f.getEntryPoint().getOffset();
            if (ep < start || ep >= end) continue;
            DecompileResults r = di.decompileFunction(f, 60, monitor);
            String c = (r != null && r.getDecompiledFunction() != null) ? r.getDecompiledFunction().getC() : "// decompile failed\n";
            StringBuilder gl = new StringBuilder("//@globals ");
            if (r != null && r.getHighFunction() != null) {
                java.util.Iterator<ghidra.program.model.pcode.HighSymbol> it = r.getHighFunction().getGlobalSymbolMap().getSymbols();
                while (it.hasNext()) {
                    ghidra.program.model.pcode.HighSymbol hs = it.next();
                    gl.append(hs.getName()).append("=").append(hs.getDataType().getDisplayName().replace(" ", "")).append(";");
                }
            }
            c = gl.toString() + "\n" + c;
            all.append("// ===== ").append(f.getName()).append(" @ ").append(f.getEntryPoint()).append("\n").append(c).append("\n");
            n++;
        }
        Files.write(Paths.get(outDir, String.format("decomp_%08x_%08x.c", start, end)), all.toString().getBytes());
        println("decompiled " + n);
    }
}
