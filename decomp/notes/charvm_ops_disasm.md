# Character VM opcode handlers (ARM9 0x02022A60, jump table 0x02022ADC)

Auto-dumped disassembly of each opcode handler. r8 = script pointer, sb(r9) = fighter object, r4 -> battle globals.
`str r5,[sp,#8]` = yield (stop running script this frame). `ldr r8,[sb,#0x104]` = jump.


## op 0x00  @ 0x2022d28
```
02022d28: add      r0, r8, #2
02022d2c: str      r0, [sb, #0x118]
02022d30: ldr      r0, [sp, #0x1c]
02022d34: add      r8, r8, #0xa
02022d38: strh     r0, [sb, #0x12]
02022d3c: str      r0, [sb, #0x114]
02022d40: b        #0x202632c
```

## op 0x01  @ 0x2022d44
```
02022d44: add      r0, sb, #0x100
02022d48: ldrh     r0, [r0, #0xc]
02022d4c: cmp      r0, #0
02022d50: bne      #0x2022da8
02022d54: ldrh     r0, [sb, #0xe]
02022d58: add      r1, sb, #0xe
02022d5c: orr      r0, r0, #0x100
02022d60: strh     r0, [sb, #0xe]
02022d64: ldrb     r0, [r8, #1]
02022d68: cmp      r0, #0
02022d6c: ldreq    r0, [sb, #0x100]
02022d70: streq    r0, [sb, #0x104]
02022d74: addeq    r8, r0, #0xa
02022d78: beq      #0x2022da8
02022d7c: cmp      r0, #1
02022d80: ldrheq   r0, [r1]
02022d84: ldreq    r8, [sb, #0x104]
02022d88: orreq    r0, r0, #1
02022d8c: strheq   r0, [r1]
02022d90: beq      #0x2022da8
02022d94: mov      r0, #2
02022d98: add      sp, sp, #0x184
02022d9c: strb     r0, [sb, #4]
02022da0: pop      {r4, r5, r6, r7, r8, sb, sl, fp, lr}
02022da4: bx       lr
02022da8: str      r5, [sp, #8]
02022dac: b        #0x202632c
```

## op 0x02  @ 0x2022db0
```
02022db0: ldr      r0, [sp, #0xc]
02022db4: cmp      r0, #0
02022db8: bne      #0x2022fd4
02022dbc: add      r6, r8, #2
02022dc0: bl       #0x2020aa0
02022dc4: cmp      r0, #0
02022dc8: beq      #0x2022dd8
02022dcc: ldrb     r0, [sb, #0x1d]
02022dd0: bl       #0x2020ab0
02022dd4: mov      r6, r0
02022dd8: add      r0, sb, #0x100
02022ddc: ldrh     r0, [r0, #0xe]
02022de0: cmp      r0, #0x25
02022de4: blo      #0x2022e58
02022de8: ldrb     r2, [r6]
02022dec: ldrb     r1, [r6, #1]
02022df0: ldr      r3, [r4]
02022df4: add      r0, sb, #0x44
02022df8: add      r1, r2, r1, lsl #8
02022dfc: ldr      r2, [pc, #0xb74]   ; =0x4f14
02022e00: lsl      r1, r1, #0x10
02022e04: lsr      r1, r1, #0x10
02022e08: add      r2, r3, r2
02022e0c: bl       #0x2020c08
02022e10: movs     r2, r0
02022e14: beq      #0x2022e48
02022e18: add      r1, sb, #0x100
02022e1c: ldrh     r3, [r1, #0xe]
02022e20: ldr      r1, [sb, #0x120]
02022e24: add      r0, sb, #0x124
02022e28: lsl      r3, r3, #0x14
02022e2c: and      r3, r3, #0xff00000
02022e30: orr      r7, r3, #0x10000000
02022e34: ldrh     r3, [r1]
02022e38: ldr      r1, [pc, #0xb3c]   ; =0xfffff
02022e3c: and      r1, r3, r1
02022e40: orr      r1, r7, r1
02022e44: bl       #0x2010fb4
02022e48: add      r0, sb, #0x124
02022e4c: mov      r1, r5
02022e50: bl       #0x2011d54
02022e54: b        #0x2022fb4
02022e58: ldr      r0, [sb, #0x250]
02022e5c: bic      r0, r0, #4
02022e60: str      r0, [sb, #0x250]
02022e64: ldrh     r0, [sb, #0x12]
02022e68: bic      r0, r0, #3
02022e6c: strh     r0, [sb, #0x12]
02022e70: ldrh     r0, [sb, #0xe]
02022e74: ands     r0, r0, #8
02022e78: ldrbeq   r0, [sb, #7]
02022e7c: addeq    r0, r0, #0x40
02022e80: andeq    r0, r0, #0xff
02022e84: asreq    r0, r0, #3
02022e88: andeq    r0, r0, #0xff
02022e8c: beq      #0x2022ea4
02022e90: ldrb     r0, [sb, #0x20]
02022e94: add      r0, r0, #0x40
02022e98: and      r0, r0, #0xff
02022e9c: asr      r0, r0, #3
02022ea0: and      r0, r0, #0xff
02022ea4: cmp      r0, #0x10
02022ea8: ldrhhs   r0, [sb, #0x12]
02022eac: orrhs    r0, r0, #1
02022eb0: strhhs   r0, [sb, #0x12]
02022eb4: ldrh     r0, [sb, #0xe]
02022eb8: ands     r0, r0, #2
02022ebc: beq      #0x2022ed8
02022ec0: ldrh     r0, [sb, #0x12]
02022ec4: bic      r1, r0, #1
02022ec8: eor      r0, r0, #1
02022ecc: and      r0, r0, #1
02022ed0: orr      r0, r1, r0
02022ed4: strh     r0, [sb, #0x12]
02022ed8: ldrh     r0, [sb, #0xe]
02022edc: ands     r0, r0, #4
02022ee0: ldrhne   r0, [sb, #0x12]
02022ee4: orrne    r0, r0, #2
02022ee8: strhne   r0, [sb, #0x12]
02022eec: ldrb     r2, [r6]
02022ef0: ldrb     r1, [r6, #1]
02022ef4: ldr      r3, [r4]
02022ef8: add      r0, sb, #0x44
02022efc: add      r1, r2, r1, lsl #8
02022f00: ldr      r2, [pc, #0xa78]   ; =0x8f38
02022f04: lsl      r1, r1, #0x10
02022f08: lsr      r1, r1, #0x10
02022f0c: add      r2, r3, r2
02022f10: bl       #0x2020c08
02022f14: cmp      r0, #0
02022f18: beq      #0x2022fb4
02022f1c: ldr      r3, [r4]
02022f20: ldr      r1, [pc, #0xa5c]   ; =0xaf38
02022f24: ldr      r0, [pc, #0xa54]   ; =0x8f38
02022f28: add      r2, r3, r1
02022f2c: add      r1, r3, #0x4000
02022f30: ldrb     r1, [r1, #0xde6]
02022f34: add      r0, r3, r0
02022f38: add      r1, r2, r1, lsl #13
02022f3c: blx      #0x20abff0
02022f40: ldr      r1, [sb, #0x120]
02022f44: ldrb     r7, [sb, #0x1a]
02022f48: ldrh     sl, [r1]
02022f4c: ldrb     r1, [sb, #5]
02022f50: ldr      fp, [pc, #0xa24]   ; =0xfffff
02022f54: ldr      r2, [r4]
02022f58: ldr      r3, [pc, #0xa24]   ; =0xaf38
02022f5c: orr      r1, r1, r7, lsl #7
02022f60: add      r3, r2, r3
02022f64: add      r2, r2, #0x4000
02022f68: lsl      r1, r1, #0x14
02022f6c: ldrb     r2, [r2, #0xde6]
02022f70: and      r1, r1, #0xff00000
02022f74: and      sl, sl, fp
02022f78: orr      r1, r1, #0x50000000
02022f7c: add      r0, sb, #0x124
02022f80: orr      r1, sl, r1
02022f84: add      r2, r3, r2, lsl #13
02022f88: bl       #0x2010fb4
02022f8c: ldr      r0, [r4]
02022f90: add      r0, r0, #0x4000
02022f94: ldrb     r1, [r0, #0xde6]
02022f98: add      r1, r1, #1
02022f9c: strb     r1, [r0, #0xde6]
02022fa0: ldr      r0, [r4]
02022fa4: add      r0, r0, #0x4000
02022fa8: ldrb     r1, [r0, #0xde6]
02022fac: and      r1, r1, #3
02022fb0: strb     r1, [r0, #0xde6]
02022fb4: ldrb     r2, [r6, #2]
02022fb8: ldrb     r1, [r6, #3]
02022fbc: add      r0, sb, #0x100
02022fc0: add      r8, r8, #6
02022fc4: add      r1, r2, r1, lsl #8
02022fc8: strh     r1, [r0, #0xc]
02022fcc: str      r5, [sp, #0xc]
02022fd0: b        #0x202632c
02022fd4: bl       #0x2020aa0
02022fd8: cmp      r0, #0
02022fdc: beq      #0x2022fe8
02022fe0: bl       #0x2020b94
02022fe4: sub      r8, r8, #6
02022fe8: str      r5, [sp, #8]
02022fec: b        #0x202632c
```

## op 0x03  @ 0x2022ff0
```
02022ff0: ldr      r0, [sp, #0xc]
02022ff4: cmp      r0, #0
02022ff8: bne      #0x20231bc
02022ffc: ldr      r0, [sb, #0x250]
02023000: bic      r0, r0, #4
02023004: str      r0, [sb, #0x250]
02023008: ldrh     r0, [sb, #0x12]
0202300c: bic      r0, r0, #1
02023010: strh     r0, [sb, #0x12]
02023014: ldrb     r3, [r8, #2]
02023018: ldrb     r1, [r8, #3]
0202301c: ldrb     r6, [r8, #4]
02023020: ldrb     r7, [r8, #5]
02023024: add      r1, r3, r1, lsl #8
02023028: add      r1, r1, r6, lsl #16
0202302c: ldrh     r2, [sb, #0x12]
02023030: ldr      r0, [sb, #0x44]
02023034: add      r1, r1, r7, lsl #24
02023038: add      r1, r0, r1
0202303c: bic      r0, r2, #3
02023040: strh     r0, [sb, #0x12]
02023044: ldrh     r0, [sb, #0xe]
02023048: ands     r0, r0, #8
0202304c: ldrbeq   r0, [sb, #7]
02023050: addeq    r0, r0, #0x40
02023054: andeq    r0, r0, #0xff
02023058: asreq    r0, r0, #3
0202305c: andeq    r0, r0, #0xff
02023060: beq      #0x2023078
02023064: ldrb     r0, [sb, #0x20]
02023068: add      r0, r0, #0x40
0202306c: and      r0, r0, #0xff
02023070: asr      r0, r0, #3
02023074: and      r0, r0, #0xff
02023078: cmp      r0, #0x10
0202307c: blo      #0x20230a0
02023080: ldrh     r2, [sb, #0x12]
02023084: sub      r0, r0, #0x10
02023088: and      r0, r0, #0xff
0202308c: orr      r2, r2, #1
02023090: cmp      r0, #0x10
02023094: strh     r2, [sb, #0x12]
02023098: ldrhs    r0, [sp, #0x20]
0202309c: b        #0x20230a8
020230a0: rsb      r0, r0, #0xf
020230a4: and      r0, r0, #0xff
020230a8: ldrh     r2, [sb, #0xe]
020230ac: ands     r2, r2, #2
020230b0: beq      #0x20230cc
020230b4: ldrh     r2, [sb, #0x12]
020230b8: bic      r3, r2, #1
020230bc: eor      r2, r2, #1
020230c0: and      r2, r2, #1
020230c4: orr      r2, r3, r2
020230c8: strh     r2, [sb, #0x12]
020230cc: ldrh     r2, [sb, #0xe]
020230d0: lsl      r0, r0, #1
020230d4: ands     r2, r2, #4
020230d8: ldrhne   r2, [sb, #0x12]
020230dc: orrne    r2, r2, #2
020230e0: strhne   r2, [sb, #0x12]
020230e4: ldrh     r1, [r1, r0]
020230e8: ldr      r3, [r4]
020230ec: ldr      r2, [pc, #0x88c]   ; =0x8f38
020230f0: add      r0, sb, #0x44
020230f4: add      r2, r3, r2
020230f8: bl       #0x2020c08
020230fc: cmp      r0, #0
02023100: beq      #0x202319c
02023104: ldr      r3, [r4]
02023108: ldr      r1, [pc, #0x874]   ; =0xaf38
0202310c: ldr      r0, [pc, #0x86c]   ; =0x8f38
02023110: add      r2, r3, r1
02023114: add      r1, r3, #0x4000
02023118: ldrb     r1, [r1, #0xde6]
0202311c: add      r0, r3, r0
02023120: add      r1, r2, r1, lsl #13
02023124: blx      #0x20abff0
02023128: ldr      r1, [sb, #0x120]
0202312c: ldrb     r7, [sb, #0x1a]
02023130: ldrb     r6, [sb, #5]
02023134: ldrh     sl, [r1]
02023138: ldr      r2, [r4]
0202313c: ldr      r1, [pc, #0x840]   ; =0xaf38
02023140: orr      r6, r6, r7, lsl #7
02023144: add      r3, r2, r1
02023148: add      r2, r2, #0x4000
0202314c: ldr      r1, [pc, #0x828]   ; =0xfffff
02023150: lsl      r6, r6, #0x14
02023154: ldrb     r2, [r2, #0xde6]
02023158: and      r6, r6, #0xff00000
0202315c: and      r1, sl, r1
02023160: orr      r6, r6, #0x50000000
02023164: add      r0, sb, #0x124
02023168: orr      r1, r1, r6
0202316c: add      r2, r3, r2, lsl #13
02023170: bl       #0x2010fb4
02023174: ldr      r0, [r4]
02023178: add      r0, r0, #0x4000
0202317c: ldrb     r1, [r0, #0xde6]
02023180: add      r1, r1, #1
02023184: strb     r1, [r0, #0xde6]
02023188: ldr      r0, [r4]
0202318c: add      r0, r0, #0x4000
02023190: ldrb     r1, [r0, #0xde6]
02023194: and      r1, r1, #3
02023198: strb     r1, [r0, #0xde6]
0202319c: ldrb     r2, [r8, #6]
020231a0: ldrb     r1, [r8, #7]
020231a4: add      r0, sb, #0x100
020231a8: add      r8, r8, #8
020231ac: add      r1, r2, r1, lsl #8
020231b0: strh     r1, [r0, #0xc]
020231b4: str      r5, [sp, #0xc]
020231b8: b        #0x202632c
020231bc: str      r5, [sp, #8]
020231c0: b        #0x202632c
```

## op 0x04  @ 0x20231c4
```
020231c4: ldrh     r0, [sb, #0xe]
020231c8: add      r8, r8, #2
020231cc: ands     r0, r0, #8
020231d0: ldrbeq   r0, [sb, #7]
020231d4: addeq    r0, r0, #0x40
020231d8: andeq    r0, r0, #0xff
020231dc: asreq    r0, r0, #3
020231e0: andeq    r1, r0, #0xff
020231e4: beq      #0x20231fc
020231e8: ldrb     r0, [sb, #0x20]
020231ec: add      r0, r0, #0x40
020231f0: and      r0, r0, #0xff
020231f4: asr      r0, r0, #3
020231f8: and      r1, r0, #0xff
020231fc: cmp      r1, #0x10
02023200: subhs    r0, r1, #0x10
02023204: andhs    r1, r0, #0xff
02023208: rsblo    r0, r1, #0xf
0202320c: andlo    r1, r0, #0xff
02023210: add      r0, r8, r1, lsl #2
02023214: ldrb     r2, [r8, r1, lsl #2]
02023218: ldrb     r6, [r0, #3]
0202321c: ldrb     r3, [r0, #2]
02023220: ldrb     r0, [r0, #1]
02023224: ldr      r7, [sb, #0x44]
02023228: add      r1, sb, #0x100
0202322c: add      r0, r2, r0, lsl #8
02023230: add      r0, r0, r3, lsl #16
02023234: add      r0, r0, r6, lsl #24
02023238: add      r0, r7, r0
0202323c: str      r0, [sb, #0x100]
02023240: ldr      r0, [sb, #0x100]
02023244: str      r0, [sb, #0x104]
02023248: ldr      r0, [sp, #0x24]
0202324c: strh     r0, [r1, #0xc]
02023250: ldr      r8, [sb, #0x104]
02023254: b        #0x202632c
```

## op 0x05  @ 0x2023258
```
02023258: ldrb     r3, [r8, #2]
0202325c: ldrb     r2, [r8, #3]
02023260: ldrb     r6, [r8, #4]
02023264: ldrb     r7, [r8, #5]
02023268: add      r2, r3, r2, lsl #8
0202326c: add      r2, r2, r6, lsl #16
02023270: ldr      r0, [sb, #0x44]
02023274: add      r2, r2, r7, lsl #24
02023278: add      r0, r0, r2
0202327c: str      r0, [sb, #0x100]
02023280: ldr      r0, [sb, #0x100]
02023284: add      r1, sb, #0x100
02023288: str      r0, [sb, #0x104]
0202328c: ldr      r0, [sp, #0x28]
02023290: strh     r0, [r1, #0xc]
02023294: ldr      r8, [sb, #0x104]
02023298: b        #0x202632c
```

## op 0x06  @ 0x202329c
```
0202329c: ldrb     r6, [r8, #5]
020232a0: ldrb     r3, [r8, #4]
020232a4: ldrb     r1, [r8, #2]
020232a8: ldrb     r0, [r8, #3]
020232ac: ldrb     r2, [r8, #9]
020232b0: ldrb     sl, [r8, #8]
020232b4: add      r0, r1, r0, lsl #8
020232b8: add      r0, r0, r3, lsl #16
020232bc: add      r6, r0, r6, lsl #24
020232c0: ldrb     r7, [r8, #6]
020232c4: ldrb     r3, [r8, #7]
020232c8: mov      r0, sb
020232cc: ldrb     r1, [r8, #1]
020232d0: add      r3, r7, r3, lsl #8
020232d4: add      r3, r3, sl, lsl #16
020232d8: add      r7, r3, r2, lsl #24
020232dc: bl       #0x202247c
020232e0: cmp      r0, #0
020232e4: beq      #0x20232f8
020232e8: ldr      r3, [sp, #0x2c]
020232ec: mov      r1, r6
020232f0: mov      r2, r7
020232f4: bl       #0x202216c
020232f8: add      r8, r8, #0xa
020232fc: b        #0x202632c
```

## op 0x07  @ 0x2023300
```
02023300: ldrb     r2, [r8, #2]
02023304: ldrb     r1, [r8, #3]
02023308: ldrb     r3, [r8, #4]
0202330c: ldrb     r6, [r8, #5]
02023310: add      r1, r2, r1, lsl #8
02023314: add      r1, r1, r3, lsl #16
02023318: add      r6, r1, r6, lsl #24
0202331c: add      r1, sb, #0x100
02023320: ldrh     r1, [r1, #0xe]
02023324: ldrb     r3, [r8, #6]
02023328: ldrb     r2, [r8, #7]
0202332c: ldrb     r7, [r8, #8]
02023330: ldrb     r0, [r8, #9]
02023334: add      r2, r3, r2, lsl #8
02023338: cmp      r1, #0x25
0202333c: ldrlo    r3, [sb, #0x244]
02023340: add      r2, r2, r7, lsl #16
02023344: add      r7, r2, r0, lsl #24
02023348: addlo    r2, sb, #0x164
0202334c: ldrhs    r3, [sb, #0x40]
02023350: ldr      r0, [sp, #0x30]
02023354: addhs    r2, sb, #0x44
02023358: str      r0, [sp]
0202335c: ldrb     r1, [r8, #1]
02023360: mov      r0, sb
02023364: bl       #0x20225c8
02023368: cmp      r0, #0
0202336c: beq      #0x2023380
02023370: ldr      r3, [sp, #0x34]
02023374: mov      r1, r6
02023378: mov      r2, r7
0202337c: bl       #0x202216c
02023380: add      r8, r8, #0xa
02023384: b        #0x202632c
```

## op 0x08  @ 0x2023388
```
02023388: add      r0, sb, #0x124
0202338c: ldrb     r2, [r8, #1]
02023390: add      r1, sb, #0x100
02023394: ldrh     r1, [r1, #0xa]
02023398: add      r1, r1, r2, lsl #5
0202339c: lsl      r1, r1, #0x10
020233a0: lsr      r1, r1, #0x10
020233a4: bl       #0x2010ad8
020233a8: add      r0, sb, #0x124
020233ac: mov      r1, r5
020233b0: bl       #0x2011d54
020233b4: add      r8, r8, #2
020233b8: b        #0x202632c
```

