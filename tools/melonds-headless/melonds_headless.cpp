// melonds_headless: a tiny C API over the melonDS 1.1 core (GPLv3, same as melonDS).
// Purpose: frame-exact, scriptable reference captures of the original game for the port:
//   - run N frames with a given key mask / touch point
//   - grab both screens (256x384 BGRA)
//   - read emulated RAM (main RAM, VRAM banks via ARM9 bus reads)
//   - save/load savestates (melonDS format, compatible with the Qt app's .mlN files)
//   - read audio output
// Built in the cloud sandbox against melonDS 1.1 sources; loaded from Python with ctypes (mh.py).
#include <cstdio>
#include <cstdarg>
#include <cstring>
#include <chrono>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <memory>
#include <vector>
#include <string>
#include <sys/stat.h>
#include "NDS.h"
#include "NDSCart.h"
#include "GPU.h"
#include "SPU.h"
#include "Savestate.h"
#include "Platform.h"
#include "Args.h"
#include "FreeBIOS.h"

using namespace melonDS;

// ------------------------------------------------------------------ Platform
namespace melonDS::Platform {
static bool g_verbose = false;
void SignalStop(StopReason, void*) {}
static std::string ModeString(FileMode mode, bool exists) {
    std::string s;
    if (mode & FileMode::Append) s += 'a';
    else if (!(mode & FileMode::Write)) s += 'r';
    else if (mode & FileMode::NoCreate) s += 'r';
    else if ((mode & FileMode::Preserve) && exists) s += 'r';
    else s += 'w';
    if ((mode & FileMode::ReadWrite) == FileMode::ReadWrite) s += '+';
    if (!(mode & FileMode::Text)) s += 'b';
    return s;
}
static bool Exists(const std::string& p) { struct stat st; return stat(p.c_str(), &st) == 0; }
FileHandle* OpenFile(const std::string& path, FileMode mode) {
    if ((mode & (FileMode::ReadWrite | FileMode::Append)) == FileMode::None) return nullptr;
    bool ex = Exists(path);
    if ((mode & FileMode::NoCreate) && !ex) return nullptr;
    return (FileHandle*)fopen(path.c_str(), ModeString(mode, ex).c_str());
}
std::string GetLocalFilePath(const std::string& f) { return f; }
FileHandle* OpenLocalFile(const std::string& p, FileMode m) { return OpenFile(p, m); }
bool CloseFile(FileHandle* f) { return fclose((FILE*)f) == 0; }
bool IsEndOfFile(FileHandle* f) { return feof((FILE*)f) != 0; }
bool FileReadLine(char* s, int n, FileHandle* f) { return fgets(s, n, (FILE*)f) != nullptr; }
bool FileExists(const std::string& n) { return Exists(n); }
bool LocalFileExists(const std::string& n) { return Exists(n); }
bool CheckFileWritable(const std::string&) { return true; }
bool CheckLocalFileWritable(const std::string&) { return true; }
bool FileSeek(FileHandle* f, s64 off, FileSeekOrigin o) {
    int w = o == FileSeekOrigin::Start ? SEEK_SET : o == FileSeekOrigin::Current ? SEEK_CUR : SEEK_END;
    return fseek((FILE*)f, off, w) == 0;
}
void FileRewind(FileHandle* f) { rewind((FILE*)f); }
u64 FilePosition(FileHandle* f) { return ftell((FILE*)f); }
u64 FileRead(void* d, u64 s, u64 c, FileHandle* f) { return fread(d, s, c, (FILE*)f); }
bool FileFlush(FileHandle* f) { return fflush((FILE*)f) == 0; }
u64 FileWrite(const void* d, u64 s, u64 c, FileHandle* f) { return fwrite(d, s, c, (FILE*)f); }
u64 FileWriteFormatted(FileHandle* f, const char* fmt, ...) {
    va_list a; va_start(a, fmt); u64 r = vfprintf((FILE*)f, fmt, a); va_end(a); return r;
}
u64 FileLength(FileHandle* f) { long p = ftell((FILE*)f); fseek((FILE*)f, 0, SEEK_END); long l = ftell((FILE*)f); fseek((FILE*)f, p, SEEK_SET); return l; }
void Log(LogLevel lvl, const char* fmt, ...) {
    if (!g_verbose && lvl < LogLevel::Warn) return;
    va_list a; va_start(a, fmt); vfprintf(stderr, fmt, a); va_end(a);
}
struct Thread { std::thread t; };
Thread* Thread_Create(std::function<void()> fn) { auto* t = new Thread; t->t = std::thread(fn); return t; }
void Thread_Free(Thread* t) { if (t->t.joinable()) t->t.detach(); delete t; }
void Thread_Wait(Thread* t) { if (t->t.joinable()) t->t.join(); }
struct Semaphore { std::mutex m; std::condition_variable cv; int count = 0; };
Semaphore* Semaphore_Create() { return new Semaphore; }
void Semaphore_Free(Semaphore* s) { delete s; }
void Semaphore_Reset(Semaphore* s) { std::lock_guard<std::mutex> l(s->m); s->count = 0; }
void Semaphore_Wait(Semaphore* s) { std::unique_lock<std::mutex> l(s->m); s->cv.wait(l, [s] { return s->count > 0; }); s->count--; }
bool Semaphore_TryWait(Semaphore* s, int ms) {
    std::unique_lock<std::mutex> l(s->m);
    if (!s->cv.wait_for(l, std::chrono::milliseconds(ms), [s] { return s->count > 0; })) return false;
    s->count--; return true;
}
void Semaphore_Post(Semaphore* s, int c) { { std::lock_guard<std::mutex> l(s->m); s->count += c; } s->cv.notify_all(); }
struct Mutex { std::mutex m; };
Mutex* Mutex_Create() { return new Mutex; }
void Mutex_Free(Mutex* m) { delete m; }
void Mutex_Lock(Mutex* m) { m->m.lock(); }
void Mutex_Unlock(Mutex* m) { m->m.unlock(); }
bool Mutex_TryLock(Mutex* m) { return m->m.try_lock(); }
void Sleep(u64 us) { std::this_thread::sleep_for(std::chrono::microseconds(us)); }
u64 GetMSCount() { return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count(); }
u64 GetUSCount() { return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now().time_since_epoch()).count(); }
static std::string g_savpath;
static std::vector<u8> g_save;
void WriteNDSSave(const u8* data, u32 len, u32, u32, void*) { g_save.assign(data, data + len); }
void WriteGBASave(const u8*, u32, u32, u32, void*) {}
void WriteFirmware(const Firmware&, u32, u32, void*) {}
void WriteDateTime(int, int, int, int, int, int, void*) {}
void MP_Begin(void*) {}
void MP_End(void*) {}
int MP_SendPacket(u8*, int, u64, void*) { return 0; }
int MP_RecvPacket(u8*, u64*, void*) { return 0; }
int MP_SendCmd(u8*, int, u64, void*) { return 0; }
int MP_SendReply(u8*, int, u64, u16, void*) { return 0; }
int MP_SendAck(u8*, int, u64, void*) { return 0; }
int MP_RecvHostPacket(u8*, u64*, void*) { return 0; }
u16 MP_RecvReplies(u8*, u64, u16, void*) { return 0; }
int Net_SendPacket(u8*, int, void*) { return 0; }
int Net_RecvPacket(u8*, void*) { return 0; }
void Mic_Start(void*) {}
void Mic_Stop(void*) {}
int Mic_ReadInput(s16*, int, void*) { return 0; }
void Camera_Start(int, void*) {}
void Camera_Stop(int, void*) {}
void Camera_CaptureFrame(int, u32*, int, int, bool, void*) {}
bool Addon_KeyDown(KeyType, void*) { return false; }
void Addon_RumbleStart(u32, void*) {}
void Addon_RumbleStop(void*) {}
float Addon_MotionQuery(MotionQueryType, void*) { return 0; }
DynamicLibrary* DynamicLibrary_Load(const char*) { return nullptr; }
void DynamicLibrary_Unload(DynamicLibrary*) {}
void* DynamicLibrary_LoadFunction(DynamicLibrary*, const char*) { return nullptr; }
AACDecoder* AAC_Init() { return nullptr; }
void AAC_DeInit(AACDecoder*) {}
bool AAC_Configure(AACDecoder*, int, int) { return false; }
bool AAC_DecodeFrame(AACDecoder*, const void*, int, void*, int) { return false; }
}  // namespace melonDS::Platform

