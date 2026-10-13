// post-script (ARM7 import): write the function entry points found by Ghidra's auto-analysis, one per line
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.*;
import java.io.*;

public class ghidra_Arm7Funcs extends GhidraScript {
    public void run() throws Exception {
        PrintWriter w = new PrintWriter(getScriptArgs()[0]);
        for (Function f : currentProgram.getFunctionManager().getFunctions(true))
            w.println(String.format("0x%08x", f.getEntryPoint().getOffset()));
        w.close();
    }
}
