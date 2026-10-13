class_name DSBoot
extends RefCounted
## Power-on state for the translated game: what the DS BIOS/firmware (cartridge boot) and the game's crt0
## (ARM9 0x02000800) leave in memory before NitroMain runs. References: GBATEK "DS Cartridge Header",
## "BIOS RAM usage" / "Firmware user settings", and the crt0 disassembly (decomp/notes/boot.md).

const MODULE_PARAMS := 0x02000B4C


static func load(core, rom: PackedByteArray, save: PackedByteArray = PackedByteArray()) -> void:
	var m := PackedByteArray()
	m.resize(DSCoreBase.SIZE)
	# --- cartridge boot: ARM9 and ARM7 binaries copied to their RAM addresses (header 0x20/0x30)
	var a9_off := rom.decode_u32(0x20)
	var a9_ram := rom.decode_u32(0x28)
	var a9_size := rom.decode_u32(0x2C)
	_put(m, a9_ram, rom.slice(a9_off, a9_off + a9_size))
	var a7_off := rom.decode_u32(0x30)
	var a7_ram := rom.decode_u32(0x38)
	var a7_size := rom.decode_u32(0x3C)
	if a7_ram >= 0x02000000 and a7_ram < 0x02400000:
		_put(m, a7_ram, rom.slice(a7_off, a7_off + a7_size))
	# --- shared work area set up by the boot process (mirrored at 0x027FF000 = main RAM end)
	var hdr := rom.slice(0, 0x170)
	var chip_id := 0x00003FC2                     # cartridge chip ID as returned by command 0x90
	var hdr_crc := rom.decode_u16(0x15E)
	var secure_crc := rom.decode_u16(0x6C)
	for base in [0x027FF800, 0x027FFC00]:
		_w32(m, base, chip_id)
		_w32(m, base + 4, chip_id)
		_w16(m, base + 8, hdr_crc)
		_w16(m, base + 0xA, secure_crc)
	_w16(m, 0x027FF850, 0x5835)                   # ARM7 BIOS CRC16 (value left by the BIOS)
	_w16(m, 0x027FFC10, 0x5835)
	_w16(m, 0x027FF869, 0x01FE)                   # (BIOS boot bookkeeping)
	_w16(m, 0x027FFC30, 0xFFFF)                   # no GBA-slot cartridge
	_w16(m, 0x027FFC40, 1)                        # boot indicator: booted from the game card
	_put(m, 0x027FFE00, hdr)                      # cartridge header copy
	# PXI: the ARM7 registers its FIFO receive callbacks for its services (tags 4-14) during its own init;
	# the ARM9 polls these "callback ready" bits (0x027FFF88 + 4 * cpu) before talking to a service
	_w32(m, 0x027FFF8C, 0x7FF0)
	# firmware user settings (0x027FFC80, 0x70 bytes): version 5, colour 0, birthday 1/1, nickname, language
	var us := PackedByteArray()
	us.resize(0x70)
	us[0] = 5
	us[2] = 1
	us[3] = 1
	var nick := "Player"
	for i in nick.length():
		us.encode_u16(6 + 2 * i, nick.unicode_at(i))
	us.encode_u16(0x1A, nick.length())
	us[0x30] = 0                                  # (alarm etc. left 0)
	# touch-screen calibration: ADC (0,0) -> pixel (0,0) and ADC (0xFF0,0xBF0) -> pixel (255,191)
	us.encode_u16(0x58, 0)
	us.encode_u16(0x5A, 0)
	us[0x5C] = 0
	us[0x5D] = 0
	us.encode_u16(0x5E, 0x0FF0)
	us.encode_u16(0x60, 0x0BF0)
	us[0x62] = 0xFF
	us[0x63] = 0xBF
	us.encode_u16(0x64, 0x0031)                   # language 1 (English) + settings flags
	_put(m, 0x027FFC80, us)
	# --- left by the ARM7 after its own initialisation (static values; live ones are updated per frame)
	_put(m, 0x027FFC30, PackedByteArray([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]))
	# wireless firmware data: console MAC address. This game stores the MAC in its save and checks it, so use
	# the one recorded in the player's save when there is one (saves made on melonDS carry 00:09:BF:11:22:33).
	var mac := PackedByteArray([0x00, 0x09, 0xBF, 0x11, 0x22, 0x33])
	if save.size() >= 16 and save[0] == 0x44 and save[1] == 0x42 and save[2] == 0x5A:   # "DBZ2"
		mac = save.slice(0xA, 0x10)
	_w16(m, 0x027FFCF2, 0xD739)
	_put(m, 0x027FFCF4, mac)
	_w16(m, 0x027FFCFA, 0x1041)                   # enabled wireless channels
	_w16(m, 0x027FFFA8, 0x2C00)                   # X/Y/pen bits (released)
	# main RAM is 4 MiB mirrored: keep 0x027FFxxx (the address the SDK uses) as the source of truth
	for i in 0x1000:
		m[0x3FF000 + i] = m[0x7FF000 + i]
	core.M = m
	_crt0(core, rom)
	core.arm7.boot_sound()   # the ARM7 sound driver (translated) initialises before the ARM9 talks to it


## What crt0 (0x02000800) does before calling NitroMain, minus CP15/stack setup.
static func _crt0(core, _rom: PackedByteArray) -> void:
	var m: PackedByteArray = core.M
	core.IO.encode_u16(0x208, 0)                  # IME = 0
	for i in 0x4000:                              # clear DTCM
		m[0x7E0000 + i] = 0
	core.hw.pal.fill(0)                           # clear palette (first 1 KiB = engine A; all of it here)
	for i in range(0, 0x400, 4):                  # OAM: every entry hidden (attr0 = 0x200)
		core.hw.oam.encode_u32(i, 0x200)
	# autoloads (ITCM code runs translated; DTCM data copied) and their bss
	var p := MODULE_PARAMS
	var lst := m.decode_u32(p - 0x02000000)
	var lst_end := m.decode_u32(p + 4 - 0x02000000)
	var src := m.decode_u32(p + 8 - 0x02000000)
	while lst < lst_end:
		var dst := m.decode_u32(lst - 0x02000000)
		var size := m.decode_u32(lst + 4 - 0x02000000)
		var bss := m.decode_u32(lst + 8 - 0x02000000)
		if dst >= 0x02000000 and dst < 0x02800000:
			for i in size:
				m[dst - 0x02000000 + i] = m[src - 0x02000000 + i]
			for i in bss:
				m[dst - 0x02000000 + size + i] = 0
		src += size
		lst += 12
	# static bss
	var bss_start := m.decode_u32(p + 0xC - 0x02000000)
	var bss_end := m.decode_u32(p + 0x10 - 0x02000000)
	for a in range(bss_start, bss_end):
		m[a - 0x02000000] = 0
	m.encode_u32(0x027FFF9C - 0x02000000, 0)
	m.encode_u32(0x027E3FFC - 0x02000000, 0x01FF8000)   # IRQ vector used by the BIOS -> OS_IrqHandler
	core.M = m


static func _put(m: PackedByteArray, addr: int, data: PackedByteArray) -> void:
	var o := addr - 0x02000000
	for i in data.size():
		m[o + i] = data[i]


static func _w32(m: PackedByteArray, addr: int, v: int) -> void:
	m.encode_u32(addr - 0x02000000, v)


static func _w16(m: PackedByteArray, addr: int, v: int) -> void:
	m.encode_u16(addr - 0x02000000, v)