## op 0x09  @ 0x20233bc
```
020233bc: ldrh     r0, [sb, #0xe]
020233c0: ands     r1, r0, #2
020233c4: orreq    r0, r0, #2
020233c8: strheq   r0, [sb, #0xe]
020233cc: ldrheq   r0, [sb, #0x12]
020233d0: orreq    r0, r0, #1
020233d4: strheq   r0, [sb, #0x12]
020233d8: beq      #0x20233f0
020233dc: bic      r0, r0, #2
020233e0: strh     r0, [sb, #0xe]
020233e4: ldrh     r0, [sb, #0x12]
020233e8: bic      r0, r0, #1
020233ec: strh     r0, [sb, #0x12]
020233f0: add      r8, r8, #2
020233f4: b        #0x202632c
```

## op 0x0a  @ 0x20233f8
```
020233f8: ldrh     r0, [sb, #0xe]
020233fc: ands     r1, r0, #4
02023400: orreq    r0, r0, #4
02023404: strheq   r0, [sb, #0xe]
02023408: ldrheq   r0, [sb, #0x12]
0202340c: orreq    r0, r0, #2
02023410: strheq   r0, [sb, #0x12]
02023414: beq      #0x202342c
02023418: bic      r0, r0, #4
0202341c: strh     r0, [sb, #0xe]
02023420: ldrh     r0, [sb, #0x12]
02023424: bic      r0, r0, #2
02023428: strh     r0, [sb, #0x12]
0202342c: add      r8, r8, #2
02023430: b        #0x202632c
```

## op 0x0b  @ 0x2023434
```
02023434: mov      r0, sb
02023438: ldrb     r1, [r8, #1]
0202343c: bl       #0x2029eb8
02023440: add      r8, r8, #2
02023444: b        #0x202632c
```

## op 0x0c  @ 0x2023448
```
02023448: mov      r0, sb
0202344c: ldrb     r1, [r8, #1]
02023450: bl       #0x2029e3c
02023454: add      r8, r8, #2
02023458: b        #0x202632c
```

## op 0x0d  @ 0x202345c
```
0202345c: add      r0, sb, #0x100
02023460: ldrh     r0, [r0, #0xe]
02023464: cmp      r0, #0x25
02023468: ldrlo    r0, [sb, #0x250]
0202346c: orrlo    r0, r0, #0x200
02023470: strlo    r0, [sb, #0x250]
02023474: ldrb     r1, [r8, #1]
02023478: add      r0, sb, #0x124
0202347c: bl       #0x2011d5c
02023480: add      r8, r8, #2
02023484: b        #0x202632c
```

## op 0x0e  @ 0x2023488
```
02023488: add      r6, r8, #2
0202348c: bl       #0x2020aa0
02023490: cmp      r0, #0
02023494: beq      #0x20234a4
02023498: ldrb     r0, [sb, #0x1d]
0202349c: bl       #0x2020ab0
020234a0: mov      r6, r0
020234a4: ldrb     r1, [sb, #7]
020234a8: mov      r0, sb
020234ac: str      r1, [sp]
020234b0: ldrb     r7, [r6]
020234b4: ldrb     r1, [r6, #1]
020234b8: ldrb     r3, [r6, #2]
020234bc: ldrb     r2, [r6, #3]
020234c0: add      r1, r7, r1, lsl #8
020234c4: lsl      r1, r1, #0x10
020234c8: add      r2, r3, r2, lsl #8
020234cc: asr      r1, r1, #0x10
020234d0: lsl      r2, r2, #0x10
020234d4: asr      r2, r2, #0x10
020234d8: ldrb     r7, [r6, #4]
020234dc: ldrb     r3, [r6, #5]
020234e0: add      r3, r7, r3, lsl #8
020234e4: lsl      r3, r3, #0x10
020234e8: asr      r3, r3, #0x10
020234ec: bl       #0x20213a8
020234f0: add      r8, r8, #8
020234f4: b        #0x202632c
```

## op 0x0f  @ 0x20234f8
```
020234f8: ldrh     r0, [sb, #0x10]
020234fc: orr      r0, r0, #2
02023500: strh     r0, [sb, #0x10]
02023504: ldrb     r1, [r8, #2]
02023508: ldrb     r0, [r8, #3]
0202350c: add      r8, r8, #4
02023510: add      r0, r1, r0, lsl #8
02023514: strh     r0, [sb, #0x18]
02023518: b        #0x202632c
```

## op 0x10  @ 0x202351c
```
0202351c: add      r8, r8, #2
02023520: ldrh     r0, [sb, #0x12]
02023524: orr      r0, r0, #8
02023528: strh     r0, [sb, #0x12]
0202352c: b        #0x202632c
```

## op 0x11  @ 0x2023530
```
02023530: ldr      r0, [sp, #0xc]
02023534: cmp      r0, #0
02023538: strne    r5, [sp, #8]
0202353c: bne      #0x202632c
02023540: ldrb     r2, [r8, #2]
02023544: ldrb     r1, [r8, #3]
02023548: add      r0, sb, #0x100
0202354c: add      r8, r8, #4
02023550: add      r1, r2, r1, lsl #8
02023554: and      r1, r1, #0xff
02023558: strh     r1, [r0, #0x12]
0202355c: str      r5, [sp, #0xc]
02023560: b        #0x202632c
```

## op 0x12  @ 0x2023564
```
02023564: ldr      r0, [sp, #0xc]
02023568: cmp      r0, #0
0202356c: bne      #0x20235ec
02023570: add      r1, sb, #0x100
02023574: ldrh     r0, [r1, #0x12]
02023578: cmp      r0, #0
0202357c: addeq    r8, r8, #6
02023580: beq      #0x20235cc
02023584: ldrb     r3, [r8, #2]
02023588: ldrb     r2, [r8, #3]
0202358c: ldrb     r6, [r8, #4]
02023590: ldrb     r7, [r8, #5]
02023594: add      r2, r3, r2, lsl #8
02023598: add      r2, r2, r6, lsl #16
0202359c: ldr      r0, [sb, #0x44]
020235a0: add      r2, r2, r7, lsl #24
020235a4: add      r0, r0, r2
020235a8: str      r0, [sb, #0x100]
020235ac: ldr      r0, [sb, #0x100]
020235b0: str      r0, [sb, #0x104]
020235b4: ldr      r0, [sp, #0x38]
020235b8: strh     r0, [r1, #0xc]
020235bc: ldrh     r0, [r1, #0x12]
020235c0: ldr      r8, [sb, #0x104]
020235c4: sub      r0, r0, #1
020235c8: strh     r0, [r1, #0x12]
020235cc: ldrb     r0, [r8]
020235d0: cmp      r0, #2
020235d4: beq      #0x202632c
020235d8: cmp      r0, #3
020235dc: beq      #0x202632c
020235e0: cmp      r0, #0x25
020235e4: strne    r5, [sp, #8]
020235e8: b        #0x202632c
020235ec: str      r5, [sp, #8]
020235f0: b        #0x202632c
```

## op 0x13  @ 0x20235f4
```
020235f4: add      r6, r8, #2
020235f8: bl       #0x2020aa0
020235fc: cmp      r0, #0
02023600: beq      #0x2023610
02023604: ldrb     r0, [sb, #0x1d]
02023608: bl       #0x2020ab0
0202360c: mov      r6, r0
02023610: ldrb     r3, [r6]
02023614: ldrb     r0, [r6, #1]
02023618: ldrb     r2, [r6, #2]
0202361c: ldrb     r1, [r6, #3]
02023620: add      r0, r3, r0, lsl #8
02023624: lsl      r0, r0, #0x10
02023628: add      r2, r2, r1, lsl #8
0202362c: lsrs     r1, r0, #0x10
02023630: lsl      r0, r2, #0x10
02023634: lsr      r2, r0, #0x10
02023638: moveq    r1, r5
0202363c: cmp      r2, #0
02023640: moveq    r2, r5
02023644: add      r0, sb, #0x124
02023648: bl       #0x2011e44
0202364c: add      r8, r8, #6
02023650: b        #0x202632c
```

## op 0x14  @ 0x2023654
```
02023654: add      r6, r8, #1
02023658: bl       #0x2020aa0
0202365c: cmp      r0, #0
02023660: beq      #0x2023670
02023664: ldrb     r0, [sb, #0x1d]
02023668: bl       #0x2020ab0
0202366c: mov      r6, r0
02023670: ldrb     r1, [r6]
02023674: add      r0, sb, #0x124
02023678: bl       #0x2011f2c
0202367c: add      r8, r8, #2
02023680: b        #0x202632c
```

## op 0x15  @ 0x2023684
```
02023684: add      r6, r8, #2
02023688: bl       #0x2020aa0
0202368c: cmp      r0, #0
02023690: beq      #0x20236a0
02023694: ldrb     r0, [sb, #0x1d]
02023698: bl       #0x2020ab0
0202369c: mov      r6, r0
020236a0: add      r0, sb, #0x124
020236a4: ldrb     r7, [r6]
020236a8: ldrb     r1, [r6, #1]
020236ac: ldrb     r3, [r6, #2]
020236b0: ldrb     r2, [r6, #3]
020236b4: add      r1, r7, r1, lsl #8
020236b8: lsl      r1, r1, #0x10
020236bc: add      r2, r3, r2, lsl #8
020236c0: asr      r1, r1, #0x10
020236c4: lsl      r2, r2, #0x10
020236c8: asr      r2, r2, #0x10
020236cc: bl       #0x2011d68
020236d0: add      r8, r8, #6
020236d4: b        #0x202632c
```

## op 0x16  @ 0x20236d8
```
020236d8: add      r6, r8, #2
020236dc: bl       #0x2020aa0
020236e0: cmp      r0, #0
020236e4: beq      #0x20236f4
020236e8: ldrb     r0, [sb, #0x1d]
020236ec: bl       #0x2020ab0
020236f0: mov      r6, r0
020236f4: add      r0, sb, #0x124
020236f8: ldrb     r2, [r6]
020236fc: ldrb     r1, [r6, #1]
02023700: add      r1, r2, r1, lsl #8
02023704: lsl      r1, r1, #0x10
02023708: asr      r1, r1, #0x10
0202370c: bl       #0x2011ee4
02023710: add      r8, r8, #4
02023714: b        #0x202632c
```

## op 0x17  @ 0x202632c
```
invalid
```

## op 0x18  @ 0x2023718
```
02023718: add      r8, r8, #2
0202371c: b        #0x202632c
```

## op 0x19  @ 0x2023720
```
02023720: add      r8, r8, #6
02023724: b        #0x202632c
```

## op 0x1a  @ 0x2023728
```
02023728: add      r8, r8, #2
0202372c: b        #0x202632c
```

## op 0x1b  @ 0x2023730
```
02023730: add      r0, sb, #0x124
02023734: ldrb     r1, [r8, #1]
02023738: bl       #0x2011d54
0202373c: add      r8, r8, #2
02023740: b        #0x202632c
```

## op 0x1c  @ 0x2023744
```
02023744: ldrb     r0, [sb, #0x1a]
02023748: bl       #0x2027bd0
0202374c: movs     r7, r0
02023750: beq      #0x20237bc
02023754: add      r6, r8, #2
02023758: bl       #0x2020aa0
0202375c: cmp      r0, #0
02023760: beq      #0x2023770
02023764: ldrb     r0, [sb, #0x1d]
02023768: bl       #0x2020ab0
0202376c: mov      r6, r0
02023770: ldr      r0, [r7, #0x38]
02023774: ldr      r3, [r7, #0x3c]
02023778: ldrb     sl, [r6]
0202377c: ldrb     r7, [r6, #1]
02023780: ldrb     r2, [r6, #2]
02023784: ldrb     r1, [r6, #3]
02023788: add      r6, sl, r7, lsl #8
0202378c: add      r6, r6, r0, asr #8
02023790: add      r0, r2, r1, lsl #8
02023794: add      r1, r0, r3, asr #8
02023798: lsl      r0, r6, #0x10
0202379c: asr      r2, r0, #0x10
020237a0: lsl      r0, r1, #0x10
020237a4: cmp      sb, #0
020237a8: asr      r1, r0, #0x10
020237ac: lslne    r0, r2, #8
020237b0: strne    r0, [sb, #0x38]
020237b4: lslne    r0, r1, #8
020237b8: strne    r0, [sb, #0x3c]
020237bc: add      r8, r8, #6
020237c0: b        #0x202632c
```

## op 0x1d  @ 0x20237c4
```
020237c4: ldrb     r0, [sb, #0x1a]
020237c8: bl       #0x2027bd0
020237cc: movs     r6, r0
020237d0: beq      #0x2023858
020237d4: add      r7, r8, #1
020237d8: bl       #0x2020aa0
020237dc: cmp      r0, #0
020237e0: beq      #0x20237f0
020237e4: ldrb     r0, [sb, #0x1d]
020237e8: bl       #0x2020ab0
020237ec: mov      r7, r0
020237f0: ldrb     r2, [r7, #2]
020237f4: ldrb     r1, [r7]
020237f8: ldrb     r0, [r7, #1]
020237fc: rsb      r2, r2, #0x100
02023800: and      r2, r2, #0xff
02023804: add      r0, r1, r0, lsl #8
02023808: lsl      r0, r0, #0x10
0202380c: lsr      r1, r0, #0x10
02023810: add      r0, r2, #0x40
02023814: and      r0, r0, #0xff
02023818: lsl      r3, r0, #1
0202381c: ldr      r0, [pc, #0x164]   ; =0x20b64d4
02023820: and      r2, r2, #0xff
02023824: ldrsh    r0, [r0, r3]
02023828: lsl      r3, r2, #1
0202382c: ldr      r2, [pc, #0x154]   ; =0x20b64d4
02023830: cmp      sb, #0
02023834: ldrsh    r2, [r2, r3]
02023838: ldr      r3, [r6, #0x38]
0202383c: mla      r3, r1, r0, r3
02023840: str      r3, [sp, #0x13c]
02023844: ldr      r0, [r6, #0x3c]
02023848: mla      r0, r1, r2, r0
0202384c: str      r0, [sp, #0x140]
02023850: strne    r3, [sb, #0x38]
02023854: strne    r0, [sb, #0x3c]
02023858: add      r8, r8, #4
0202385c: b        #0x202632c
```

## op 0x1e  @ 0x2023860
```
02023860: ldr      r7, [sb]
02023864: cmp      r7, #0
02023868: beq      #0x20238d4
0202386c: add      r6, r8, #2
02023870: bl       #0x2020aa0
02023874: cmp      r0, #0
02023878: beq      #0x2023888
0202387c: ldrb     r0, [sb, #0x1d]
02023880: bl       #0x2020ab0
02023884: mov      r6, r0
02023888: ldr      r0, [r7, #0x38]
0202388c: ldr      r3, [r7, #0x3c]
02023890: ldrb     sl, [r6]
02023894: ldrb     r7, [r6, #1]
02023898: ldrb     r2, [r6, #2]
0202389c: ldrb     r1, [r6, #3]
020238a0: add      r6, sl, r7, lsl #8
020238a4: add      r6, r6, r0, asr #8
020238a8: add      r0, r2, r1, lsl #8
020238ac: add      r1, r0, r3, asr #8
020238b0: lsl      r0, r6, #0x10
020238b4: asr      r2, r0, #0x10
020238b8: lsl      r0, r1, #0x10
020238bc: cmp      sb, #0
020238c0: asr      r1, r0, #0x10
020238c4: lslne    r0, r2, #8
020238c8: strne    r0, [sb, #0x38]
020238cc: lslne    r0, r1, #8
020238d0: strne    r0, [sb, #0x3c]
020238d4: add      r8, r8, #6
020238d8: b        #0x202632c
```

## op 0x1f  @ 0x20238dc
```
020238dc: ldr      r6, [sb]
020238e0: cmp      r6, #0
020238e4: beq      #0x202396c
020238e8: add      r7, r8, #1
020238ec: bl       #0x2020aa0
020238f0: cmp      r0, #0
020238f4: beq      #0x2023904
020238f8: ldrb     r0, [sb, #0x1d]
020238fc: bl       #0x2020ab0
02023900: mov      r7, r0
02023904: ldrb     r2, [r7, #2]
02023908: ldrb     r1, [r7]
0202390c: ldrb     r0, [r7, #1]
02023910: rsb      r2, r2, #0x100
02023914: and      r2, r2, #0xff
02023918: add      r0, r1, r0, lsl #8
0202391c: lsl      r0, r0, #0x10
02023920: lsr      r1, r0, #0x10
02023924: add      r0, r2, #0x40
02023928: and      r0, r0, #0xff
0202392c: lsl      r3, r0, #1
02023930: ldr      r0, [pc, #0x50]   ; =0x20b64d4
02023934: and      r2, r2, #0xff
02023938: ldrsh    r0, [r0, r3]
0202393c: lsl      r3, r2, #1
02023940: ldr      r2, [pc, #0x40]   ; =0x20b64d4
02023944: cmp      sb, #0
02023948: ldrsh    r2, [r2, r3]
0202394c: ldr      r3, [r6, #0x38]
02023950: mla      r3, r1, r0, r3
02023954: str      r3, [sp, #0x144]
02023958: ldr      r0, [r6, #0x3c]
0202395c: mla      r0, r1, r2, r0
02023960: str      r0, [sp, #0x148]
02023964: strne    r3, [sb, #0x38]
02023968: strne    r0, [sb, #0x3c]
0202396c: add      r8, r8, #4
02023970: b        #0x202632c
02023974: andeq    lr, sp, #204, #6
02023978: andeq    r4, r0, r4, lsl pc
```

## op 0x20  @ 0x202398c
```
0202398c: ldrb     r1, [r8, #2]
02023990: ldrb     r0, [r8, #3]
02023994: add      r0, r1, r0, lsl #8
02023998: lsl      r0, r0, #0x10
0202399c: lsr      r0, r0, #0x10
020239a0: bl       #0x2018ee4
020239a4: add      r8, r8, #4
020239a8: b        #0x202632c
```

## op 0x21  @ 0x20239ac
```
020239ac: add      r0, sb, #0x100
020239b0: ldrh     r0, [r0, #0xe]
020239b4: cmp      r0, #0x25
020239b8: bhs      #0x20239dc
020239bc: mov      r0, sb
020239c0: ldrb     r2, [r8, #2]
020239c4: ldrb     r1, [r8, #3]
020239c8: add      r1, r2, r1, lsl #8
020239cc: lsl      r1, r1, #0x10
020239d0: lsr      r1, r1, #0x10
020239d4: bl       #0x2019104
020239d8: b        #0x20239f8
020239dc: mov      r0, sb
020239e0: ldrb     r2, [r8, #2]
020239e4: ldrb     r1, [r8, #3]
020239e8: add      r1, r2, r1, lsl #8
020239ec: lsl      r1, r1, #0x10
020239f0: lsr      r1, r1, #0x10
020239f4: bl       #0x2018fb8
020239f8: add      r8, r8, #4
020239fc: b        #0x202632c
```

## op 0x22  @ 0x2023a00
```
02023a00: add      r8, r8, #2
02023a04: bl       #0x2019044
02023a08: b        #0x202632c
```

## op 0x23  @ 0x2023a0c
```
02023a0c: ldrb     r0, [sb, #0x1a]
02023a10: bl       #0x2027bd0
02023a14: cmp      r0, #0
02023a18: beq      #0x2023a34
02023a1c: ldrb     r2, [r8, #2]
02023a20: ldrb     r1, [r8, #3]
02023a24: add      r1, r2, r1, lsl #8
02023a28: lsl      r1, r1, #0x10
02023a2c: lsr      r1, r1, #0x10
02023a30: bl       #0x2019104
02023a34: add      r8, r8, #4
02023a38: b        #0x202632c
```

## op 0x24  @ 0x2023a3c
```
02023a3c: add      r6, r8, #2
02023a40: bl       #0x2020aa0
02023a44: cmp      r0, #0
02023a48: beq      #0x2023a58
02023a4c: ldrb     r0, [sb, #0x1d]
02023a50: bl       #0x2020ab0
02023a54: mov      r6, r0
02023a58: ldr      r0, [sb, #0x38]
02023a5c: ldr      r1, [sb, #0x3c]
02023a60: lsl      r0, r0, #8
02023a64: asr      r7, r0, #0x10
02023a68: ldrb     r3, [r6]
02023a6c: ldrb     r0, [r6, #1]
02023a70: lsl      r1, r1, #8
02023a74: ldrb     r2, [r6, #2]
02023a78: add      r0, r3, r0, lsl #8
02023a7c: asr      r3, r1, #0x10
02023a80: ldrb     r1, [r6, #3]
02023a84: lsl      r0, r0, #0x10
02023a88: add      r0, r7, r0, asr #16
02023a8c: add      r1, r2, r1, lsl #8
02023a90: lsl      r1, r1, #0x10
02023a94: lsl      r0, r0, #0x10
02023a98: add      r1, r3, r1, asr #16
02023a9c: lsl      r1, r1, #0x10
02023aa0: asr      r0, r0, #0x10
02023aa4: cmp      sb, #0
02023aa8: lslne    r0, r0, #8
02023aac: asr      r1, r1, #0x10
02023ab0: strne    r0, [sb, #0x38]
02023ab4: lslne    r0, r1, #8
02023ab8: strne    r0, [sb, #0x3c]
02023abc: add      r8, r8, #6
02023ac0: b        #0x202632c
```

