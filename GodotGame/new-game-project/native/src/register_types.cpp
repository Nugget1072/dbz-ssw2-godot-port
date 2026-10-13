// GDExtension entry point of the native helpers (dsnative.gdextension).
#include "ds_fs_native.h"
#include "ds_gx_native.h"
#include "ds_mem_native.h"
#include "ds_sound_native.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_dsnative(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
	GDREGISTER_CLASS(DSFSNative);
	GDREGISTER_CLASS(DSGXNative);
	GDREGISTER_CLASS(DSMemNative);
	GDREGISTER_CLASS(DSSoundNative);
}

void uninitialize_dsnative(ModuleInitializationLevel p_level) {}

extern "C" {
GDExtensionBool GDE_EXPORT dsnative_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_dsnative);
	init_obj.register_terminator(uninitialize_dsnative);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
