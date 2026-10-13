// pre-script: add the ARM7 autoload segments (WRAM 0x037F8000, main RAM 0x027E0000) with their bss
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.*;
import ghidra.program.model.mem.*;
import java.io.*;

public class ghidra_Arm7Setup extends GhidraScript {
    void add(String name, long addr, String file, long bss) throws Exception {
        File f = new File(file);
        Memory mem = currentProgram.getMemory();
        Address a = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(addr);
        try (InputStream in = new FileInputStream(f)) {
            MemoryBlock b = mem.createInitializedBlock(name, a, in, f.length(), monitor, false);
            b.setRead(true); b.setWrite(true); b.setExecute(true);
        }
        if (bss > 0) {
            MemoryBlock z = mem.createInitializedBlock(name + "_bss", a.add(f.length()), bss, (byte) 0, monitor, false);
            z.setRead(true); z.setWrite(true);
        }
    }
    public void run() throws Exception {
        String d = getScriptArgs()[0];
        add("wram", 0x037F8000L, d + "/wram.bin", 0x3758);
        add("mram", 0x027E0000L, d + "/mram.bin", 0x18B8);
        Memory mem = currentProgram.getMemory();
        Address io = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(0x04000000L);
        mem.createUninitializedBlock("io", io, 0x1000, false);
        disassemble(currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(0x037FB6C0L));
        createFunction(currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(0x037FB6C0L), "Arm7Main");
    }
}