## op 0x25  @ 0x2023ac4
```
02023ac4: ldr      r0, [sp, #0xc]
02023ac8: cmp      r0, #0
02023acc: bne      #0x2023b24
02023ad0: add      r6, r8, #2
02023ad4: bl       #0x2020aa0
02023ad8: cmp      r0, #0
02023adc: beq      #0x2023aec
02023ae0: ldrb     r0, [sb, #0x1d]
02023ae4: bl       #0x2020ab0
02023ae8: mov      r6, r0
02023aec: add      r0, sb, #0x100
02023af0: ldrh     r0, [r0, #0xe]
02023af4: add      r8, r8, #4
02023af8: str      r5, [sp, #0xc]
02023afc: cmp      r0, #0x25
02023b00: ldrlo    r0, [sb, #0x250]
02023b04: biclo    r0, r0, #4
02023b08: strlo    r0, [sb, #0x250]
02023b0c: ldrb     r2, [r6]
02023b10: ldrb     r1, [r6, #1]
02023b14: add      r0, sb, #0x100
02023b18: add      r1, r2, r1, lsl #8
02023b1c: strh     r1, [r0, #0xc]
02023b20: b        #0x202632c
02023b24: bl       #0x2020aa0
02023b28: cmp      r0, #0
02023b2c: beq      #0x2023b38
02023b30: bl       #0x2020b94
02023b34: sub      r8, r8, #6
02023b38: str      r5, [sp, #8]
02023b3c: b        #0x202632c
```

## op 0x26  @ 0x2023b40
```
02023b40: add      r7, r8, #2
02023b44: bl       #0x2020aa0
02023b48: cmp      r0, #0
02023b4c: beq      #0x2023b5c
02023b50: ldrb     r0, [sb, #0x1d]
02023b54: bl       #0x2020ab0
02023b58: mov      r7, r0
02023b5c: add      r0, sb, #0x124
02023b60: ldrb     r6, [r7]
02023b64: ldrb     r3, [r7, #1]
02023b68: add      r1, sb, #0x100
02023b6c: ldrh     r2, [r1, #0x56]
02023b70: add      r1, r6, r3, lsl #8
02023b74: lsl      r1, r1, #0x10
02023b78: lsr      r1, r1, #0x10
02023b7c: bl       #0x2011e44
02023b80: add      r8, r8, #4
02023b84: b        #0x202632c
```

## op 0x27  @ 0x2023b88
```
02023b88: add      r6, r8, #2
02023b8c: bl       #0x2020aa0
02023b90: cmp      r0, #0
02023b94: beq      #0x2023ba4
02023b98: ldrb     r0, [sb, #0x1d]
02023b9c: bl       #0x2020ab0
02023ba0: mov      r6, r0
02023ba4: add      r0, sb, #0x124
02023ba8: add      r1, sb, #0x100
02023bac: ldrh     r1, [r1, #0x54]
02023bb0: ldrb     r3, [r6]
02023bb4: ldrb     r2, [r6, #1]
02023bb8: add      r2, r3, r2, lsl #8
02023bbc: lsl      r2, r2, #0x10
02023bc0: lsr      r2, r2, #0x10
02023bc4: bl       #0x2011e44
02023bc8: add      r8, r8, #4
02023bcc: b        #0x202632c
```

## op 0x28  @ 0x2023bd0
```
02023bd0: add      r6, r8, #1
02023bd4: bl       #0x2020aa0
02023bd8: cmp      r0, #0
02023bdc: beq      #0x2023bec
02023be0: ldrb     r0, [sb, #0x1d]
02023be4: bl       #0x2020ab0
02023be8: mov      r6, r0
02023bec: ldrb     r2, [r6]
02023bf0: ldr      r1, [sp, #0x3c]
02023bf4: add      r0, sb, #0x124
02023bf8: rsb      r2, r2, #0x100
02023bfc: and      r3, r2, #0xff
02023c00: mov      r2, r1
02023c04: bl       #0x2011f74
02023c08: add      r8, r8, #2
02023c0c: b        #0x202632c
```

## op 0x29  @ 0x2023c10
```
02023c10: add      r6, r8, #1
02023c14: bl       #0x2020aa0
02023c18: cmp      r0, #0
02023c1c: beq      #0x2023c2c
02023c20: ldrb     r0, [sb, #0x1d]
02023c24: bl       #0x2020ab0
02023c28: mov      r6, r0
02023c2c: ldr      r1, [sp, #0x40]
02023c30: ldrb     r3, [r6]
02023c34: add      r0, sb, #0x124
02023c38: mov      r2, r1
02023c3c: bl       #0x2011f38
02023c40: add      r8, r8, #2
02023c44: b        #0x202632c
```

## op 0x2a  @ 0x2023c48
```
02023c48: ldr      r0, [sb]
02023c4c: cmp      r0, #0
02023c50: beq      #0x2023c84
02023c54: ldrb     r0, [r0, #7]
02023c58: ldrb     r6, [r8, #1]
02023c5c: rsb      r0, r0, #0x100
02023c60: and      r0, r0, #0xff
02023c64: mov      r1, r6
02023c68: bl       #0x20b5e30
02023c6c: mul      r0, r6, r0
02023c70: ldr      r1, [sp, #0x44]
02023c74: and      r3, r0, #0xff
02023c78: add      r0, sb, #0x124
02023c7c: mov      r2, r1
02023c80: bl       #0x2011f74
02023c84: add      r8, r8, #2
02023c88: b        #0x202632c
```

## op 0x2b  @ 0x2023c8c
```
02023c8c: ldr      r0, [r4]
02023c90: ldrb     r2, [r8, #2]
02023c94: add      r0, r0, #0x4d00
02023c98: ldrsh    r3, [r0, #0xee]
02023c9c: ldrb     r0, [r8, #3]
02023ca0: ldr      r1, [sb, #0x3c]
02023ca4: add      r0, r2, r0, lsl #8
02023ca8: lsl      r0, r0, #0x10
02023cac: sub      r0, r3, r0, asr #16
02023cb0: cmp      r0, r1, asr #8
02023cb4: addle    r8, r8, #4
02023cb8: strgt    r5, [sp, #8]
02023cbc: b        #0x202632c
```

## op 0x2c  @ 0x2023cc0
```
02023cc0: add      r6, r8, #1
02023cc4: bl       #0x2020aa0
02023cc8: cmp      r0, #0
02023ccc: beq      #0x2023cdc
02023cd0: ldrb     r0, [sb, #0x1d]
02023cd4: bl       #0x2020ab0
02023cd8: mov      r6, r0
02023cdc: ldrb     r1, [r6, #6]
02023ce0: mov      r0, sb
02023ce4: str      r1, [sp]
02023ce8: ldrb     r7, [r6]
02023cec: ldrb     r1, [r6, #1]
02023cf0: ldrb     r3, [r6, #2]
02023cf4: ldrb     r2, [r6, #3]
02023cf8: add      r1, r7, r1, lsl #8
02023cfc: lsl      r1, r1, #0x10
02023d00: add      r2, r3, r2, lsl #8
02023d04: asr      r1, r1, #0x10
02023d08: lsl      r2, r2, #0x10
02023d0c: asr      r2, r2, #0x10
02023d10: ldrb     r7, [r6, #4]
02023d14: ldrb     r3, [r6, #5]
02023d18: add      r3, r7, r3, lsl #8
02023d1c: lsl      r3, r3, #0x10
02023d20: asr      r3, r3, #0x10
02023d24: bl       #0x20213a8
02023d28: add      r8, r8, #8
02023d2c: b        #0x202632c
```

## op 0x2d  @ 0x2023d30
```
02023d30: add      r8, r8, #2
02023d34: ldrh     r0, [sb, #0xe]
02023d38: orr      r0, r0, #0x20
02023d3c: strh     r0, [sb, #0xe]
02023d40: b        #0x202632c
```

## op 0x2e  @ 0x2023d44
```
02023d44: add      r0, sb, #0x100
02023d48: ldrh     r0, [r0, #0xe]
02023d4c: cmp      r0, #0x25
02023d50: bhs      #0x2023dac
02023d54: ldrb     r0, [sb, #6]
02023d58: cmp      r0, #0x5a
02023d5c: blo      #0x2023d8c
02023d60: cmp      r0, #0x66
02023d64: bhi      #0x2023d8c
02023d68: ldrb     r3, [r8, #2]
02023d6c: ldrb     r1, [r8, #3]
02023d70: ldr      r2, [sp, #0x48]
02023d74: mov      r0, sb
02023d78: add      r1, r3, r1, lsl #8
02023d7c: lsl      r1, r1, #0x10
02023d80: lsr      r1, r1, #0x10
02023d84: bl       #0x20293a4
02023d88: b        #0x2023dac
02023d8c: ldrb     r3, [r8, #2]
02023d90: ldrb     r1, [r8, #3]
02023d94: ldr      r2, [sp, #0x4c]
02023d98: mov      r0, sb
02023d9c: add      r1, r3, r1, lsl #8
02023da0: lsl      r1, r1, #0x10
02023da4: lsr      r1, r1, #0x10
02023da8: bl       #0x20293a4
02023dac: add      r8, r8, #6
02023db0: b        #0x202632c
```

## op 0x2f  @ 0x2023db4
```
02023db4: ldr      r1, [r4]
02023db8: ldrb     r0, [sb, #0x1a]
02023dbc: add      r1, r1, #0x4d00
02023dc0: ldrsh    r7, [r1, #0xec]
02023dc4: ldrsh    r2, [r1, #0xe8]
02023dc8: ldrsh    r6, [r1, #0xee]
02023dcc: ldrb     r3, [r8, #2]
02023dd0: add      r1, r7, r2
02023dd4: asr      r1, r1, #1
02023dd8: lsl      r1, r1, #8
02023ddc: ldrb     r2, [r8, #3]
02023de0: add      r2, r3, r2, lsl #8
02023de4: lsl      r2, r2, #0x10
02023de8: sub      r2, r6, r2, lsr #16
02023dec: lsl      r2, r2, #8
02023df0: bl       #0x2028cf8
02023df4: add      r8, r8, #4
02023df8: b        #0x202632c
```

## op 0x30  @ 0x2023dfc
```
02023dfc: add      r3, sb, #0x100
02023e00: ldrb     r1, [r8, #2]
02023e04: ldrb     r6, [r8, #3]
02023e08: ldrh     r2, [r3, #0xa]
02023e0c: and      r1, r1, #0xf
02023e10: ldrh     r0, [r3, #0x2c]
02023e14: add      r1, r2, r1, lsl #5
02023e18: and      r6, r6, #0xf
02023e1c: add      r2, r2, r6, lsl #5
02023e20: lsl      r2, r2, #0x10
02023e24: lsl      r1, r1, #0x10
02023e28: cmp      r0, r2, lsr #16
02023e2c: addlo    r0, r0, #0x20
02023e30: lsr      r1, r1, #0x10
02023e34: strhlo   r0, [r3, #0x2c]
02023e38: blo      #0x2023e44
02023e3c: add      r0, sb, #0x124
02023e40: bl       #0x2010ad8
02023e44: add      r8, r8, #4
02023e48: b        #0x202632c
```

## op 0x31  @ 0x2023e4c
```
02023e4c: ldrb     r3, [r8, #2]
02023e50: ldrb     r2, [r8, #3]
02023e54: ldr      r1, [r4]
02023e58: ldr      r0, [sp, #0x50]
02023e5c: add      r2, r3, r2, lsl #8
02023e60: add      r1, r1, #0x4d00
02023e64: strh     r2, [r1, #0xe4]
02023e68: ldr      r2, [r4]
02023e6c: ldr      r1, [sp, #0x54]
02023e70: add      r2, r2, #0x4d00
02023e74: ldrh     r2, [r2, #0xe4]
02023e78: bl       #0x2001c68
02023e7c: ldr      r0, [r4]
02023e80: add      r8, r8, #4
02023e84: add      r0, r0, #0x4d00
02023e88: ldrh     r1, [r0, #0xe4]
02023e8c: add      r1, r1, #1
02023e90: strh     r1, [r0, #0xe4]
02023e94: b        #0x202632c
```

## op 0x32  @ 0x2023e98
```
02023e98: ldrb     r3, [r8, #2]
02023e9c: ldrb     r2, [r8, #3]
02023ea0: ldr      r1, [r4]
02023ea4: ldr      r0, [sp, #0x58]
02023ea8: add      r2, r3, r2, lsl #8
02023eac: add      r1, r1, #0x4d00
02023eb0: strh     r2, [r1, #0xe4]
02023eb4: ldr      r2, [r4]
02023eb8: ldr      r1, [sp, #0x54]
02023ebc: add      r2, r2, #0x4d00
02023ec0: ldrh     r2, [r2, #0xe4]
02023ec4: bl       #0x2001cdc
02023ec8: ldr      r0, [r4]
02023ecc: add      r8, r8, #4
02023ed0: add      r0, r0, #0x4d00
02023ed4: ldrh     r1, [r0, #0xe4]
02023ed8: add      r1, r1, #1
02023edc: strh     r1, [r0, #0xe4]
02023ee0: b        #0x202632c
```

## op 0x33  @ 0x2023ee4
```
02023ee4: ldrh     r0, [sb, #0xe]
02023ee8: ands     r1, r0, #0x40
02023eec: bicne    r0, r0, #0x40
02023ef0: strhne   r0, [sb, #0xe]
02023ef4: addne    r8, r8, #2
02023ef8: streq    r5, [sp, #8]
02023efc: b        #0x202632c
```

## op 0x34  @ 0x2023f00
```
02023f00: ldrb     r0, [sb, #0x1a]
02023f04: ldrb     r1, [r8, #1]
02023f08: bl       #0x2027b34
02023f0c: cmp      r0, #0
02023f10: ldrhne   r1, [r0, #0xe]
02023f14: add      r8, r8, #2
02023f18: orrne    r1, r1, #0x40
02023f1c: strhne   r1, [r0, #0xe]
02023f20: b        #0x202632c
```

## op 0x35  @ 0x2023f24
```
02023f24: ldrb     r0, [sb, #0x1a]
02023f28: bl       #0x2027bd0
02023f2c: cmp      r0, #0
02023f30: ldrhne   r1, [r0, #0xe]
02023f34: add      r8, r8, #2
02023f38: orrne    r1, r1, #0x40
02023f3c: strhne   r1, [r0, #0xe]
02023f40: b        #0x202632c
```

## op 0x36  @ 0x2023f44
```
02023f44: mov      r0, sb
02023f48: ldrb     r2, [r8, #2]
02023f4c: ldrb     r1, [r8, #3]
02023f50: add      r1, r2, r1, lsl #8
02023f54: lsl      r1, r1, #0x10
02023f58: lsr      r1, r1, #0x10
02023f5c: bl       #0x2018fb8
02023f60: add      r8, r8, #4
02023f64: b        #0x202632c
```

## op 0x37  @ 0x2023f68
```
02023f68: add      r8, r8, #2
02023f6c: b        #0x202632c
```

## op 0x38  @ 0x2023f70
```
02023f70: add      r8, r8, #2
02023f74: bl       #0x2021e90
02023f78: b        #0x202632c
```

## op 0x39  @ 0x2023f7c
```
02023f7c: ldrb     r0, [sb, #0x1a]
02023f80: bl       #0x2027c00
02023f84: mov      r7, r0
02023f88: ldrb     r0, [sb, #0x1a]
02023f8c: bl       #0x2027bd0
02023f90: mov      r6, r0
02023f94: cmp      r7, #0
02023f98: add      r8, r8, #2
02023f9c: beq      #0x202632c
02023fa0: cmp      r6, #0
02023fa4: beq      #0x202632c
02023fa8: bl       #0x201301c
02023fac: ldrh     r2, [r0, #6]
02023fb0: ldr      r1, [r7, #0x38]
02023fb4: ldr      r0, [r6, #0x38]
02023fb8: sub      r3, r2, #0x80
02023fbc: add      r0, r1, r0
02023fc0: asr      r1, r0, #1
02023fc4: str      r1, [sp, #0x14c]
02023fc8: ldr      sl, [r7, #0x3c]
02023fcc: ldr      r2, [r6, #0x3c]
02023fd0: mov      r0, #0x6000
02023fd4: add      r2, sl, r2
02023fd8: asr      r2, r2, #1
02023fdc: str      r2, [sp, #0x150]
02023fe0: mul      r2, r3, r0
02023fe4: asr      r0, r2, #6
02023fe8: add      r0, r2, r0, lsr #25
02023fec: lsl      r3, r3, #0xe
02023ff0: asr      r2, r3, #6
02023ff4: add      r2, r3, r2, lsr #25
02023ff8: ldr      sl, [r7, #0x38]
02023ffc: ldr      r3, [r6, #0x38]
02024000: asr      r0, r0, #7
02024004: cmp      sl, r3
02024008: addgt    r0, r1, r0
0202400c: strgt    r0, [sp, #0x14c]
02024010: suble    r0, r1, r0
02024014: strle    r0, [sp, #0x14c]
02024018: ldr      r1, [r7, #0x3c]
0202401c: ldr      r0, [r6, #0x3c]
02024020: asr      r2, r2, #7
02024024: cmp      r1, r0
02024028: ble      #0x2024058
0202402c: ldr      r1, [sp, #0x150]
02024030: ldr      r0, [r4]
02024034: add      r1, r1, r2
02024038: add      r0, r0, #0x4d00
0202403c: str      r1, [sp, #0x150]
02024040: ldrsh    r0, [r0, #0xee]
02024044: sub      r0, r0, #0x20
02024048: cmp      r0, r1, asr #8
0202404c: suble    r0, r1, r2
02024050: strle    r0, [sp, #0x150]
02024054: b        #0x2024064
02024058: ldr      r0, [sp, #0x150]
0202405c: sub      r0, r0, r2
02024060: str      r0, [sp, #0x150]
02024064: cmp      sb, #0
02024068: ldrne    r1, [sp, #0x14c]
0202406c: ldrne    r0, [sp, #0x150]
02024070: strne    r1, [sb, #0x38]
02024074: strne    r0, [sb, #0x3c]
02024078: b        #0x202632c
```

## op 0x3a  @ 0x202407c
```
0202407c: add      r6, r8, #1
02024080: bl       #0x2020aa0
02024084: cmp      r0, #0
02024088: beq      #0x2024098
0202408c: ldrb     r0, [sb, #0x1d]
02024090: bl       #0x2020ab0
02024094: mov      r6, r0
02024098: ldrb     r2, [r6, #6]
0202409c: ldrb     r1, [r6, #7]
020240a0: mov      r0, sb
020240a4: add      r1, r2, r1, lsl #8
020240a8: lsl      r1, r1, #0x10
020240ac: asr      r1, r1, #0x10
020240b0: str      r1, [sp]
020240b4: ldrb     r1, [r6, #8]
020240b8: str      r1, [sp, #4]
020240bc: ldrb     r7, [r6]
020240c0: ldrb     r1, [r6, #1]
020240c4: ldrb     r3, [r6, #2]
020240c8: ldrb     r2, [r6, #3]
020240cc: add      r1, r7, r1, lsl #8
020240d0: lsl      r1, r1, #0x10
020240d4: add      r2, r3, r2, lsl #8
020240d8: asr      r1, r1, #0x10
020240dc: lsl      r2, r2, #0x10
020240e0: asr      r2, r2, #0x10
020240e4: ldrb     r7, [r6, #4]
020240e8: ldrb     r3, [r6, #5]
020240ec: add      r3, r7, r3, lsl #8
020240f0: lsl      r3, r3, #0x10
020240f4: asr      r3, r3, #0x10
020240f8: bl       #0x2021374
020240fc: add      r8, r8, #0xa
02024100: b        #0x202632c
```

