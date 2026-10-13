// Native fast path for the NitroSDK file system's path lookup (FSi_FindPath, 0x020ADF08, the default handler of
// FS_COMMAND_FINDPATH). The translated original walks the file name table one directory entry at a time through
// several layers of archive commands (0x020AD8BC -> 0x020AE234 seek-dir / 0x020AE124 read-dir -> 0x020AE370 read
// -> 0x020AEE38 memory read -> MI_CpuCopy8); each file open cost thousands of GDScript calls (100-300 ms hitches
// on screen changes). This is the same walk in C++, writing the same memory (see DATA_NOTES "FS path lookup").
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>

namespace godot {

class DSFSNative : public RefCounted {
	GDCLASS(DSFSNative, RefCounted)

protected:
	static void _bind_methods();

public:
	// h = [M] (main RAM + DTCM image from 0x02000000), file = FSFile address, fp = the translated function's
	// stack frame (DSCoreBase._sp on entry). Returns the FSResult (0 found / 1 failure), or -1 when the
	// preconditions of the fast path do not hold (nothing was written; the caller runs the translated original).
	static int64_t find_path(const Array &h, int64_t file, int64_t fp);
};

} // namespace godot