// ------------------------------------------------------------------ C API
static std::unique_ptr<NDS> g_nds;
static u32 g_keys = 0xFFF;  // active-low mask, as NDS::SetKeyMask expects

static std::vector<u8> ReadAll(const char* path) {
    std::vector<u8> v; FILE* f = fopen(path, "rb"); if (!f) return v;
    fseek(f, 0, SEEK_END); v.resize(ftell(f)); fseek(f, 0, SEEK_SET);
    if (fread(v.data(), 1, v.size(), f) != v.size()) v.clear();
    fclose(f); return v;
}

extern "C" {
int mh_init(const char* rom_path, const char* sav_path, int jit) {
    auto rom = ReadAll(rom_path);
    if (rom.empty()) return -1;
    NDSArgs args;
    if (!jit) args.JIT = std::nullopt;
    g_nds = std::make_unique<NDS>(std::move(args), nullptr);
    NDSCart::NDSCartArgs cargs;
    if (sav_path && *sav_path) {
        auto sav = ReadAll(sav_path);
        if (!sav.empty()) {
            cargs.SRAM = std::make_unique<u8[]>(sav.size());
            memcpy(cargs.SRAM.get(), sav.data(), sav.size());
            cargs.SRAMLength = sav.size();
        }
    }
    auto cart = NDSCart::ParseROM(rom.data(), rom.size(), nullptr, std::move(cargs));
    if (!cart) return -2;
    g_nds->Reset();
    g_nds->SetNDSCart(std::move(cart));
    g_nds->SetupDirectBoot("rom.nds");
    g_nds->Start();
    return 0;
}
// RTC override (deterministic references): sets the date/time; callers re-set it every frame to freeze it
void mh_set_rtc(int y, int mo, int d, int h, int mi, int s) { g_nds->RTC.SetDateTime(y, mo, d, h, mi, s); }
// keys: bitmask of PRESSED buttons, bit order = A B Select Start Right Left Up Down R L X Y
void mh_set_input(u32 pressed, int touch, int tx, int ty) {
    g_keys = (~pressed) & 0xFFF;
    g_nds->SetKeyMask(g_keys);
    if (touch) g_nds->TouchScreen(tx, ty); else g_nds->ReleaseScreen();
}
u32 mh_run_frames(int n) { u32 r = 0; for (int i = 0; i < n; i++) r = g_nds->RunFrame(); return r; }
// out: 256*384 u32 (0xAARRGGBB as melonDS stores: BGRA8888 little-endian)
void mh_get_screens(u32* out) {
    int fb = g_nds->GPU.FrontBuffer;
    memcpy(out, g_nds->GPU.Framebuffer[fb][0].get(), 256 * 192 * 4);
    memcpy(out + 256 * 192, g_nds->GPU.Framebuffer[fb][1].get(), 256 * 192 * 4);
}
// Read via the ARM9 bus (covers main RAM, VRAM mapped regions, palettes, OAM, IO).
void mh_read(u32 addr, u32 len, u8* out) {
    for (u32 i = 0; i < len; i++) out[i] = g_nds->ARM9Read8(addr + i);
}
// 32-bit aligned reads (IO registers often have no 8-bit read path)
void mh_read32(u32 addr, u32 words, u32* out) { for (u32 i = 0; i < words; i++) out[i] = g_nds->ARM9Read32(addr + i * 4); }
// tightly coupled memories (not visible through the bus reads above)
u32 mh_dtcm(u8* out) { memcpy(out, g_nds->ARM9.DTCM, 0x4000); return g_nds->ARM9.DTCMBase; }
void mh_itcm(u8* out) { memcpy(out, g_nds->ARM9.ITCM, 0x8000); }
// code patch for breakpoints: write main RAM directly and drop the ARM9 instruction cache (use without JIT)
void mh_poke32(u32 addr, u32 v) {
    u32 o = addr & g_nds->MainRAMMask;
    memcpy(&g_nds->MainRAM[o], &v, 4);
    g_nds->ARM9.ICacheInvalidateAll();
}
void mh_write8(u32 addr, u8 v) { g_nds->ARM9Write8(addr, v); }
int mh_main_ram(u8* out, u32 len) { if (len > g_nds->MainRAMMask + 1) len = g_nds->MainRAMMask + 1; memcpy(out, g_nds->MainRAM, len); return len; }
int mh_savestate(const char* path) {
    Savestate st; if (st.Error) return -1;
    if (!g_nds->DoSavestate(&st) || st.Error) return -2;
    FILE* f = fopen(path, "wb"); if (!f) return -3;
    fwrite(st.Buffer(), 1, st.Length(), f); fclose(f); return 0;
}
int mh_loadstate(const char* path) {
    auto v = ReadAll(path); if (v.empty()) return -1;
    Savestate st(v.data(), v.size(), false);
    if (st.Error) return -2;
    if (!g_nds->DoSavestate(&st) || st.Error) return -3;
    return 0;
}
int mh_audio(s16* out, int max_samples) { return g_nds->SPU.ReadOutput(out, max_samples); }
int mh_audio_avail() { return g_nds->SPU.GetOutputSize(); }
// Dump the 3D polygons rendered in the last frame.
// Record: attr, texparam, texpal, nverts, then per vertex: clipX clipY clipZ clipW texS texT scrX scrY r g b
int mh_polys(s32* out, int max_ints) {
    auto& g3 = g_nds->GPU.GPU3D;
    int n = 0, np = g3.RenderNumPolygons;
    for (int i = 0; i < np; i++) {
        Polygon* p = g3.RenderPolygonRAM[i];
        int need = 4 + p->NumVertices * 11;
        if (n + need + 1 > max_ints) break;
        out[n++] = p->Attr; out[n++] = p->TexParam; out[n++] = p->TexPalette; out[n++] = p->NumVertices;
        for (u32 v = 0; v < p->NumVertices; v++) {
            Vertex* vx = p->Vertices[v];
            for (int k = 0; k < 4; k++) out[n++] = vx->Position[k];
            out[n++] = vx->TexCoords[0]; out[n++] = vx->TexCoords[1];
            out[n++] = vx->FinalPosition[0]; out[n++] = vx->FinalPosition[1];
            for (int k = 0; k < 3; k++) out[n++] = vx->FinalColor[k];
        }
    }
    return n;
}
// Raw VRAM banks A-I (for texture/palette inspection)
int mh_vram(int bank, u8* out) {
    static const u32 sizes[9] = {0x20000,0x20000,0x20000,0x20000,0x10000,0x4000,0x4000,0x8000,0x4000};
    if (bank < 0 || bank > 8) return 0;
    memcpy(out, g_nds->GPU.VRAM[bank], sizes[bank]);
    return sizes[bank];
}
u32 mh_vramcnt(int bank) { return g_nds->GPU.VRAMCNT[bank]; }
// 2D engine state (engine 0 = A/top by default, 1 = B): out[0]=DispCnt, [1..4]=BGCnt, [5..8]=BGXPos, [9..12]=BGYPos,
// [13..14]=BGXRef, [15..16]=BGYRef, [17..18]=PA, [19..20]=PB, [21..22]=PC, [23..24]=PD, [25]=BlendCnt, [26]=BlendAlpha, [27]=EVY
void mh_gpu2d(int engine, s32* out) {
    GPU2D::Unit& u = engine ? g_nds->GPU.GPU2D_B : g_nds->GPU.GPU2D_A;
    out[0] = u.DispCnt;
    for (int i = 0; i < 4; i++) { out[1 + i] = u.BGCnt[i]; out[5 + i] = u.BGXPos[i]; out[9 + i] = u.BGYPos[i]; }
    for (int i = 0; i < 2; i++) { out[13 + i] = u.BGXRef[i]; out[15 + i] = u.BGYRef[i]; out[17 + i] = u.BGRotA[i];
                                  out[19 + i] = u.BGRotB[i]; out[21 + i] = u.BGRotC[i]; out[23 + i] = u.BGRotD[i]; }
    out[25] = u.BlendCnt; out[26] = u.BlendAlpha; out[27] = u.EVY;
}
// Lighting state: LightDirection[4][3] (s16), LightColor[4][3], MatDiffuse/Ambient/Specular/Emission[3], SpecRecip[4],
// UseShininessTable, ShininessTable[128], VecMatrix[16]
int mh_lights(s32* out) {
    auto& g = g_nds->GPU.GPU3D; int n = 0;
    for (int i = 0; i < 4; i++) for (int k = 0; k < 3; k++) out[n++] = g.LightDirection[i][k];
    for (int i = 0; i < 4; i++) for (int k = 0; k < 3; k++) out[n++] = g.LightColor[i][k];
    for (int k = 0; k < 3; k++) out[n++] = g.MatDiffuse[k];
    for (int k = 0; k < 3; k++) out[n++] = g.MatAmbient[k];
    for (int k = 0; k < 3; k++) out[n++] = g.MatSpecular[k];
    for (int k = 0; k < 3; k++) out[n++] = g.MatEmission[k];
    for (int i = 0; i < 4; i++) out[n++] = g.SpecRecip[i];
    out[n++] = g.UseShininessTable;
    for (int i = 0; i < 128; i++) out[n++] = g.ShininessTable[i];
    for (int i = 0; i < 16; i++) out[n++] = g.VecMatrix[i];
    return n;
}
// ARM9 registers r0-r15 + CPSR + halted flag
void mh_arm9_regs(u32* out) {
    for (int i = 0; i < 16; i++) out[i] = g_nds->ARM9.R[i];
    out[16] = g_nds->ARM9.CPSR;
    out[17] = g_nds->ARM9.Halted;
}
void mh_verbose(int v) { Platform::g_verbose = v != 0; }
}