## op 0x3b  @ 0x2024104
```
02024104: ldrb     r0, [sb, #0x1a]
02024108: bl       #0x2027bd0
0202410c: mov      r1, r0
02024110: mov      r0, sb
02024114: bl       #0x201ee60
02024118: mov      r7, r0
0202411c: add      r6, r8, #1
02024120: bl       #0x2020aa0
02024124: cmp      r0, #0
02024128: beq      #0x2024138
0202412c: ldrb     r0, [sb, #0x1d]
02024130: bl       #0x2020ab0
02024134: mov      r6, r0
02024138: ldrb     r1, [r6]
0202413c: mov      r2, r7
02024140: ldrb     r0, [sb, #7]
02024144: bl       #0x20210c8
02024148: strb     r0, [sb, #7]
0202414c: ldrh     r0, [sb, #0xe]
02024150: ands     r0, r0, #0x80
02024154: bne      #0x2024184
02024158: add      r0, sb, #0x100
0202415c: ldrh     r0, [r0, #0xe]
02024160: cmp      r0, #0x25
02024164: blo      #0x2024184
02024168: ldrb     r3, [sb, #7]
0202416c: ldr      r1, [sp, #0x5c]
02024170: add      r0, sb, #0x124
02024174: rsb      r3, r3, #0x100
02024178: mov      r2, r1
0202417c: and      r3, r3, #0xff
02024180: bl       #0x2011f74
02024184: ldrb     r1, [sb, #7]
02024188: mov      r0, sb
0202418c: str      r1, [sp]
02024190: ldrsh    r1, [sb, #0x22]
02024194: ldrsh    r2, [sb, #0x26]
02024198: ldrsh    r3, [sb, #0x24]
0202419c: bl       #0x20213a8
020241a0: add      r8, r8, #2
020241a4: b        #0x202632c
```

## op 0x3c  @ 0x20241a8
```
020241a8: add      r8, r8, #2
020241ac: b        #0x202632c
```

## op 0x3d  @ 0x20241b0
```
020241b0: ldrb     r1, [r8, #2]
020241b4: ldrb     r0, [r8, #3]
020241b8: ldrb     r3, [r8, #4]
020241bc: ldrb     r6, [r8, #5]
020241c0: add      r0, r1, r0, lsl #8
020241c4: add      r0, r0, r3, lsl #16
020241c8: add      fp, r0, r6, lsl #24
020241cc: ldrb     r6, [r8, #6]
020241d0: ldrb     r3, [r8, #7]
020241d4: ldrb     r7, [r8, #8]
020241d8: ldrb     r2, [r8, #9]
020241dc: add      r3, r6, r3, lsl #8
020241e0: add      r3, r3, r7, lsl #16
020241e4: add      r2, r3, r2, lsl #24
020241e8: ldrb     r1, [r8, #1]
020241ec: mov      r0, sb
020241f0: str      r2, [sp, #0x10]
020241f4: bl       #0x202247c
020241f8: movs     r7, r0
020241fc: beq      #0x2024284
02024200: ldrb     r2, [r8, #0xa]
02024204: ldrb     r1, [r8, #0xb]
02024208: ldrb     r3, [r8, #0xc]
0202420c: ldr      r0, [sb, #0x3c]
02024210: add      r1, r2, r1, lsl #8
02024214: lsl      r1, r1, #0x10
02024218: ldrb     r2, [r8, #0xd]
0202421c: asr      r6, r1, #0x10
02024220: ldrh     r1, [sb, #0x12]
02024224: add      r2, r3, r2, lsl #8
02024228: add      r2, r2, r0, asr #8
0202422c: ands     r0, r1, #1
02024230: lsl      r0, r2, #0x10
02024234: asr      sl, r0, #0x10
02024238: mvnne    r0, #0
0202423c: smulbbne r0, r6, r0
02024240: ldr      r3, [sb, #0x38]
02024244: lslne    r0, r0, #0x10
02024248: asrne    r6, r0, #0x10
0202424c: lsl      r3, r3, #8
02024250: add      r3, r6, r3, asr #16
02024254: lsl      r3, r3, #0x10
02024258: asr      r6, r3, #0x10
0202425c: ldr      r2, [sp, #0x10]
02024260: ldr      r3, [sp, #0x60]
02024264: mov      r1, fp
02024268: mov      r0, r7
0202426c: bl       #0x202216c
02024270: cmp      r7, #0
02024274: lslne    r0, r6, #8
02024278: strne    r0, [r7, #0x38]
0202427c: lslne    r0, sl, #8
02024280: strne    r0, [r7, #0x3c]
02024284: add      r8, r8, #0xe
02024288: b        #0x202632c
```

## op 0x3e  @ 0x202428c
```
0202428c: ldrb     r2, [r8, #2]
02024290: ldrb     r1, [r8, #3]
02024294: ldrb     r3, [r8, #4]
02024298: ldrb     r7, [r8, #5]
0202429c: add      r1, r2, r1, lsl #8
020242a0: add      r1, r1, r3, lsl #16
020242a4: add      fp, r1, r7, lsl #24
020242a8: add      r1, sb, #0x100
020242ac: ldrh     r1, [r1, #0xe]
020242b0: ldrb     r3, [r8, #6]
020242b4: ldrb     r2, [r8, #7]
020242b8: ldrb     r6, [r8, #8]
020242bc: ldrb     r0, [r8, #9]
020242c0: add      r2, r3, r2, lsl #8
020242c4: add      r2, r2, r6, lsl #16
020242c8: cmp      r1, #0x25
020242cc: add      r0, r2, r0, lsl #24
020242d0: ldrlo    r3, [sb, #0x244]
020242d4: str      r0, [sp, #0x14]
020242d8: addlo    r2, sb, #0x164
020242dc: ldrhs    r3, [sb, #0x40]
020242e0: ldr      r0, [sp, #0x64]
020242e4: addhs    r2, sb, #0x44
020242e8: str      r0, [sp]
020242ec: ldrb     r1, [r8, #1]
020242f0: mov      r0, sb
020242f4: bl       #0x20225c8
020242f8: movs     r7, r0
020242fc: beq      #0x2024384
02024300: ldrb     r2, [r8, #0xa]
02024304: ldrb     r1, [r8, #0xb]
02024308: ldrb     r3, [r8, #0xc]
0202430c: ldr      r0, [sb, #0x3c]
02024310: add      r1, r2, r1, lsl #8
02024314: lsl      r1, r1, #0x10
02024318: ldrb     r2, [r8, #0xd]
0202431c: asr      r6, r1, #0x10
02024320: ldrh     r1, [sb, #0x12]
02024324: add      r2, r3, r2, lsl #8
02024328: add      r2, r2, r0, asr #8
0202432c: ands     r0, r1, #1
02024330: lsl      r0, r2, #0x10
02024334: asr      sl, r0, #0x10
02024338: mvnne    r0, #0
0202433c: smulbbne r0, r6, r0
02024340: ldr      r3, [sb, #0x38]
02024344: lslne    r0, r0, #0x10
02024348: asrne    r6, r0, #0x10
0202434c: lsl      r3, r3, #8
02024350: add      r3, r6, r3, asr #16
02024354: lsl      r3, r3, #0x10
02024358: asr      r6, r3, #0x10
0202435c: ldr      r2, [sp, #0x14]
02024360: ldr      r3, [sp, #0x68]
02024364: mov      r1, fp
02024368: mov      r0, r7
0202436c: bl       #0x202216c
02024370: cmp      r7, #0
02024374: lslne    r0, r6, #8
02024378: strne    r0, [r7, #0x38]
0202437c: lslne    r0, sl, #8
02024380: strne    r0, [r7, #0x3c]
02024384: add      r8, r8, #0xe
02024388: b        #0x202632c
```

## op 0x3f  @ 0x202438c
```
0202438c: str      r8, [sb, #0x114]
02024390: ldrb     r0, [sb, #0x1a]
02024394: ldrb     r2, [r8, #2]
02024398: ldrb     r1, [r8, #3]
0202439c: add      r1, r2, r1, lsl #8
020243a0: lsl      r1, r1, #0x10
020243a4: lsr      r1, r1, #0x10
020243a8: bl       #0x20291c8
020243ac: add      r8, r8, #8
020243b0: b        #0x202632c
```

## op 0x40  @ 0x20243b4
```
020243b4: ldr      r0, [sp, #0x6c]
020243b8: ldr      r1, [sp, #0x6c]
020243bc: str      r0, [sb, #0x114]
020243c0: ldrb     r0, [sb, #0x1a]
020243c4: add      r8, r8, #2
020243c8: bl       #0x20291c8
020243cc: b        #0x202632c
```

## op 0x41  @ 0x20243d0
```
020243d0: add      r0, r8, #2
020243d4: str      r0, [sb, #0x118]
020243d8: ldrb     r3, [r8, #0xd]
020243dc: ldrb     r2, [r8, #0xc]
020243e0: ldrb     r1, [r8, #0xa]
020243e4: ldrb     r0, [r8, #0xb]
020243e8: add      r8, r8, #0xe
020243ec: add      r0, r1, r0, lsl #8
020243f0: add      r0, r0, r2, lsl #16
020243f4: add      r0, r0, r3, lsl #24
020243f8: str      r0, [sb, #0x11c]
020243fc: b        #0x202632c
```

## op 0x42  @ 0x2024400
```
02024400: add      r8, r8, #2
02024404: ldrh     r0, [sb, #0x12]
02024408: bic      r0, r0, #8
0202440c: strh     r0, [sb, #0x12]
02024410: b        #0x202632c
```

## op 0x43  @ 0x2024414
```
02024414: add      r6, r8, #2
02024418: bl       #0x2020aa0
0202441c: cmp      r0, #0
02024420: beq      #0x2024430
02024424: ldrb     r0, [sb, #0x1d]
02024428: bl       #0x2020ab0
0202442c: mov      r6, r0
02024430: ldrh     r0, [sb, #0x12]
02024434: ands     r0, r0, #8
02024438: beq      #0x2024468
0202443c: ldrb     r1, [r6]
02024440: ldrb     r0, [r6, #1]
02024444: add      r0, r1, r0, lsl #8
02024448: lsl      r0, r0, #8
0202444c: str      r0, [sp, #0x154]
02024450: ldrb     r1, [r6, #2]
02024454: ldrb     r0, [r6, #3]
02024458: add      r0, r1, r0, lsl #8
0202445c: lsl      r0, r0, #8
02024460: str      r0, [sp, #0x158]
02024464: b        #0x202449c
02024468: bl       #0x201301c
0202446c: ldr      r3, [r0, #0xc]
02024470: ldrb     r2, [r6]
02024474: ldrb     r1, [r6, #1]
02024478: add      r1, r2, r1, lsl #8
0202447c: add      r1, r3, r1, lsl #8
02024480: str      r1, [sp, #0x154]
02024484: ldr      r2, [r0, #0x10]
02024488: ldrb     r1, [r6, #2]
0202448c: ldrb     r0, [r6, #3]
02024490: add      r0, r1, r0, lsl #8
02024494: add      r0, r2, r0, lsl #8
02024498: str      r0, [sp, #0x158]
0202449c: cmp      sb, #0
020244a0: ldrne    r1, [sp, #0x154]
020244a4: ldrne    r0, [sp, #0x158]
020244a8: add      r8, r8, #6
020244ac: strne    r1, [sb, #0x38]
020244b0: strne    r0, [sb, #0x3c]
020244b4: b        #0x202632c
```

## op 0x44  @ 0x20244b8
```
020244b8: add      r6, r8, #1
020244bc: bl       #0x2020aa0
020244c0: cmp      r0, #0
020244c4: beq      #0x20244d4
020244c8: ldrb     r0, [sb, #0x1d]
020244cc: bl       #0x2020ab0
020244d0: mov      r6, r0
020244d4: ldrb     r0, [r6]
020244d8: strb     r0, [sb, #7]
020244dc: ldrh     r0, [sb, #0xe]
020244e0: ands     r0, r0, #0x80
020244e4: bne      #0x2024514
020244e8: add      r0, sb, #0x100
020244ec: ldrh     r0, [r0, #0xe]
020244f0: cmp      r0, #0x25
020244f4: blo      #0x2024514
020244f8: ldrb     r2, [r6]
020244fc: ldr      r1, [sp, #0x70]
02024500: add      r0, sb, #0x124
02024504: rsb      r2, r2, #0x100
02024508: and      r3, r2, #0xff
0202450c: mov      r2, r1
02024510: bl       #0x2011f74
02024514: add      r8, r8, #2
02024518: b        #0x202632c
```

## op 0x45  @ 0x202451c
```
0202451c: ldrb     r0, [sb, #0x1a]
02024520: bl       #0x2027bd0
02024524: ldr      r3, [sb, #0x38]
02024528: ldr      r1, [r0, #0x38]
0202452c: ldr      r2, [sb, #0x3c]
02024530: sub      r1, r3, r1
02024534: asr      r7, r1, #8
02024538: ldr      r1, [r0, #0x3c]
0202453c: add      r0, sp, #0x164
02024540: sub      r1, r2, r1
02024544: asr      r6, r1, #8
02024548: bl       #0x20af82c
0202454c: mul      r0, r6, r6
02024550: mla      r2, r7, r7, r0
02024554: ldr      r1, [sp, #0x74]
02024558: ldr      r0, [pc, #0xfb8]   ; =0x40002b0
0202455c: strh     r1, [r0]
02024560: ldr      r0, [pc, #0xfb4]   ; =0x40002b8
02024564: str      r2, [r0]
02024568: ldr      r0, [pc, #0xfa8]   ; =0x40002b0
0202456c: ldrh     r0, [r0]
02024570: ands     r0, r0, #0x8000
02024574: bne      #0x2024568
02024578: ldr      r0, [pc, #0xf98]   ; =0x40002b0
0202457c: ldrh     r0, [r0]
02024580: ands     r0, r0, #0x8000
02024584: bne      #0x2024578
02024588: ldr      r0, [pc, #0xf90]   ; =0x40002b4
0202458c: ldr      r6, [r0]
02024590: add      r0, sp, #0x164
02024594: bl       #0x20af7c0
02024598: ldrb     r0, [r8, #1]
0202459c: cmp      r6, r0
020245a0: addge    r8, r8, #6
020245a4: bge      #0x202632c
020245a8: ldrb     r3, [r8, #2]
020245ac: ldrb     r2, [r8, #3]
020245b0: ldrb     r6, [r8, #4]
020245b4: ldrb     r7, [r8, #5]
020245b8: add      r2, r3, r2, lsl #8
020245bc: add      r2, r2, r6, lsl #16
020245c0: ldr      r0, [sb, #0x44]
020245c4: add      r2, r2, r7, lsl #24
020245c8: add      r0, r0, r2
020245cc: str      r0, [sb, #0x100]
020245d0: ldr      r0, [sb, #0x100]
020245d4: add      r1, sb, #0x100
020245d8: str      r0, [sb, #0x104]
020245dc: ldr      r0, [sp, #0x78]
020245e0: strh     r0, [r1, #0xc]
020245e4: ldr      r8, [sb, #0x104]
020245e8: b        #0x202632c
```

## op 0x46  @ 0x20245ec
```
020245ec: ldr      r0, [r4]
020245f0: ldrb     r2, [r8, #2]
020245f4: add      r0, r0, #0x4d00
020245f8: ldrsh    r3, [r0, #0xee]
020245fc: ldrb     r0, [r8, #3]
02024600: ldr      r1, [sb, #0x3c]
02024604: add      r0, r2, r0, lsl #8
02024608: lsl      r0, r0, #0x10
0202460c: sub      r0, r3, r0, asr #16
02024610: cmp      r0, r1, asr #8
02024614: addgt    r8, r8, #8
02024618: bgt      #0x202632c
0202461c: ldrb     r3, [r8, #4]
02024620: ldrb     r2, [r8, #5]
02024624: ldrb     r6, [r8, #6]
02024628: ldrb     r7, [r8, #7]
0202462c: add      r2, r3, r2, lsl #8
02024630: add      r2, r2, r6, lsl #16
02024634: ldr      r0, [sb, #0x44]
02024638: add      r2, r2, r7, lsl #24
0202463c: add      r0, r0, r2
02024640: str      r0, [sb, #0x100]
02024644: ldr      r0, [sb, #0x100]
02024648: add      r1, sb, #0x100
0202464c: str      r0, [sb, #0x104]
02024650: ldr      r0, [sp, #0x7c]
02024654: str      r5, [sp, #8]
02024658: strh     r0, [r1, #0xc]
0202465c: ldr      r8, [sb, #0x104]
02024660: b        #0x202632c
```

## op 0x47  @ 0x2024664
```
02024664: ldrb     r0, [sb, #0x1a]
02024668: bl       #0x2027c00
0202466c: ldrb     r1, [r8, #1]
02024670: lsl      r1, r1, #0x18
02024674: lsr      r1, r1, #0x10
02024678: bl       #0x2027a40
0202467c: add      r8, r8, #2
02024680: b        #0x202632c
```

## op 0x48  @ 0x2024684
```
02024684: ldrb     r0, [sb, #0x1a]
02024688: bl       #0x2027c00
0202468c: ldrb     r1, [r8, #1]
02024690: ldr      r2, [sp, #0x80]
02024694: lsl      r1, r1, #0x18
02024698: lsr      r1, r1, #0x10
0202469c: bl       #0x2027950
020246a0: add      r8, r8, #2
020246a4: b        #0x202632c
```

## op 0x49  @ 0x20246a8
```
020246a8: str      r8, [sb, #0x114]
020246ac: ldrb     r0, [sb, #0x1a]
020246b0: ldrb     r2, [r8, #1]
020246b4: ldrb     r1, [r8, #2]
020246b8: add      r1, r2, r1, lsl #8
020246bc: lsl      r1, r1, #0x10
020246c0: lsr      r1, r1, #0x10
020246c4: bl       #0x20291c8
020246c8: add      r8, r8, #8
020246cc: b        #0x202632c
```

## op 0x4a  @ 0x20246d0
```
020246d0: str      r8, [sb, #0x114]
020246d4: ldrb     r0, [sb, #0x1a]
020246d8: ldrb     r2, [r8, #1]
020246dc: ldrb     r1, [r8, #2]
020246e0: add      r1, r2, r1, lsl #8
020246e4: lsl      r1, r1, #0x10
020246e8: lsr      r1, r1, #0x10
020246ec: bl       #0x20291c8
020246f0: add      r8, r8, #8
020246f4: b        #0x202632c
```

## op 0x4b  @ 0x20246f8
```
020246f8: str      r8, [sb, #0x114]
020246fc: add      r8, r8, #6
02024700: b        #0x202632c
```

## op 0x4c  @ 0x2024704
```
02024704: str      r8, [sb, #0x114]
02024708: add      r8, r8, #6
0202470c: b        #0x202632c
```

## op 0x4d  @ 0x2024710
```
02024710: str      r8, [sb, #0x114]
02024714: add      r8, r8, #6
02024718: b        #0x202632c
```

## op 0x4e  @ 0x202471c
```
0202471c: add      r0, sb, #0x100
02024720: ldrh     r0, [r0, #0xe]
02024724: cmp      r0, #0x25
02024728: bhs      #0x2024794
0202472c: ldrb     r0, [sb, #0x1a]
02024730: bl       #0x2027bd0
02024734: mov      r1, r0
02024738: ldrb     r2, [r8, #1]
0202473c: mov      r0, sb
02024740: bl       #0x2028ddc
02024744: cmp      r0, #0
02024748: addeq    r8, r8, #6
0202474c: beq      #0x202632c
02024750: ldrb     r3, [r8, #2]
02024754: ldrb     r2, [r8, #3]
02024758: ldrb     r6, [r8, #4]
0202475c: ldrb     r7, [r8, #5]
02024760: add      r2, r3, r2, lsl #8
02024764: add      r2, r2, r6, lsl #16
02024768: ldr      r0, [sb, #0x44]
0202476c: add      r2, r2, r7, lsl #24
02024770: add      r0, r0, r2
02024774: str      r0, [sb, #0x100]
02024778: ldr      r0, [sb, #0x100]
0202477c: add      r1, sb, #0x100
02024780: str      r0, [sb, #0x104]
02024784: ldr      r0, [sp, #0x84]
02024788: strh     r0, [r1, #0xc]
0202478c: ldr      r8, [sb, #0x104]
02024790: b        #0x202632c
02024794: add      r8, r8, #6
02024798: b        #0x202632c
```

## op 0x4f  @ 0x202479c
```
0202479c: ldr      r6, [sb, #0x44]
020247a0: ldrb     r3, [r8, #5]
020247a4: ldrb     r2, [r8, #4]
020247a8: ldrb     r1, [r8, #2]
020247ac: ldrb     r0, [r8, #3]
020247b0: add      r0, r1, r0, lsl #8
020247b4: add      r0, r0, r2, lsl #16
020247b8: add      r0, r0, r3, lsl #24
020247bc: add      r0, r6, r0
020247c0: bl       #0x2020bb0
020247c4: add      r8, r8, #6
020247c8: b        #0x202632c
```

## op 0x50  @ 0x20247cc
```
020247cc: add      r6, r8, #2
020247d0: bl       #0x2020aa0
020247d4: cmp      r0, #0
020247d8: beq      #0x20247e8
020247dc: ldrb     r0, [sb, #0x1d]
020247e0: bl       #0x2020ab0
020247e4: mov      r6, r0
020247e8: ldrb     r2, [sb, #7]
020247ec: ldrb     r1, [r6]
020247f0: ldrb     r0, [r6, #1]
020247f4: add      r0, r1, r0, lsl #8
020247f8: lsl      r0, r0, #0x10
020247fc: add      r0, r2, r0, asr #16
02024800: strb     r0, [sb, #7]
02024804: ldrh     r0, [sb, #0xe]
02024808: ands     r0, r0, #0x80
0202480c: bne      #0x202483c
02024810: add      r0, sb, #0x100
02024814: ldrh     r0, [r0, #0xe]
02024818: cmp      r0, #0x25
0202481c: blo      #0x202483c
02024820: ldrb     r3, [sb, #7]
02024824: ldr      r1, [sp, #0x88]
02024828: add      r0, sb, #0x124
0202482c: rsb      r3, r3, #0x100
02024830: mov      r2, r1
02024834: and      r3, r3, #0xff
02024838: bl       #0x2011f74
0202483c: add      r8, r8, #4
02024840: b        #0x202632c
```

## op 0x51  @ 0x2024844
```
02024844: add      r0, sb, #0x100
02024848: ldrh     r0, [r0, #0xe]
0202484c: cmp      r0, #0x25
02024850: bhs      #0x20248ac
02024854: bl       #0x2021edc
02024858: ldr      r1, [sp, #0x8c]
0202485c: mov      r0, sb
02024860: bl       #0x2021d2c
02024864: cmp      r0, #0
02024868: ldrne    r1, [sp, #0x90]
0202486c: strbne   r1, [r0, #4]
02024870: ldr      r0, [sb, #0x250]
02024874: bic      r0, r0, #0x200
02024878: str      r0, [sb, #0x250]
0202487c: ldrb     r0, [sb, #0x1a]
02024880: bl       #0x2027bd0
02024884: ldr      r1, [r0, #0x250]
02024888: bic      r1, r1, #0x800
0202488c: str      r1, [r0, #0x250]
02024890: bl       #0x2027b1c
02024894: cmp      r0, #0
02024898: beq      #0x20248ac
0202489c: bl       #0x2027b1c
020248a0: ldr      r1, [r0, #0x250]
020248a4: bic      r1, r1, #0x800
020248a8: str      r1, [r0, #0x250]
020248ac: add      r8, r8, #2
020248b0: b        #0x202632c
```

## op 0x52  @ 0x20248b4
```
020248b4: add      r0, sb, #0x100
020248b8: ldrh     r0, [r0, #0xe]
020248bc: cmp      r0, #0x25
020248c0: bhs      #0x202491c
020248c4: bl       #0x2021f18
020248c8: ldr      r1, [sp, #0x8c]
020248cc: mov      r0, sb
020248d0: bl       #0x202247c
020248d4: ldr      r1, [sp, #0x94]
020248d8: add      r0, sb, #0x124
020248dc: bl       #0x2011d5c
020248e0: ldr      r0, [sb, #0x250]
020248e4: orr      r0, r0, #0x200
020248e8: str      r0, [sb, #0x250]
020248ec: ldrb     r0, [sb, #0x1a]
020248f0: bl       #0x2027bd0
020248f4: ldr      r1, [r0, #0x250]
020248f8: orr      r1, r1, #0x800
020248fc: str      r1, [r0, #0x250]
02024900: bl       #0x2027b1c
02024904: cmp      r0, #0
02024908: beq      #0x202491c
0202490c: bl       #0x2027b1c
02024910: ldr      r1, [r0, #0x250]
02024914: orr      r1, r1, #0x800
02024918: str      r1, [r0, #0x250]
0202491c: add      r8, r8, #2
02024920: b        #0x202632c
```

## op 0x53  @ 0x2024924
```
02024924: add      r0, sb, #0x100
02024928: ldrh     r0, [r0, #0xe]
0202492c: cmp      r0, #0x25
02024930: bhs      #0x2024954
02024934: ldrb     r0, [r8, #1]
02024938: cmp      r0, #0
0202493c: ldrne    r0, [sb, #0x250]
02024940: bicne    r0, r0, #0x20
02024944: strne    r0, [sb, #0x250]
02024948: ldreq    r0, [sb, #0x250]
0202494c: orreq    r0, r0, #0x20
02024950: streq    r0, [sb, #0x250]
02024954: add      r8, r8, #2
02024958: b        #0x202632c
```

## op 0x54  @ 0x202495c
```
0202495c: ldrb     r0, [r8, #2]
02024960: ldrb     r1, [r8, #3]
02024964: ldrb     r3, [r8, #4]
02024968: ldrb     r2, [r8, #5]
0202496c: add      r2, r3, r2, lsl #8
02024970: lsl      r2, r2, #0x10
02024974: lsr      r2, r2, #0x10
02024978: bl       #0x2018e8c
0202497c: add      r8, r8, #6
02024980: b        #0x202632c
```

## op 0x55  @ 0x2024984
```
02024984: ldrb     r0, [sb, #0x1a]
02024988: bl       #0x2027c00
0202498c: bl       #0x2027924
02024990: ldrb     r1, [r8, #1]
02024994: cmp      r0, r1
02024998: addgt    r8, r8, #6
0202499c: bgt      #0x202632c
020249a0: ldrb     r3, [r8, #2]
020249a4: ldrb     r2, [r8, #3]
020249a8: ldrb     r6, [r8, #4]
020249ac: ldrb     r7, [r8, #5]
020249b0: add      r2, r3, r2, lsl #8
020249b4: add      r2, r2, r6, lsl #16
020249b8: ldr      r0, [sb, #0x44]
020249bc: add      r2, r2, r7, lsl #24
020249c0: add      r0, r0, r2
020249c4: str      r0, [sb, #0x100]
020249c8: ldr      r0, [sb, #0x100]
020249cc: add      r1, sb, #0x100
020249d0: str      r0, [sb, #0x104]
020249d4: ldr      r0, [sp, #0x98]
020249d8: strh     r0, [r1, #0xc]
020249dc: ldr      r8, [sb, #0x104]
020249e0: b        #0x202632c
```

## op 0x56  @ 0x20249e4
```
020249e4: ldrb     r0, [sb, #0x1a]
020249e8: bl       #0x2027c00
020249ec: movs     r7, r0
020249f0: beq      #0x2024a5c
020249f4: add      r6, r8, #2
020249f8: bl       #0x2020aa0
020249fc: cmp      r0, #0
02024a00: beq      #0x2024a10
02024a04: ldrb     r0, [sb, #0x1d]
02024a08: bl       #0x2020ab0
02024a0c: mov      r6, r0
02024a10: ldr      r0, [r7, #0x38]
02024a14: ldr      r3, [r7, #0x3c]
02024a18: ldrb     sl, [r6]
02024a1c: ldrb     r7, [r6, #1]
02024a20: ldrb     r2, [r6, #2]
02024a24: ldrb     r1, [r6, #3]
02024a28: add      r6, sl, r7, lsl #8
02024a2c: add      r6, r6, r0, asr #8
02024a30: add      r0, r2, r1, lsl #8
02024a34: add      r1, r0, r3, asr #8
02024a38: lsl      r0, r6, #0x10
02024a3c: asr      r2, r0, #0x10
02024a40: lsl      r0, r1, #0x10
02024a44: cmp      sb, #0
02024a48: asr      r1, r0, #0x10
02024a4c: lslne    r0, r2, #8
02024a50: strne    r0, [sb, #0x38]
02024a54: lslne    r0, r1, #8
02024a58: strne    r0, [sb, #0x3c]
02024a5c: add      r8, r8, #6
02024a60: b        #0x202632c
```

## op 0x57  @ 0x2024a64
```
02024a64: ldrb     r0, [sb, #0x1a]
02024a68: bl       #0x2027c00
02024a6c: movs     r6, r0
02024a70: beq      #0x2024af8
02024a74: add      r7, r8, #1
02024a78: bl       #0x2020aa0
02024a7c: cmp      r0, #0
02024a80: beq      #0x2024a90
02024a84: ldrb     r0, [sb, #0x1d]
02024a88: bl       #0x2020ab0
02024a8c: mov      r7, r0
02024a90: ldrb     r2, [r7, #2]
02024a94: ldrb     r1, [r7]
02024a98: ldrb     r0, [r7, #1]
02024a9c: rsb      r2, r2, #0x100
02024aa0: and      r2, r2, #0xff
02024aa4: add      r0, r1, r0, lsl #8
02024aa8: lsl      r0, r0, #0x10
02024aac: lsr      r1, r0, #0x10
02024ab0: add      r0, r2, #0x40
02024ab4: and      r0, r0, #0xff
02024ab8: lsl      r3, r0, #1
02024abc: ldr      r0, [pc, #0xa60]   ; =0x20b64d4
02024ac0: and      r2, r2, #0xff
02024ac4: ldrsh    r0, [r0, r3]
02024ac8: lsl      r3, r2, #1
02024acc: ldr      r2, [pc, #0xa50]   ; =0x20b64d4
02024ad0: cmp      sb, #0
02024ad4: ldrsh    r2, [r2, r3]
02024ad8: ldr      r3, [r6, #0x38]
02024adc: mla      r3, r1, r0, r3
02024ae0: str      r3, [sp, #0x15c]
02024ae4: ldr      r0, [r6, #0x3c]
02024ae8: mla      r0, r1, r2, r0
02024aec: str      r0, [sp, #0x160]
02024af0: strne    r3, [sb, #0x38]
02024af4: strne    r0, [sb, #0x3c]
02024af8: add      r8, r8, #4
02024afc: b        #0x202632c
```

## op 0x58  @ 0x2024b00
```
02024b00: add      r0, sb, #0x100
02024b04: ldrh     r0, [r0, #0xe]
02024b08: cmp      r0, #0x25
02024b0c: bhs      #0x2024b84
02024b10: ldrb     r0, [r8, #1]
02024b14: ldr      r1, [sp, #0x9c]
02024b18: cmp      r0, #3
02024b1c: addls    pc, pc, r0, lsl #2
02024b20: b        #0x2024b50
02024b24: b        #0x2024b34
02024b28: b        #0x2024b3c
02024b2c: b        #0x2024b44
02024b30: b        #0x2024b4c
02024b34: ldr      r1, [sp, #0x94]
02024b38: b        #0x2024b50
02024b3c: ldr      r1, [sp, #0xa0]
02024b40: b        #0x2024b50
02024b44: ldr      r1, [sp, #0x20]
02024b48: b        #0x2024b50
02024b4c: ldr      r1, [sp, #0xa4]
02024b50: ldr      r0, [sp, #0xa8]
02024b54: str      r0, [sb, #0x250]
02024b58: ldrb     r2, [sb, #0x1a]
02024b5c: mov      r0, sb
02024b60: strb     r2, [sb, #0x25d]
02024b64: bl       #0x2021b4c
02024b68: ldrb     r2, [r8, #2]
02024b6c: ldrb     r1, [r8, #3]
02024b70: add      r0, sb, #0x200
02024b74: add      r8, r8, #4
02024b78: add      r1, r2, r1, lsl #8
02024b7c: strh     r1, [r0, #0x5e]
02024b80: b        #0x202632c
02024b84: add      r8, r8, #4
02024b88: b        #0x202632c
```

## op 0x59  @ 0x2024b8c
```
02024b8c: ldrb     r2, [r8, #2]
02024b90: ldrb     r1, [r8, #3]
02024b94: add      r0, sb, #0x54
02024b98: add      r1, r2, r1, lsl #8
02024b9c: lsl      r1, r1, #0x10
02024ba0: lsr      r1, r1, #0x10
02024ba4: bl       #0x2006074
02024ba8: ldr      r1, [sb, #0x120]
02024bac: cmp      r1, r0
02024bb0: addne    r8, r8, #8
02024bb4: bne      #0x202632c
02024bb8: ldrb     r3, [r8, #4]
02024bbc: ldrb     r2, [r8, #5]
02024bc0: ldrb     r6, [r8, #6]
02024bc4: ldrb     r7, [r8, #7]
02024bc8: add      r2, r3, r2, lsl #8
02024bcc: add      r2, r2, r6, lsl #16
02024bd0: ldr      r0, [sb, #0x44]
02024bd4: add      r2, r2, r7, lsl #24
02024bd8: add      r0, r0, r2
02024bdc: str      r0, [sb, #0x100]
02024be0: ldr      r0, [sb, #0x100]
02024be4: add      r1, sb, #0x100
02024be8: str      r0, [sb, #0x104]
02024bec: ldr      r0, [sp, #0xac]
02024bf0: strh     r0, [r1, #0xc]
02024bf4: ldr      r8, [sb, #0x104]
02024bf8: b        #0x202632c
```

## op 0x5a  @ 0x2024bfc
```
02024bfc: ldrb     r2, [r8, #2]
02024c00: ldrb     r1, [r8, #3]
02024c04: ldrb     r3, [r8, #4]
02024c08: ldrb     r6, [r8, #5]
02024c0c: add      r1, r2, r1, lsl #8
02024c10: add      r1, r1, r3, lsl #16
02024c14: add      r1, r1, r6, lsl #24
02024c18: ldr      r0, [sb, #0x44]
02024c1c: ldr      r6, [sp, #0xb0]
02024c20: add      r8, r8, #6
02024c24: add      r7, r0, r1
02024c28: add      sl, sb, #0x54
02024c2c: mov      r0, sl
02024c30: lsl      r1, r6, #1
02024c34: ldrh     r1, [r7, r1]
02024c38: bl       #0x2006074
02024c3c: ldr      r1, [sb, #0x120]
02024c40: cmp      r1, r0
02024c44: bne      #0x2024c8c
02024c48: ldrb     r7, [r8]
02024c4c: ldrb     r3, [r8, #1]
02024c50: ldrb     sl, [r8, #2]
02024c54: ldrb     r0, [r8, #3]
02024c58: add      r3, r7, r3, lsl #8
02024c5c: add      r3, r3, sl, lsl #16
02024c60: ldr      r1, [sb, #0x44]
02024c64: add      r0, r3, r0, lsl #24
02024c68: add      r0, r1, r0
02024c6c: str      r0, [sb, #0x100]
02024c70: ldr      r0, [sb, #0x100]
02024c74: add      r2, sb, #0x100
02024c78: str      r0, [sb, #0x104]
02024c7c: ldr      r0, [sp, #0xb4]
02024c80: strh     r0, [r2, #0xc]
02024c84: ldr      r8, [sb, #0x104]
02024c88: b        #0x2024c9c
02024c8c: add      r0, r6, #1
02024c90: and      r6, r0, #0xff
02024c94: cmp      r6, #0x10
02024c98: blo      #0x2024c2c
02024c9c: cmp      r6, #0x10
02024ca0: addeq    r8, r8, #4
02024ca4: b        #0x202632c
```

## op 0x5b  @ 0x2024ca8
```
02024ca8: ldrb     r0, [sb, #0x1a]
02024cac: bl       #0x2027bd0
02024cb0: mov      r1, r0
02024cb4: mov      r0, sb
02024cb8: bl       #0x201ee60
02024cbc: mov      r7, r0
02024cc0: add      r6, r8, #2
02024cc4: bl       #0x2020aa0
02024cc8: cmp      r0, #0
02024ccc: beq      #0x2024cdc
02024cd0: ldrb     r0, [sb, #0x1d]
02024cd4: bl       #0x2020ab0
02024cd8: mov      r6, r0
02024cdc: mov      r2, r7
02024ce0: ldrb     r0, [r6]
02024ce4: ldrb     r1, [r6, #1]
02024ce8: bl       #0x20210c8
02024cec: strb     r0, [sb, #7]
02024cf0: ldrh     r0, [sb, #0xe]
02024cf4: ands     r0, r0, #0x80
02024cf8: bne      #0x2024d28
02024cfc: add      r0, sb, #0x100
02024d00: ldrh     r0, [r0, #0xe]
02024d04: cmp      r0, #0x25
02024d08: blo      #0x2024d28
02024d0c: ldrb     r3, [sb, #7]
02024d10: ldr      r1, [sp, #0xb8]
02024d14: add      r0, sb, #0x124
02024d18: rsb      r3, r3, #0x100
02024d1c: mov      r2, r1
02024d20: and      r3, r3, #0xff
02024d24: bl       #0x2011f74
02024d28: ldrb     r1, [sb, #7]
02024d2c: mov      r0, sb
02024d30: str      r1, [sp]
02024d34: ldrsh    r1, [sb, #0x22]
02024d38: ldrsh    r2, [sb, #0x26]
02024d3c: ldrsh    r3, [sb, #0x24]
02024d40: bl       #0x20213a8
02024d44: add      r8, r8, #4
02024d48: b        #0x202632c
```

## op 0x5c  @ 0x2024d4c
```
02024d4c: ldr      r7, [sb, #0x38]
02024d50: ldr      r6, [sb, #0x3c]
02024d54: ldrb     r3, [r8, #2]
02024d58: ldrb     r2, [r8, #3]
02024d5c: ldrb     r1, [r8, #4]
02024d60: ldrb     r0, [r8, #5]
02024d64: add      r2, r3, r2, lsl #8
02024d68: add      r2, r2, r7, asr #8
02024d6c: add      r0, r1, r0, lsl #8
02024d70: add      r1, r0, r6, asr #8
02024d74: lsl      r0, r2, #0x10
02024d78: lsr      r0, r0, #0x10
02024d7c: lsl      r1, r1, #0x10
02024d80: lsr      r1, r1, #0x10
02024d84: ldrb     r3, [r8, #6]
02024d88: ldrb     r2, [r8, #7]
02024d8c: add      r2, r3, r2, lsl #8
02024d90: lsl      r2, r2, #0x10
02024d94: lsr      r2, r2, #0x10
02024d98: bl       #0x20190a0
02024d9c: add      r8, r8, #8
02024da0: b        #0x202632c
```

## op 0x5d  @ 0x2024da4
```
02024da4: mov      r6, r8
02024da8: bl       #0x2020aa0
02024dac: cmp      r0, #0
02024db0: beq      #0x2024dc0
02024db4: ldrb     r0, [sb, #0x1d]
02024db8: bl       #0x2020ab0
02024dbc: mov      r6, r0
02024dc0: ldrb     r2, [r6, #4]
02024dc4: ldrb     r1, [r6, #5]
02024dc8: ldrb     r3, [r6, #2]
02024dcc: ldrb     r0, [r6, #3]
02024dd0: add      r1, r2, r1, lsl #8
02024dd4: lsl      r1, r1, #0x10
02024dd8: asr      r7, r1, #0x10
02024ddc: ldrb     r2, [r6, #6]
02024de0: ldrb     r1, [r6, #7]
02024de4: add      r0, r3, r0, lsl #8
02024de8: lsl      r0, r0, #0x10
02024dec: add      r1, r2, r1, lsl #8
02024df0: lsl      r1, r1, #0x10
02024df4: lsrs     r6, r1, #0x10
02024df8: asr      r0, r0, #0x10
02024dfc: moveq    r6, r5
02024e00: lsl      r0, r0, #8
02024e04: mov      r1, r6
02024e08: bl       #0x20b5e30
02024e0c: lsl      r0, r0, #0x10
02024e10: asr      sl, r0, #0x10
02024e14: lsl      r0, r7, #8
02024e18: mov      r1, r6
02024e1c: bl       #0x20b5e30
02024e20: ldr      r2, [sp, #0xbc]
02024e24: and      r3, r6, #0xff
02024e28: str      r2, [sp]
02024e2c: lsl      r0, r0, #0x10
02024e30: str      r3, [sp, #4]
02024e34: asr      r3, r0, #0x10
02024e38: mov      r1, sl
02024e3c: mov      r0, sb
02024e40: bl       #0x2021374
02024e44: add      r8, r8, #8
02024e48: b        #0x202632c
```

## op 0x5e  @ 0x2024e4c
```
02024e4c: ldrb     r0, [sb, #0x1a]
02024e50: ldrb     r1, [r8, #1]
02024e54: bl       #0x2027b34
02024e58: movs     r7, r0
02024e5c: beq      #0x2024ec8
02024e60: add      r6, r8, #2
02024e64: bl       #0x2020aa0
02024e68: cmp      r0, #0
02024e6c: beq      #0x2024e7c
02024e70: ldrb     r0, [sb, #0x1d]
02024e74: bl       #0x2020ab0
02024e78: mov      r6, r0
02024e7c: ldr      r0, [r7, #0x38]
02024e80: ldr      r3, [r7, #0x3c]
02024e84: ldrb     sl, [r6]
02024e88: ldrb     r7, [r6, #1]
02024e8c: ldrb     r2, [r6, #2]
02024e90: ldrb     r1, [r6, #3]
02024e94: add      r6, sl, r7, lsl #8
02024e98: add      r6, r6, r0, asr #8
02024e9c: add      r0, r2, r1, lsl #8
02024ea0: add      r1, r0, r3, asr #8
02024ea4: lsl      r0, r6, #0x10
02024ea8: asr      r2, r0, #0x10
02024eac: lsl      r0, r1, #0x10
02024eb0: cmp      sb, #0
02024eb4: asr      r1, r0, #0x10
02024eb8: lslne    r0, r2, #8
02024ebc: strne    r0, [sb, #0x38]
02024ec0: lslne    r0, r1, #8
02024ec4: strne    r0, [sb, #0x3c]
02024ec8: add      r8, r8, #6
02024ecc: b        #0x202632c
```

## op 0x5f  @ 0x2024ed0
```
02024ed0: ldrb     r0, [sb, #0x1a]
02024ed4: ldrb     r1, [r8, #1]
02024ed8: bl       #0x2027b34
02024edc: movs     r7, r0
02024ee0: beq      #0x2024f6c
02024ee4: add      r6, r8, #2
02024ee8: bl       #0x2020aa0
02024eec: cmp      r0, #0
02024ef0: beq      #0x2024f00
02024ef4: ldrb     r0, [sb, #0x1d]
02024ef8: bl       #0x2020ab0
02024efc: mov      r6, r0
02024f00: ldrb     r2, [r6]
02024f04: ldrb     r1, [r6, #1]
02024f08: ldrb     sl, [r6, #2]
02024f0c: ldrb     r3, [r6, #3]
02024f10: add      r1, r2, r1, lsl #8
02024f14: lsl      r1, r1, #0x10
02024f18: ldrh     r2, [r7, #0x12]
02024f1c: ldr      r0, [r7, #0x3c]
02024f20: add      r3, sl, r3, lsl #8
02024f24: add      r3, r3, r0, asr #8
02024f28: ands     r0, r2, #1
02024f2c: asr      r1, r1, #0x10
02024f30: mvnne    r2, #0
02024f34: smulbbne r1, r1, r2
02024f38: lslne    r1, r1, #0x10
02024f3c: asrne    r1, r1, #0x10
02024f40: ldr      r2, [r7, #0x38]
02024f44: lsl      r0, r3, #0x10
02024f48: add      r1, r1, r2, asr #8
02024f4c: lsl      r1, r1, #0x10
02024f50: asr      r1, r1, #0x10
02024f54: cmp      sb, #0
02024f58: asr      r0, r0, #0x10
02024f5c: lslne    r1, r1, #8
02024f60: strne    r1, [sb, #0x38]
02024f64: lslne    r0, r0, #8
02024f68: strne    r0, [sb, #0x3c]
02024f6c: add      r8, r8, #6
02024f70: b        #0x202632c
```

## op 0x60  @ 0x2024f74
```
02024f74: add      r0, sb, #0x100
02024f78: ldrh     r0, [r0, #0xe]
02024f7c: add      r8, r8, #2
02024f80: cmp      r0, #0x25
02024f84: addlo    r0, sb, #0x200
02024f88: ldrhlo   r1, [r0, #0x54]
02024f8c: orrlo    r1, r1, #0x100
02024f90: strhlo   r1, [r0, #0x54]
02024f94: b        #0x202632c
```

## op 0x61  @ 0x202632c
```
invalid
```

## op 0x62  @ 0x202632c
```
invalid
```

## op 0x63  @ 0x2024f98
```
02024f98: ldrh     r0, [sb, #0xe]
02024f9c: ands     r1, r0, #0x40
02024fa0: bicne    r0, r0, #0x40
02024fa4: strhne   r0, [sb, #0xe]
02024fa8: addne    r8, r8, #6
02024fac: bne      #0x202632c
02024fb0: ldrb     r0, [r8, #1]
02024fb4: ldrb     r2, [r8, #2]
02024fb8: ldrb     r3, [r8, #3]
02024fbc: add      r0, r7, r0, lsl #8
02024fc0: add      r0, r0, r2, lsl #16
02024fc4: ldr      r6, [sb, #0x44]
02024fc8: add      r0, r0, r3, lsl #24
02024fcc: add      r0, r6, r0
02024fd0: str      r0, [sb, #0x100]
02024fd4: ldr      r0, [sb, #0x100]
02024fd8: add      r1, sb, #0x100
02024fdc: str      r0, [sb, #0x104]
02024fe0: ldr      r0, [sp, #0xc0]
02024fe4: strh     r0, [r1, #0xc]
02024fe8: ldr      r8, [sb, #0x104]
02024fec: b        #0x202632c
```

## op 0x64  @ 0x2024ff0
```
02024ff0: ldrb     r2, [r8, #2]
02024ff4: ldrb     r1, [r8, #3]
02024ff8: ldr      r0, [r4]
02024ffc: add      r8, r8, #4
02025000: add      r1, r2, r1, lsl #8
02025004: add      r0, r0, #0x4d00
02025008: strh     r1, [r0, #0xe2]
0202500c: b        #0x202632c
```

## op 0x65  @ 0x2025010
```
02025010: ldr      r0, [r4]
02025014: ldrb     r1, [r8, #2]
02025018: add      r0, r0, #0x4d00
0202501c: ldrh     r2, [r0, #0xe2]
02025020: ldrb     r0, [r8, #3]
02025024: add      r0, r1, r0, lsl #8
02025028: lsl      r0, r0, #0x10
0202502c: cmp      r2, r0, lsr #16
02025030: addeq    r8, r8, #4
02025034: strne    r5, [sp, #8]
02025038: b        #0x202632c
```

## op 0x66  @ 0x202503c
```
0202503c: ldr      r0, [r4]
02025040: ldrb     r1, [r8, #2]
02025044: add      r0, r0, #0x4d00
02025048: ldrh     r2, [r0, #0xe2]
0202504c: ldrb     r0, [r8, #3]
02025050: add      r0, r1, r0, lsl #8
02025054: lsl      r0, r0, #0x10
02025058: cmp      r2, r0, lsr #16
0202505c: addeq    r8, r8, #8
02025060: beq      #0x202632c
02025064: ldrb     r3, [r8, #4]
02025068: ldrb     r2, [r8, #5]
0202506c: ldrb     r6, [r8, #6]
02025070: ldrb     r7, [r8, #7]
02025074: add      r2, r3, r2, lsl #8
02025078: add      r2, r2, r6, lsl #16
0202507c: ldr      r0, [sb, #0x44]
02025080: add      r2, r2, r7, lsl #24
02025084: add      r0, r0, r2
02025088: str      r0, [sb, #0x100]
0202508c: ldr      r0, [sb, #0x100]
02025090: add      r1, sb, #0x100
02025094: str      r0, [sb, #0x104]
02025098: ldr      r0, [sp, #0xc4]
0202509c: strh     r0, [r1, #0xc]
020250a0: ldr      r8, [sb, #0x104]
020250a4: b        #0x202632c
```

## op 0x67  @ 0x20250a8
```
020250a8: ldrb     r0, [sb, #0x1a]
020250ac: bl       #0x2027bd0
020250b0: movs     r6, r0
020250b4: beq      #0x2025148
020250b8: add      sl, r8, #2
020250bc: bl       #0x2020aa0
020250c0: cmp      r0, #0
020250c4: beq      #0x20250d4
020250c8: ldrb     r0, [sb, #0x1d]
020250cc: bl       #0x2020ab0
020250d0: mov      sl, r0
020250d4: ldrb     r2, [sl]
020250d8: ldrb     r0, [sl, #1]
020250dc: ldrb     r3, [sl, #2]
020250e0: ldr      r1, [r6, #0x3c]
020250e4: add      r0, r2, r0, lsl #8
020250e8: ldrb     r2, [sl, #3]
020250ec: lsl      r0, r0, #0x10
020250f0: asr      r7, r0, #0x10
020250f4: add      r2, r3, r2, lsl #8
020250f8: add      r1, r2, r1, asr #8
020250fc: lsl      r1, r1, #0x10
02025100: mov      r0, r6
02025104: asr      sl, r1, #0x10
02025108: bl       #0x2021440
0202510c: cmp      r0, #0
02025110: mvneq    r0, #0
02025114: smulbbeq r0, r7, r0
02025118: lsleq    r0, r0, #0x10
0202511c: asreq    r7, r0, #0x10
02025120: ldr      r0, [r6, #0x38]
02025124: cmp      sb, #0
02025128: lsl      r0, r0, #8
0202512c: add      r0, r7, r0, asr #16
02025130: lsl      r0, r0, #0x10
02025134: asr      r0, r0, #0x10
02025138: lslne    r0, r0, #8
0202513c: strne    r0, [sb, #0x38]
02025140: lslne    r0, sl, #8
02025144: strne    r0, [sb, #0x3c]
02025148: add      r8, r8, #6
0202514c: b        #0x202632c
```

## op 0x68  @ 0x2025150
```
02025150: ldr      r6, [sb]
02025154: cmp      r6, #0
02025158: beq      #0x20251ec
0202515c: add      sl, r8, #2
02025160: bl       #0x2020aa0
02025164: cmp      r0, #0
02025168: beq      #0x2025178
0202516c: ldrb     r0, [sb, #0x1d]
02025170: bl       #0x2020ab0
02025174: mov      sl, r0
02025178: ldrb     r2, [sl]
0202517c: ldrb     r0, [sl, #1]
02025180: ldrb     r3, [sl, #2]
02025184: ldr      r1, [r6, #0x3c]
02025188: add      r0, r2, r0, lsl #8
0202518c: ldrb     r2, [sl, #3]
02025190: lsl      r0, r0, #0x10
02025194: asr      r7, r0, #0x10
02025198: add      r2, r3, r2, lsl #8
0202519c: add      r1, r2, r1, asr #8
020251a0: lsl      r1, r1, #0x10
020251a4: mov      r0, r6
020251a8: asr      sl, r1, #0x10
020251ac: bl       #0x2021440
020251b0: cmp      r0, #0
020251b4: mvneq    r0, #0
020251b8: smulbbeq r0, r7, r0
020251bc: lsleq    r0, r0, #0x10
020251c0: asreq    r7, r0, #0x10
020251c4: ldr      r0, [r6, #0x38]
020251c8: cmp      sb, #0
020251cc: lsl      r0, r0, #8
020251d0: add      r0, r7, r0, asr #16
020251d4: lsl      r0, r0, #0x10
020251d8: asr      r0, r0, #0x10
020251dc: lslne    r0, r0, #8
020251e0: strne    r0, [sb, #0x38]
020251e4: lslne    r0, sl, #8
020251e8: strne    r0, [sb, #0x3c]
020251ec: add      r8, r8, #6
020251f0: b        #0x202632c
```

## op 0x69  @ 0x20251f4
```
020251f4: ldrb     r0, [sb, #0x1a]
020251f8: bl       #0x2027bd0
020251fc: mov      r7, r0
02025200: mov      r6, r8
02025204: bl       #0x2020aa0
02025208: cmp      r0, #0
0202520c: beq      #0x202521c
02025210: ldrb     r0, [sb, #0x1d]
02025214: bl       #0x2020ab0
02025218: mov      r6, r0
0202521c: ldrb     r1, [r6, #2]
02025220: ldrb     r0, [r6, #3]
02025224: ldr      r2, [r7, #0x38]
02025228: add      r0, r1, r0, lsl #8
0202522c: lsl      r0, r0, #0x10
02025230: lsrs     r6, r0, #0x10
02025234: ldr      r0, [sb, #0x38]
02025238: moveq    r6, r5
0202523c: mov      r1, r6
02025240: sub      r0, r2, r0
02025244: bl       #0x20b5e30
02025248: ldr      r2, [r7, #0x3c]
0202524c: mov      r7, r0
02025250: ldr      r0, [sb, #0x3c]
02025254: mov      r1, r6
02025258: sub      r0, r2, r0
0202525c: bl       #0x20b5e30
02025260: ldr      r2, [sp, #0xc8]
02025264: lsl      r1, r7, #0x10
02025268: and      r3, r6, #0xff
0202526c: str      r2, [sp]
02025270: lsl      r0, r0, #0x10
02025274: str      r3, [sp, #4]
02025278: asr      r3, r0, #0x10
0202527c: asr      r1, r1, #0x10
02025280: mov      r0, sb
02025284: bl       #0x2021374
02025288: add      r8, r8, #4
0202528c: b        #0x202632c
```

## op 0x6a  @ 0x2025290
```
02025290: ldr      r6, [sb]
02025294: cmp      r6, #0
02025298: beq      #0x2025324
0202529c: mov      r7, r8
020252a0: bl       #0x2020aa0
020252a4: cmp      r0, #0
020252a8: beq      #0x20252b8
020252ac: ldrb     r0, [sb, #0x1d]
020252b0: bl       #0x2020ab0
020252b4: mov      r7, r0
020252b8: ldrb     r1, [r7, #2]
020252bc: ldrb     r0, [r7, #3]
020252c0: ldr      r2, [r6, #0x38]
020252c4: add      r0, r1, r0, lsl #8
020252c8: lsl      r0, r0, #0x10
020252cc: lsrs     r7, r0, #0x10
020252d0: ldr      r0, [sb, #0x38]
020252d4: moveq    r7, r5
020252d8: mov      r1, r7
020252dc: sub      r0, r2, r0
020252e0: bl       #0x20b5e30
020252e4: ldr      r2, [r6, #0x3c]
020252e8: mov      r6, r0
020252ec: ldr      r0, [sb, #0x3c]
020252f0: mov      r1, r7
020252f4: sub      r0, r2, r0
020252f8: bl       #0x20b5e30
020252fc: ldr      r2, [sp, #0xcc]
02025300: lsl      r1, r6, #0x10
02025304: and      r3, r7, #0xff
02025308: str      r2, [sp]
0202530c: lsl      r0, r0, #0x10
02025310: str      r3, [sp, #4]
02025314: asr      r3, r0, #0x10
02025318: asr      r1, r1, #0x10
0202531c: mov      r0, sb
02025320: bl       #0x2021374
02025324: add      r8, r8, #4
02025328: b        #0x202632c
```

## op 0x6b  @ 0x202532c
```
0202532c: ldrb     r0, [sb, #0x1a]
02025330: ldrb     r1, [r8, #1]
02025334: bl       #0x2027b34
02025338: movs     r7, r0
0202533c: beq      #0x20253c8
02025340: mov      r6, r8
02025344: bl       #0x2020aa0
02025348: cmp      r0, #0
0202534c: beq      #0x202535c
02025350: ldrb     r0, [sb, #0x1d]
02025354: bl       #0x2020ab0
02025358: mov      r6, r0
0202535c: ldrb     r1, [r6, #2]
02025360: ldrb     r0, [r6, #3]
02025364: ldr      r2, [r7, #0x38]
02025368: add      r0, r1, r0, lsl #8
0202536c: lsl      r0, r0, #0x10
02025370: lsrs     r6, r0, #0x10
02025374: ldr      r0, [sb, #0x38]
02025378: moveq    r6, r5
0202537c: mov      r1, r6
02025380: sub      r0, r2, r0
02025384: bl       #0x20b5e30
02025388: ldr      r2, [r7, #0x3c]
0202538c: mov      r7, r0
02025390: ldr      r0, [sb, #0x3c]
02025394: mov      r1, r6
02025398: sub      r0, r2, r0
0202539c: bl       #0x20b5e30
020253a0: ldr      r2, [sp, #0xd0]
020253a4: lsl      r1, r7, #0x10
020253a8: and      r3, r6, #0xff
020253ac: str      r2, [sp]
020253b0: lsl      r0, r0, #0x10
020253b4: str      r3, [sp, #4]
020253b8: asr      r3, r0, #0x10
020253bc: asr      r1, r1, #0x10
020253c0: mov      r0, sb
020253c4: bl       #0x2021374
020253c8: add      r8, r8, #4
020253cc: b        #0x202632c
```

## op 0x6c  @ 0x20253d0
```
020253d0: add      r7, r8, #2
020253d4: bl       #0x2020aa0
020253d8: cmp      r0, #0
020253dc: beq      #0x20253ec
020253e0: ldrb     r0, [sb, #0x1d]
020253e4: bl       #0x2020ab0
020253e8: mov      r7, r0
020253ec: ldrb     r3, [r7]
020253f0: ldrb     r0, [r7, #1]
020253f4: ldr      r1, [sb, #0x3c]
020253f8: ldrb     r2, [r7, #2]
020253fc: add      r0, r3, r0, lsl #8
02025400: lsl      r0, r0, #0x10
02025404: asr      r6, r0, #0x10
02025408: lsl      r0, r1, #8
0202540c: ldrb     r1, [r7, #3]
02025410: asr      r3, r0, #0x10
02025414: mov      r0, sb
02025418: add      r1, r2, r1, lsl #8
0202541c: lsl      r1, r1, #0x10
02025420: add      r1, r3, r1, asr #16
02025424: lsl      r1, r1, #0x10
02025428: asr      r7, r1, #0x10
0202542c: bl       #0x2021440
02025430: cmp      r0, #0
02025434: mvneq    r0, #0
02025438: smulbbeq r0, r6, r0
0202543c: lsleq    r0, r0, #0x10
02025440: asreq    r6, r0, #0x10
02025444: ldr      r0, [sb, #0x38]
02025448: cmp      sb, #0
0202544c: lsl      r0, r0, #8
02025450: add      r0, r6, r0, asr #16
02025454: lsl      r0, r0, #0x10
02025458: asr      r0, r0, #0x10
0202545c: lslne    r0, r0, #8
02025460: strne    r0, [sb, #0x38]
02025464: lslne    r0, r7, #8
02025468: strne    r0, [sb, #0x3c]
0202546c: add      r8, r8, #6
02025470: b        #0x202632c
```

## op 0x6d  @ 0x2025528
```
02025528: add      r6, r8, #1
0202552c: bl       #0x2020aa0
02025530: cmp      r0, #0
02025534: beq      #0x2025544
02025538: ldrb     r0, [sb, #0x1d]
0202553c: bl       #0x2020ab0
02025540: mov      r6, r0
02025544: mov      r0, sb
02025548: bl       #0x2021440
0202554c: cmp      r0, #0
02025550: beq      #0x202556c
02025554: ldr      r1, [sp, #0xdc]
02025558: ldrb     r3, [r6]
0202555c: add      r0, sb, #0x124
02025560: mov      r2, r1
02025564: bl       #0x2011f38
02025568: b        #0x202558c
0202556c: ldrb     r2, [r6]
02025570: ldr      r1, [sp, #0xe0]
02025574: add      r0, sb, #0x124
02025578: rsb      r2, r2, #0
0202557c: lsl      r2, r2, #0x10
02025580: asr      r3, r2, #0x10
02025584: mov      r2, r1
02025588: bl       #0x2011f38
0202558c: add      r8, r8, #2
02025590: b        #0x202632c
```

## op 0x6e  @ 0x2025474
```
02025474: add      r6, r8, #1
02025478: bl       #0x2020aa0
0202547c: cmp      r0, #0
02025480: beq      #0x2025490
02025484: ldrb     r0, [sb, #0x1d]
02025488: bl       #0x2020ab0
0202548c: mov      r6, r0
02025490: mov      r0, sb
02025494: bl       #0x2021440
02025498: cmp      r0, #0
0202549c: bne      #0x20254f4
020254a0: ldrh     r0, [sb, #0xe]
020254a4: ands     r1, r0, #4
020254a8: orreq    r0, r0, #4
020254ac: strheq   r0, [sb, #0xe]
020254b0: ldrheq   r0, [sb, #0x12]
020254b4: orreq    r0, r0, #2
020254b8: strheq   r0, [sb, #0x12]
020254bc: beq      #0x20254d4
020254c0: bic      r0, r0, #4
020254c4: strh     r0, [sb, #0xe]
020254c8: ldrh     r0, [sb, #0x12]
020254cc: bic      r0, r0, #2
020254d0: strh     r0, [sb, #0x12]
020254d4: ldrb     r2, [r6]
020254d8: ldr      r1, [sp, #0xd4]
020254dc: add      r0, sb, #0x124
020254e0: sub      r2, r2, #0x80
020254e4: and      r3, r2, #0xff
020254e8: mov      r2, r1
020254ec: bl       #0x2011f74
020254f0: b        #0x2025510
020254f4: ldrb     r2, [r6]
020254f8: ldr      r1, [sp, #0xd8]
020254fc: add      r0, sb, #0x124
02025500: rsb      r2, r2, #0x100
02025504: and      r3, r2, #0xff
02025508: mov      r2, r1
0202550c: bl       #0x2011f74
02025510: add      r8, r8, #2
02025514: b        #0x202632c
02025518: streq    r0, [r0], #-0x2b0
0202551c: streq    r0, [r0], #-0x2b8
02025520: streq    r0, [r0], #-0x2b4
02025524: andeq    r6, fp, #212, #8
```

## op 0x6f  @ 0x202632c
```
invalid
```

## op 0x70  @ 0x2025594
```
02025594: ldrb     r2, [r8, #1]
02025598: ldrb     r0, [r8, #2]
0202559c: ldrb     r1, [r8, #3]
020255a0: add      r0, r2, r0, lsl #8
020255a4: lsl      r0, r0, #0x10
020255a8: lsr      r0, r0, #0x10
020255ac: bl       #0x20193fc
020255b0: add      r8, r8, #4
020255b4: b        #0x202632c
```

## op 0x71  @ 0x20255b8
```
020255b8: ldr      r1, [r4]
020255bc: ldrb     r0, [sb, #0x1a]
020255c0: add      r2, r1, #0x4d00
020255c4: ldrb     r7, [r8, #2]
020255c8: ldrb     r1, [r8, #3]
020255cc: ldrsh    r6, [r2, #0xec]
020255d0: ldrsh    r3, [r2, #0xe8]
020255d4: add      r1, r7, r1, lsl #8
020255d8: lsl      r1, r1, #0x10
020255dc: add      r3, r6, r3
020255e0: asr      r1, r1, #0x10
020255e4: add      r1, r1, r3, asr #1
020255e8: lsl      r1, r1, #8
020255ec: ldrsh    r6, [r2, #0xee]
020255f0: ldrb     r3, [r8, #4]
020255f4: ldrb     r2, [r8, #5]
020255f8: add      r2, r3, r2, lsl #8
020255fc: lsl      r2, r2, #0x10
02025600: sub      r2, r6, r2, asr #16
02025604: lsl      r2, r2, #8
02025608: bl       #0x2028cf8
0202560c: add      r8, r8, #6
02025610: b        #0x202632c
```

## op 0x72  @ 0x2025614
```
02025614: ldrb     r0, [sb, #0x1a]
02025618: bl       #0x2027bd0
0202561c: mov      r1, r0
02025620: mov      r0, sb
02025624: bl       #0x201ee60
02025628: mov      r7, r0
0202562c: add      r6, r8, #2
02025630: bl       #0x2020aa0
02025634: cmp      r0, #0
02025638: beq      #0x2025648
0202563c: ldrb     r0, [sb, #0x1d]
02025640: bl       #0x2020ab0
02025644: mov      r6, r0
02025648: mov      r0, sb
0202564c: bl       #0x2021440
02025650: cmp      r0, #0
02025654: beq      #0x2025670
02025658: mov      r2, r7
0202565c: ldrb     r0, [r6]
02025660: ldrb     r1, [r6, #1]
02025664: bl       #0x20210c8
02025668: strb     r0, [sb, #7]
0202566c: b        #0x202568c
02025670: mov      r2, r7
02025674: ldrb     r0, [r6]
02025678: ldrb     r1, [r6, #1]
0202567c: rsb      r0, r0, #0x100
02025680: and      r0, r0, #0xff
02025684: bl       #0x20210c8
02025688: strb     r0, [sb, #7]
0202568c: ldrh     r0, [sb, #0xe]
02025690: ands     r0, r0, #0x80
02025694: bne      #0x20256c4
02025698: add      r0, sb, #0x100
0202569c: ldrh     r0, [r0, #0xe]
020256a0: cmp      r0, #0x25
020256a4: blo      #0x20256c4
020256a8: ldrb     r3, [sb, #7]
020256ac: ldr      r1, [sp, #0xe4]
020256b0: add      r0, sb, #0x124
020256b4: rsb      r3, r3, #0x100
020256b8: mov      r2, r1
020256bc: and      r3, r3, #0xff
020256c0: bl       #0x2011f74
020256c4: ldrb     r1, [sb, #7]
020256c8: mov      r0, sb
020256cc: str      r1, [sp]
020256d0: ldrsh    r1, [sb, #0x22]
020256d4: ldrsh    r2, [sb, #0x26]
020256d8: ldrsh    r3, [sb, #0x24]
020256dc: bl       #0x20213a8
020256e0: add      r8, r8, #4
020256e4: b        #0x202632c
```

## op 0x73  @ 0x20256e8
```
020256e8: ldrb     r0, [sb, #0x1a]
020256ec: bl       #0x2027bd0
020256f0: ldr      r1, [r0, #0x38]
020256f4: ldr      r2, [sb, #0x38]
020256f8: ldr      r0, [r0, #0x3c]
020256fc: sub      r1, r2, r1
02025700: ldr      r2, [sb, #0x3c]
02025704: ldrb     r7, [r8, #2]
02025708: ldrb     r6, [r8, #3]
0202570c: sub      r0, r2, r0
02025710: ldrb     r3, [r8, #4]
02025714: add      r6, r7, r6, lsl #8
02025718: ldrb     r2, [r8, #5]
0202571c: add      r6, r6, r1, asr #8
02025720: add      r1, r3, r2, lsl #8
02025724: add      r2, r1, r0, asr #8
02025728: add      r0, r6, r6, asr #31
0202572c: eor      r1, r0, r6, asr #31
02025730: add      r0, r2, r2, asr #31
02025734: eor      r0, r0, r2, asr #31
02025738: add      r1, r1, r0
0202573c: mov      r0, #0xc0
02025740: mul      r0, r1, r0
02025744: asr      r1, r0, #8
02025748: ldrb     r0, [r8, #1]
0202574c: cmp      r1, r0
02025750: addge    r8, r8, #0xa
02025754: bge      #0x202632c
02025758: ldrb     r3, [r8, #6]
0202575c: ldrb     r2, [r8, #7]
02025760: ldrb     r6, [r8, #8]
02025764: ldrb     r7, [r8, #9]
02025768: add      r2, r3, r2, lsl #8
0202576c: add      r2, r2, r6, lsl #16
02025770: ldr      r0, [sb, #0x44]
02025774: add      r2, r2, r7, lsl #24
02025778: add      r0, r0, r2
0202577c: str      r0, [sb, #0x100]
02025780: ldr      r0, [sb, #0x100]
02025784: add      r1, sb, #0x100
02025788: str      r0, [sb, #0x104]
0202578c: ldr      r0, [sp, #0xe8]
02025790: strh     r0, [r1, #0xc]
02025794: ldr      r8, [sb, #0x104]
02025798: b        #0x202632c
```

## op 0x74  @ 0x202579c
```
0202579c: ldrb     r0, [sb, #0x1a]
020257a0: bl       #0x2027c00
020257a4: mov      r6, r0
020257a8: bl       #0x2012fd4
020257ac: cmp      r0, #0xb
020257b0: beq      #0x20257dc
020257b4: bl       #0x2012fd4
020257b8: cmp      r0, #0xc
020257bc: beq      #0x20257dc
020257c0: mov      r0, r6
020257c4: ldrb     r2, [r8, #2]
020257c8: ldrb     r1, [r8, #3]
020257cc: add      r1, r2, r1, lsl #8
020257d0: lsl      r1, r1, #0x10
020257d4: lsr      r1, r1, #0x10
020257d8: bl       #0x2029428
020257dc: add      r8, r8, #4
020257e0: b        #0x202632c
```

## op 0x75  @ 0x20257e4
```
020257e4: add      r8, r8, #2
020257e8: ldrh     r0, [sb, #0x12]
020257ec: orr      r0, r0, #0x10
020257f0: strh     r0, [sb, #0x12]
020257f4: b        #0x202632c
```

## op 0x76  @ 0x20257f8
```
020257f8: ldrb     r0, [sb, #0x1a]
020257fc: bl       #0x2027bd0
02025800: mov      sl, r0
02025804: add      r6, r8, #2
02025808: bl       #0x2020aa0
0202580c: cmp      r0, #0
02025810: beq      #0x2025820
02025814: ldrb     r0, [sb, #0x1d]
02025818: bl       #0x2020ab0
0202581c: mov      r6, r0
02025820: ldrb     r1, [r6, #4]
02025824: ldrb     r0, [r6, #5]
02025828: ldrb     r3, [r6]
0202582c: ldrb     r2, [r6, #2]
02025830: add      r0, r1, r0, lsl #8
02025834: lsl      r0, r0, #0x10
02025838: lsrs     r7, r0, #0x10
0202583c: ldrb     r0, [r6, #1]
02025840: ldrb     r1, [r6, #3]
02025844: moveq    r7, r5
02025848: add      r0, r3, r0, lsl #8
0202584c: add      r1, r2, r1, lsl #8
02025850: lsl      fp, r1, #0x10
02025854: ldr      r3, [sl, #0x38]
02025858: ldr      r2, [sb, #0x38]
0202585c: lsl      r0, r0, #0x10
02025860: sub      r2, r3, r2
02025864: mov      r1, r7
02025868: add      r0, r2, r0, asr #8
0202586c: bl       #0x20b5e30
02025870: lsl      r0, r0, #0x10
02025874: asr      r6, r0, #0x10
02025878: ldr      r2, [sl, #0x3c]
0202587c: ldr      r0, [sb, #0x3c]
02025880: mov      r1, r7
02025884: sub      r0, r2, r0
02025888: add      r0, r0, fp, asr #8
0202588c: bl       #0x20b5e30
02025890: ldr      r2, [sp, #0xec]
02025894: and      r3, r7, #0xff
02025898: str      r2, [sp]
0202589c: lsl      r0, r0, #0x10
020258a0: str      r3, [sp, #4]
020258a4: asr      r3, r0, #0x10
020258a8: mov      r1, r6
020258ac: mov      r0, sb
020258b0: bl       #0x2021374
020258b4: add      r8, r8, #8
020258b8: b        #0x202632c
```

## op 0x77  @ 0x20258bc
```
020258bc: ldr      sl, [sb]
020258c0: cmp      sl, #0
020258c4: beq      #0x202597c
020258c8: add      r8, r8, #2
020258cc: mov      r6, r8
020258d0: bl       #0x2020aa0
020258d4: cmp      r0, #0
020258d8: beq      #0x20258e8
020258dc: ldrb     r0, [sb, #0x1d]
020258e0: bl       #0x2020ab0
020258e4: mov      r6, r0
020258e8: ldrb     r1, [r6, #4]
020258ec: ldrb     r0, [r6, #5]
020258f0: ldrb     r3, [r6]
020258f4: ldrb     r2, [r6, #2]
020258f8: add      r0, r1, r0, lsl #8
020258fc: lsl      r0, r0, #0x10
02025900: lsrs     r7, r0, #0x10
02025904: ldrb     r0, [r6, #1]
02025908: ldrb     r1, [r6, #3]
0202590c: moveq    r7, r5
02025910: add      r0, r3, r0, lsl #8
02025914: add      r1, r2, r1, lsl #8
02025918: lsl      fp, r1, #0x10
0202591c: ldr      r3, [sl, #0x38]
02025920: ldr      r2, [sb, #0x38]
02025924: lsl      r0, r0, #0x10
02025928: sub      r2, r3, r2
0202592c: mov      r1, r7
02025930: add      r0, r2, r0, asr #8
02025934: bl       #0x20b5e30
02025938: lsl      r0, r0, #0x10
0202593c: asr      r6, r0, #0x10
02025940: ldr      r2, [sl, #0x3c]
02025944: ldr      r0, [sb, #0x3c]
02025948: mov      r1, r7
0202594c: sub      r0, r2, r0
02025950: add      r0, r0, fp, asr #8
02025954: bl       #0x20b5e30
02025958: ldr      r2, [sp, #0xf0]
0202595c: and      r3, r7, #0xff
02025960: str      r2, [sp]
02025964: lsl      r0, r0, #0x10
02025968: str      r3, [sp, #4]
0202596c: asr      r3, r0, #0x10
02025970: mov      r1, r6
02025974: mov      r0, sb
02025978: bl       #0x2021374
0202597c: add      r8, r8, #6
02025980: b        #0x202632c
```

## op 0x78  @ 0x2025984
```
02025984: ldrb     r0, [sb, #0x1a]
02025988: bl       #0x2027bd0
0202598c: mov      r7, r0
02025990: ldrb     r6, [r8, #2]
02025994: ldrb     r1, [r8, #3]
02025998: ldrb     sl, [r8, #4]
0202599c: ldrb     r0, [r8, #5]
020259a0: add      r1, r6, r1, lsl #8
020259a4: add      r1, r1, sl, lsl #16
020259a8: add      sl, r1, r0, lsl #24
020259ac: ldrb     fp, [r8, #6]
020259b0: ldrb     r6, [r8, #7]
020259b4: ldrb     r2, [r8, #8]
020259b8: ldrb     r3, [r8, #9]
020259bc: add      r6, fp, r6, lsl #8
020259c0: add      r2, r6, r2, lsl #16
020259c4: ldrb     r1, [r8, #1]
020259c8: mov      r0, sb
020259cc: add      fp, r2, r3, lsl #24
020259d0: bl       #0x202247c
020259d4: movs     r6, r0
020259d8: beq      #0x2025a40
020259dc: ldr      r3, [r7, #0x38]
020259e0: mov      r2, fp
020259e4: str      r3, [sp, #0xf4]
020259e8: ldrb     fp, [r8, #0xa]
020259ec: ldrb     r3, [r8, #0xb]
020259f0: mov      r1, sl
020259f4: ldr      sl, [r7, #0x3c]
020259f8: add      fp, fp, r3, lsl #8
020259fc: ldr      r3, [sp, #0xf4]
02025a00: ldrb     r7, [r8, #0xc]
02025a04: ldrb     ip, [r8, #0xd]
02025a08: add      r3, fp, r3, asr #8
02025a0c: lsl      r3, r3, #0x10
02025a10: add      r7, r7, ip, lsl #8
02025a14: add      sl, r7, sl, asr #8
02025a18: asr      r7, r3, #0x10
02025a1c: lsl      r3, sl, #0x10
02025a20: asr      sl, r3, #0x10
02025a24: ldr      r3, [sp, #0xf8]
02025a28: bl       #0x202216c
02025a2c: cmp      r6, #0
02025a30: lslne    r0, r7, #8
02025a34: strne    r0, [r6, #0x38]
02025a38: lslne    r0, sl, #8
02025a3c: strne    r0, [r6, #0x3c]
02025a40: add      r8, r8, #0xe
02025a44: b        #0x202632c
```

## op 0x79  @ 0x2025a48
```
02025a48: ldrb     r0, [sb, #0x1a]
02025a4c: bl       #0x2027bd0
02025a50: ldrb     r6, [r8, #2]
02025a54: ldrb     r3, [r8, #3]
02025a58: ldrb     sl, [r8, #4]
02025a5c: mov      r7, r0
02025a60: add      r3, r6, r3, lsl #8
02025a64: ldrb     r2, [r8, #5]
02025a68: add      r3, r3, sl, lsl #16
02025a6c: ldrb     r6, [r8, #6]
02025a70: add      sl, r3, r2, lsl #24
02025a74: ldrb     r3, [r8, #7]
02025a78: add      r2, sb, #0x100
02025a7c: ldrh     r2, [r2, #0xe]
02025a80: ldrb     r0, [r8, #8]
02025a84: add      r3, r6, r3, lsl #8
02025a88: cmp      r2, #0x25
02025a8c: add      r0, r3, r0, lsl #16
02025a90: ldrb     r1, [r8, #9]
02025a94: ldrlo    r3, [sb, #0x244]
02025a98: addlo    r2, sb, #0x164
02025a9c: add      fp, r0, r1, lsl #24
02025aa0: ldrhs    r3, [sb, #0x40]
02025aa4: ldr      r0, [sp, #0xfc]
02025aa8: addhs    r2, sb, #0x44
02025aac: str      r0, [sp]
02025ab0: ldrb     r1, [r8, #1]
02025ab4: mov      r0, sb
02025ab8: bl       #0x20225c8
02025abc: movs     r6, r0
02025ac0: beq      #0x2025b20
02025ac4: mov      r1, sl
02025ac8: ldrb     ip, [r8, #0xa]
02025acc: ldrb     sl, [r8, #0xb]
02025ad0: mov      r2, fp
02025ad4: ldr      fp, [r7, #0x38]
02025ad8: add      sl, ip, sl, lsl #8
02025adc: ldrb     r3, [r8, #0xc]
02025ae0: ldrb     lr, [r8, #0xd]
02025ae4: ldr      r7, [r7, #0x3c]
02025ae8: add      sl, sl, fp, asr #8
02025aec: add      r3, r3, lr, lsl #8
02025af0: add      fp, r3, r7, asr #8
02025af4: lsl      r3, sl, #0x10
02025af8: asr      r7, r3, #0x10
02025afc: lsl      r3, fp, #0x10
02025b00: asr      sl, r3, #0x10
02025b04: ldr      r3, [sp, #0x100]
02025b08: bl       #0x202216c
02025b0c: cmp      r6, #0
02025b10: lslne    r0, r7, #8
02025b14: strne    r0, [r6, #0x38]
02025b18: lslne    r0, sl, #8
02025b1c: strne    r0, [r6, #0x3c]
02025b20: add      r8, r8, #0xe
02025b24: b        #0x202632c
```

## op 0x7a  @ 0x2025b28
```
02025b28: ldrb     r1, [sb, #0x1d]
02025b2c: ldrb     r0, [r8, #1]
02025b30: cmp      r1, r0
02025b34: addeq    r8, r8, #6
02025b38: beq      #0x202632c
02025b3c: ldrb     r3, [r8, #2]
02025b40: ldrb     r2, [r8, #3]
02025b44: ldrb     r6, [r8, #4]
02025b48: ldrb     r7, [r8, #5]
02025b4c: add      r2, r3, r2, lsl #8
02025b50: add      r2, r2, r6, lsl #16
02025b54: ldr      r0, [sb, #0x44]
02025b58: add      r2, r2, r7, lsl #24
02025b5c: add      r0, r0, r2
02025b60: str      r0, [sb, #0x100]
02025b64: ldr      r0, [sb, #0x100]
02025b68: add      r1, sb, #0x100
02025b6c: str      r0, [sb, #0x104]
02025b70: ldr      r0, [sp, #0x104]
02025b74: strh     r0, [r1, #0xc]
02025b78: ldr      r8, [sb, #0x104]
02025b7c: b        #0x202632c
```

## op 0x7b  @ 0x2025b80
```
02025b80: ldrb     r0, [r8, #1]
02025b84: add      r8, r8, #2
02025b88: add      r6, r8, #4
02025b8c: sub      r0, r0, #1
02025b90: and      r7, r0, #0xff
02025b94: bl       #0x2001998
02025b98: add      r1, r7, #1
02025b9c: bl       #0x20b5e30
02025ba0: lsl      r7, r1, #1
02025ba4: mov      r0, sb
02025ba8: bl       #0x2029000
02025bac: ldrb     r2, [r8, r7]!
02025bb0: ldrb     r1, [r8, #1]
02025bb4: add      r1, r2, r1, lsl #8
02025bb8: lsl      r1, r1, #0x10
02025bbc: lsr      r1, r1, #0x10
02025bc0: bl       #0x200ff9c
02025bc4: mov      r8, r6
02025bc8: b        #0x202632c
```

## op 0x7c  @ 0x2025bcc
```
02025bcc: ldrb     r1, [r8, #1]
02025bd0: mov      r0, sb
02025bd4: bl       #0x2021d2c
02025bd8: cmp      r0, #0
02025bdc: addeq    r8, r8, #6
02025be0: beq      #0x202632c
02025be4: ldrb     r3, [r8, #2]
02025be8: ldrb     r2, [r8, #3]
02025bec: ldrb     r6, [r8, #4]
02025bf0: ldrb     r7, [r8, #5]
02025bf4: add      r2, r3, r2, lsl #8
02025bf8: add      r2, r2, r6, lsl #16
02025bfc: ldr      r0, [sb, #0x44]
02025c00: add      r2, r2, r7, lsl #24
02025c04: add      r0, r0, r2
02025c08: str      r0, [sb, #0x100]
02025c0c: ldr      r0, [sb, #0x100]
02025c10: add      r1, sb, #0x100
02025c14: str      r0, [sb, #0x104]
02025c18: ldr      r0, [sp, #0x108]
02025c1c: strh     r0, [r1, #0xc]
02025c20: ldr      r8, [sb, #0x104]
02025c24: b        #0x202632c
```

## op 0x7d  @ 0x2025c28
```
02025c28: ldrb     r1, [r8, #1]
02025c2c: mov      r0, sb
02025c30: bl       #0x2021d2c
02025c34: cmp      r0, #0
02025c38: ldrne    r1, [sp, #0x90]
02025c3c: add      r8, r8, #2
02025c40: strbne   r1, [r0, #4]
02025c44: b        #0x202632c
```

## op 0x7e  @ 0x2025c48
```
02025c48: add      r8, r8, #2
02025c4c: add      r0, sb, #0x100
02025c50: ldrh     r0, [r0, #0xe]
02025c54: cmp      r0, #0x25
02025c58: bhs      #0x202632c
02025c5c: ldrh     r0, [sb, #0x10]
02025c60: ands     r0, r0, #1
02025c64: beq      #0x2025c88
02025c68: ldr      r0, [sp, #0x10c]
02025c6c: ldr      r1, [sp, #0x48]
02025c70: str      r0, [sb, #0x250]
02025c74: ldrb     r2, [sb, #0x1a]
02025c78: mov      r0, sb
02025c7c: strb     r2, [sb, #0x25d]
02025c80: bl       #0x2021b4c
02025c84: b        #0x202632c
02025c88: ldr      r0, [sp, #0x110]
02025c8c: ldr      r1, [sp, #0x110]
02025c90: str      r0, [sb, #0x250]
02025c94: ldrb     r2, [sb, #0x1a]
02025c98: mov      r0, sb
02025c9c: strb     r2, [sb, #0x25d]
02025ca0: bl       #0x2021b4c
02025ca4: b        #0x202632c
```

## op 0x7f  @ 0x2025ca8
```
02025ca8: add      r8, r8, #2
02025cac: ldrh     r0, [sb, #0x12]
02025cb0: orr      r0, r0, #0x20
02025cb4: strh     r0, [sb, #0x12]
02025cb8: b        #0x202632c
```

## op 0x80  @ 0x2025cbc
```
02025cbc: ldrb     r0, [r8, #1]
02025cc0: bl       #0x2012f9c
02025cc4: add      r8, r8, #2
02025cc8: b        #0x202632c
```

## op 0x81  @ 0x2025ccc
```
02025ccc: add      r8, r8, #2
02025cd0: b        #0x202632c
```

## op 0x82  @ 0x2025cd4
```
02025cd4: add      r8, r8, #2
02025cd8: b        #0x202632c
```

## op 0x83  @ 0x2025cdc
```
02025cdc: bl       #0x2028dac
02025ce0: cmp      r0, sb
02025ce4: addeq    r8, r8, #2
02025ce8: strne    r5, [sp, #8]
02025cec: b        #0x202632c
```

## op 0x84  @ 0x2025cf0
```
02025cf0: ldrb     r1, [r8, #2]
02025cf4: ldrb     r0, [r8, #3]
02025cf8: ldrb     r2, [r8, #4]
02025cfc: ldrb     r3, [r8, #5]
02025d00: add      r0, r1, r0, lsl #8
02025d04: add      r0, r0, r2, lsl #16
02025d08: ldr      r6, [sb, #0x44]
02025d0c: add      r0, r0, r3, lsl #24
02025d10: add      r0, r6, r0
02025d14: bl       #0x2020bb0
02025d18: ldr      r0, [sb]
02025d1c: add      r8, r8, #6
02025d20: cmp      r0, #0
02025d24: ldrbne   r0, [r0, #0x1d]
02025d28: strbne   r0, [sb, #0x1d]
02025d2c: b        #0x202632c
```

## op 0x85  @ 0x2025d30
```
02025d30: ldrb     r2, [r8, #2]
02025d34: ldrb     r1, [r8, #3]
02025d38: ldrb     r3, [r8, #4]
02025d3c: ldrb     r7, [r8, #5]
02025d40: add      r1, r2, r1, lsl #8
02025d44: add      r1, r1, r3, lsl #16
02025d48: add      r7, r1, r7, lsl #24
02025d4c: add      r1, sb, #0x100
02025d50: ldrh     r1, [r1, #0xe]
02025d54: ldrb     r3, [r8, #6]
02025d58: ldrb     r2, [r8, #7]
02025d5c: ldrb     r6, [r8, #8]
02025d60: ldrb     r0, [r8, #9]
02025d64: add      r2, r3, r2, lsl #8
02025d68: cmp      r1, #0x25
02025d6c: ldrlo    r3, [sb, #0x244]
02025d70: add      r2, r2, r6, lsl #16
02025d74: add      sl, r2, r0, lsl #24
02025d78: addlo    r2, sb, #0x164
02025d7c: ldrhs    r3, [sb, #0x40]
02025d80: ldr      r0, [sp, #0x114]
02025d84: addhs    r2, sb, #0x44
02025d88: str      r0, [sp]
02025d8c: ldrb     r1, [r8, #1]
02025d90: mov      r0, sb
02025d94: bl       #0x20225c8
02025d98: movs     r6, r0
02025d9c: beq      #0x2025dfc
02025da0: mov      r1, r7
02025da4: ldrb     r7, [r8, #0xa]
02025da8: ldrb     r3, [r8, #0xb]
02025dac: mov      r2, sl
02025db0: ldr      sl, [sb, #0x38]
02025db4: add      r3, r7, r3, lsl #8
02025db8: add      r3, r3, sl, asr #8
02025dbc: lsl      r3, r3, #0x10
02025dc0: asr      r7, r3, #0x10
02025dc4: ldrb     ip, [r8, #0xc]
02025dc8: ldrb     sl, [r8, #0xd]
02025dcc: ldr      fp, [sb, #0x3c]
02025dd0: ldr      r3, [sp, #0x118]
02025dd4: add      sl, ip, sl, lsl #8
02025dd8: add      sl, sl, fp, asr #8
02025ddc: lsl      sl, sl, #0x10
02025de0: asr      sl, sl, #0x10
02025de4: bl       #0x202216c
02025de8: cmp      r6, #0
02025dec: lslne    r0, r7, #8
02025df0: strne    r0, [r6, #0x38]
02025df4: lslne    r0, sl, #8
02025df8: strne    r0, [r6, #0x3c]
02025dfc: add      r8, r8, #0xe
02025e00: b        #0x202632c
```

## op 0x86  @ 0x2025e04
```
02025e04: ldrb     r0, [r8, #1]
02025e08: bl       #0x2028528
02025e0c: add      r8, r8, #2
02025e10: b        #0x202632c
```

## op 0x87  @ 0x2025e14
```
02025e14: ldr      r0, [sp, #0xc]
02025e18: cmp      r0, #0
02025e1c: bne      #0x2025ef8
02025e20: add      r7, r8, #2
02025e24: bl       #0x2020aa0
02025e28: cmp      r0, #0
02025e2c: beq      #0x2025e3c
02025e30: ldrb     r0, [sb, #0x1d]
02025e34: bl       #0x2020ab0
02025e38: mov      r7, r0
02025e3c: ldrb     r2, [r7]
02025e40: ldrb     r1, [r7, #1]
02025e44: add      r0, sb, #0xa8
02025e48: add      r1, r2, r1, lsl #8
02025e4c: lsl      r1, r1, #0x10
02025e50: lsr      r1, r1, #0x10
02025e54: bl       #0x2005fb4
02025e58: add      r0, r0, #0x10
02025e5c: lsl      r0, r0, #4
02025e60: lsr      r0, r0, #4
02025e64: bl       #0x2009120
02025e68: mov      r2, r0
02025e6c: ldrb     r3, [r7]
02025e70: ldrb     r1, [r7, #1]
02025e74: add      r0, sb, #0x44
02025e78: add      r1, r3, r1, lsl #8
02025e7c: lsl      r1, r1, #0x10
02025e80: lsr      r1, r1, #0x10
02025e84: bl       #0x2020c08
02025e88: movs     r6, r0
02025e8c: beq      #0x2025ec4
02025e90: add      r1, sb, #0x100
02025e94: ldrh     r1, [r1, #0xe]
02025e98: ldr      r3, [sb, #0x120]
02025e9c: add      r0, sb, #0x124
02025ea0: ldrh     sl, [r3]
02025ea4: lsl      r1, r1, #0x14
02025ea8: ldr      r3, [pc, #0x64c]   ; =0xfffff
02025eac: and      r1, r1, #0xff00000
02025eb0: orr      r1, r1, #0x70000000
02025eb4: and      r3, sl, r3
02025eb8: mov      r2, r6
02025ebc: orr      r1, r1, r3
02025ec0: bl       #0x2010fb4
02025ec4: add      r0, sb, #0x124
02025ec8: mov      r1, r5
02025ecc: bl       #0x2011d54
02025ed0: mov      r0, r6
02025ed4: bl       #0x2020f20
02025ed8: ldrb     r2, [r7, #2]
02025edc: ldrb     r1, [r7, #3]
02025ee0: add      r0, sb, #0x100
02025ee4: add      r8, r8, #6
02025ee8: add      r1, r2, r1, lsl #8
02025eec: strh     r1, [r0, #0xc]
02025ef0: str      r5, [sp, #0xc]
02025ef4: b        #0x202632c
02025ef8: bl       #0x2020aa0
02025efc: cmp      r0, #0
02025f00: beq      #0x2025f0c
02025f04: bl       #0x2020b94
02025f08: sub      r8, r8, #6
02025f0c: str      r5, [sp, #8]
02025f10: b        #0x202632c
```

## op 0x88  @ 0x2025f14
```
02025f14: ldr      r0, [sp, #0xc]
02025f18: cmp      r0, #0
02025f1c: bne      #0x2026018
02025f20: add      r6, r8, #2
02025f24: bl       #0x2020aa0
02025f28: cmp      r0, #0
02025f2c: beq      #0x2025f3c
02025f30: ldrb     r0, [sb, #0x1d]
02025f34: bl       #0x2020ab0
02025f38: mov      r6, r0
02025f3c: ldrb     r2, [r6]
02025f40: ldrb     r1, [r6, #1]
02025f44: add      r0, sb, #0xa8
02025f48: add      r1, r2, r1, lsl #8
02025f4c: lsl      r1, r1, #0x10
02025f50: lsr      r1, r1, #0x10
02025f54: bl       #0x2005fb4
02025f58: add      r0, r0, #0x10
02025f5c: lsl      r0, r0, #4
02025f60: lsr      r0, r0, #4
02025f64: bl       #0x2009120
02025f68: mov      r2, r0
02025f6c: ldrb     r3, [r6]
02025f70: ldrb     r1, [r6, #1]
02025f74: add      r0, sb, #0x44
02025f78: add      r1, r3, r1, lsl #8
02025f7c: lsl      r1, r1, #0x10
02025f80: lsr      r1, r1, #0x10
02025f84: bl       #0x2020c08
02025f88: movs     r7, r0
02025f8c: beq      #0x2025fe4
02025f90: ldr      r0, [sp, #0x11c]
02025f94: bl       #0x2009120
02025f98: str      r0, [sp, #0x18]
02025f9c: ldr      r1, [sp, #0x18]
02025fa0: mov      r0, r7
02025fa4: blx      #0x20abff0
02025fa8: mov      r0, r7
02025fac: bl       #0x20090b0
02025fb0: add      r1, sb, #0x100
02025fb4: ldrh     r3, [r1, #0xe]
02025fb8: ldr      r1, [sb, #0x120]
02025fbc: ldr      r2, [sp, #0x18]
02025fc0: lsl      r3, r3, #0x14
02025fc4: and      r3, r3, #0xff00000
02025fc8: orr      r7, r3, #0x70000000
02025fcc: ldrh     r3, [r1]
02025fd0: ldr      r1, [pc, #0x524]   ; =0xfffff
02025fd4: add      r0, sb, #0x124
02025fd8: and      r1, r3, r1
02025fdc: orr      r1, r7, r1
02025fe0: bl       #0x2010fb4
02025fe4: add      r0, sb, #0x124
02025fe8: mov      r1, r5
02025fec: bl       #0x2011d54
02025ff0: ldr      r0, [sp, #0x18]
02025ff4: bl       #0x2020f20
02025ff8: ldrb     r2, [r6, #2]
02025ffc: ldrb     r1, [r6, #3]
02026000: add      r0, sb, #0x100
02026004: add      r8, r8, #6
02026008: add      r1, r2, r1, lsl #8
0202600c: strh     r1, [r0, #0xc]
02026010: str      r5, [sp, #0xc]
02026014: b        #0x202632c
02026018: bl       #0x2020aa0
0202601c: cmp      r0, #0
02026020: beq      #0x202602c
02026024: bl       #0x2020b94
02026028: sub      r8, r8, #6
0202602c: str      r5, [sp, #8]
02026030: b        #0x202632c
```

## op 0x89  @ 0x2026034
```
02026034: add      r0, sb, #0x100
02026038: ldrh     r0, [r0, #0xe]
0202603c: add      r8, r8, #2
02026040: cmp      r0, #0x25
02026044: ldrlo    r0, [sb, #0x250]
02026048: orrlo    r0, r0, #0x10000
0202604c: strlo    r0, [sb, #0x250]
02026050: b        #0x202632c
```

## op 0x8a  @ 0x2026054
```
02026054: ldrb     r0, [r8, #2]
02026058: ldr      r3, [sb, #0xfc]
0202605c: ldrb     r1, [r8, #3]
02026060: add      r0, r3, r0, lsl #5
02026064: ldrb     r2, [r8, #5]
02026068: asr      r3, r1, #3
0202606c: ldrb     r1, [r8, #4]
02026070: asr      r6, r2, #3
02026074: ldr      r2, [sp, #0xa4]
02026078: asr      r1, r1, #3
0202607c: orr      r1, r3, r1, lsl #5
02026080: orr      r1, r1, r6, lsl #10
02026084: lsl      r1, r1, #0x10
02026088: lsr      r1, r1, #0x10
0202608c: bl       #0x20015c0
02026090: mov      r1, r0
02026094: add      r0, sb, #0x100
02026098: ldrb     r3, [r8, #2]
0202609c: ldrh     r0, [r0, #0xa]
020260a0: ldr      r2, [sp, #0x120]
020260a4: add      r0, r0, r3, lsl #5
020260a8: lsl      r0, r0, #0x10
020260ac: lsr      r0, r0, #0x10
020260b0: bl       #0x2010ae0
020260b4: add      r8, r8, #6
020260b8: b        #0x202632c
```

## op 0x8b  @ 0x20260bc
```
020260bc: ldrb     r0, [r8, #2]
020260c0: ldr      r3, [sb, #0xfc]
020260c4: ldrb     r1, [r8, #3]
020260c8: add      r0, r3, r0, lsl #5
020260cc: ldrb     r2, [r8, #5]
020260d0: asr      r3, r1, #3
020260d4: ldrb     r1, [r8, #4]
020260d8: asr      r6, r2, #3
020260dc: ldr      r2, [sp, #0xa4]
020260e0: asr      r1, r1, #3
020260e4: orr      r1, r3, r1, lsl #5
020260e8: orr      r1, r1, r6, lsl #10
020260ec: lsl      r1, r1, #0x10
020260f0: lsr      r1, r1, #0x10
020260f4: bl       #0x20014d8
020260f8: mov      r1, r0
020260fc: add      r0, sb, #0x100
02026100: ldrb     r3, [r8, #2]
02026104: ldrh     r0, [r0, #0xa]
02026108: ldr      r2, [sp, #0x120]
0202610c: add      r0, r0, r3, lsl #5
02026110: lsl      r0, r0, #0x10
02026114: lsr      r0, r0, #0x10
02026118: bl       #0x2010ae0
0202611c: add      r8, r8, #6
02026120: b        #0x202632c
```

## op 0x8c  @ 0x2026124
```
02026124: add      r0, sb, #0x100
02026128: ldrh     r0, [r0, #0xe]
0202612c: cmp      r0, #0x25
02026130: bhs      #0x2026158
02026134: ldr      r0, [sb, #0x250]
02026138: ands     r0, r0, #0x2000
0202613c: bne      #0x202614c
02026140: mov      r0, sb
02026144: ldrb     r1, [r8, #1]
02026148: bl       #0x2029e3c
0202614c: ldr      r0, [sb, #0x250]
02026150: bic      r0, r0, #0x2000
02026154: str      r0, [sb, #0x250]
02026158: add      r8, r8, #2
0202615c: b        #0x202632c
```

## op 0x8d  @ 0x2026160
```
02026160: ldrb     r0, [sb, #0x1a]
02026164: bl       #0x2027bb4
02026168: add      r0, r0, #0x800
0202616c: ldrh     r7, [r0, #0xe0]
02026170: mov      r6, r5
02026174: cmp      r7, #3
02026178: blo      #0x2026228
0202617c: ldrb     r0, [r8, #1]
02026180: cmp      r0, #0
02026184: beq      #0x202619c
02026188: cmp      r0, #1
0202618c: beq      #0x20261ac
02026190: cmp      r0, #2
02026194: beq      #0x20261d8
02026198: b        #0x2026200
0202619c: add      r0, sb, #0x124
020261a0: mov      r1, r5
020261a4: bl       #0x2011d54
020261a8: b        #0x2026200
020261ac: cmp      r7, #0xa
020261b0: blo      #0x20261c4
020261b4: add      r0, sb, #0x124
020261b8: mov      r1, r5
020261bc: bl       #0x2011d54
020261c0: b        #0x20261d0
020261c4: ldr      r1, [sp, #0x124]
020261c8: add      r0, sb, #0x124
020261cc: bl       #0x2011d54
020261d0: ldr      r6, [sp, #0x128]
020261d4: b        #0x2026200
020261d8: cmp      r7, #0x64
020261dc: blo      #0x20261f0
020261e0: add      r0, sb, #0x124
020261e4: mov      r1, r5
020261e8: bl       #0x2011d54
020261ec: b        #0x20261fc
020261f0: ldr      r1, [sp, #0x12c]
020261f4: add      r0, sb, #0x124
020261f8: bl       #0x2011d54
020261fc: ldr      r6, [sp, #0x130]
02026200: mov      r0, r7
02026204: mov      r1, r6
02026208: bl       #0x20b603c
0202620c: ldr      r1, [pc, #0x2ec]   ; =0xcccccccd
02026210: umull    r1, r2, r0, r1
02026214: ldr      r1, [pc, #0x2e8]   ; =0xa
02026218: lsr      r2, r2, #3
0202621c: umull    r2, r3, r1, r2
02026220: sub      r2, r0, r2
02026224: strb     r2, [sb, #0x1d]
02026228: add      r8, r8, #2
0202622c: b        #0x202632c
```

## op 0x8e  @ 0x2026230
```
02026230: ldrb     r0, [sb, #0x1a]
02026234: bl       #0x2027c00
02026238: ldrb     r0, [r0, #0x257]
0202623c: cmp      r0, #0
02026240: addeq    r8, r8, #6
02026244: beq      #0x202632c
02026248: ldrb     r3, [r8, #2]
0202624c: ldrb     r2, [r8, #3]
02026250: ldrb     r6, [r8, #4]
02026254: ldrb     r7, [r8, #5]
02026258: add      r2, r3, r2, lsl #8
0202625c: add      r2, r2, r6, lsl #16
02026260: ldr      r0, [sb, #0x44]
02026264: add      r2, r2, r7, lsl #24
02026268: add      r0, r0, r2
0202626c: str      r0, [sb, #0x100]
02026270: ldr      r0, [sb, #0x100]
02026274: add      r1, sb, #0x100
02026278: str      r0, [sb, #0x104]
0202627c: ldr      r0, [sp, #0x134]
02026280: strh     r0, [r1, #0xc]
02026284: ldr      r8, [sb, #0x104]
02026288: b        #0x202632c
```

## op 0x8f  @ 0x202628c
```
0202628c: ldrb     r0, [sb, #0x1a]
02026290: bl       #0x2027c00
02026294: bl       #0x2029804
02026298: add      r8, r8, #2
0202629c: b        #0x202632c
```

## op 0x90  @ 0x20262a0
```
020262a0: ldrh     r0, [sb, #0xe]
020262a4: ands     r0, r0, #0x20
020262a8: strne    r5, [sp, #8]
020262ac: addeq    r8, r8, #2
020262b0: b        #0x202632c
```

## op 0x91  @ 0x20262b4
```
020262b4: ldrb     r0, [sb, #0x1a]
020262b8: bl       #0x2027bd0
020262bc: bl       #0x2029804
020262c0: add      r8, r8, #2
020262c4: b        #0x202632c
```

## op 0x92  @ 0x20262c8
```
020262c8: ldrb     r0, [sb, #0x1a]
020262cc: cmp      r0, #0
020262d0: beq      #0x2026328
020262d4: bl       #0x2001ea4
020262d8: ldrb     r1, [r8, #1]
020262dc: cmp      r1, r0
020262e0: bne      #0x2026328
020262e4: ldrb     r3, [r8, #2]
020262e8: ldrb     r2, [r8, #3]
020262ec: ldrb     r6, [r8, #4]
020262f0: ldrb     r7, [r8, #5]
020262f4: add      r2, r3, r2, lsl #8
020262f8: add      r2, r2, r6, lsl #16
020262fc: ldr      r0, [sb, #0x44]
02026300: add      r2, r2, r7, lsl #24
02026304: add      r0, r0, r2
02026308: str      r0, [sb, #0x100]
0202630c: ldr      r0, [sb, #0x100]
02026310: add      r1, sb, #0x100
02026314: str      r0, [sb, #0x104]
02026318: ldr      r0, [sp, #0x138]
0202631c: strh     r0, [r1, #0xc]
02026320: ldr      r8, [sb, #0x104]
02026324: b        #0x202632c
02026328: add      r8, r8, #6
```