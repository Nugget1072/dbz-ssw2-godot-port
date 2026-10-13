class_name DSBios7
extends RefCounted
## ARM7 BIOS sound tables used by the sound driver (SWI 1Bh GetPitchTable, SWI 1Ch GetVolumeTable).
## The pitch table is 0x10000 * (2^(i/768) - 1) rounded (checked against melonDS's FreeBIOS: all 768 entries).
## The volume table (724 entries, index = decibels * 10 + 723; ranges below -24/-12/-6 dB are stored 16x/4x/2x
## larger for the driver's channel shift) is the one in melonDS's FreeBIOS, which the reference captures use:
## FreeBIOS: Copyright (c) 2013, Gilead Kutnick. All rights reserved. Redistribution and use in source and binary
## forms, with or without modification, are permitted provided that the copyright notice, the conditions and
## the disclaimer are retained (2-clause BSD licence, full text in melonDS src/FreeBIOS.cpp).

static var _vol := PackedByteArray()


static func pitch(i: int) -> int:
	i = clampi(i, 0, 767)
	return int(round((pow(2.0, i / 768.0) - 1.0) * 65536.0))


static func volume(i: int) -> int:
	if _vol.is_empty():
		_vol = Marshalls.base64_to_raw(VOLUME_B64)
	return _vol[clampi(i, 0, 723)]


const VOLUME_B64 := "AAEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBQUFBQUFBQUFBQUFBQUFBQUGBgYGBgYGBgYGBgYGBgYHBwcHBwcHBwcHBwcICAgICAgICAgICAkJCQkJCQkJCQkKCgoKCgoKCgsLCwsLCwsLDAwMDAwMDAwNDQ0NDQ0ODg4ODg4ODw8PDw8QEBAQEBARERERERISEhISExMTExQUFBQUFRUVFRYWFhYXFxcYGBgYGRkZGRoaGhsbGxwcHB0dHR4eHh8fHyAgICEhIiIiIyMkJCQlJSYmJycnKCgpKSoqKyssLC0tLi4vLzAxMTIyMzM0NTU2Njc4ODk6Ojs8PD0+Pz9AQUJCQ0RFRUZHSElKSktMTU5PUFFSUlNUVVZXWFlaW11eX2BhYmNkZWdoaWprbW5vcXJzdXZ3eXp7fX5/ICEhISIiIyMjJCQlJSYmJicnKCgpKSoqKyssLC0tLi4vLzAwMTEyMzM0NDU2Njc3ODk5Ojs7PD0+Pj9AQEFCQ0NERUZHR0hJSktMTU1OT1BRUlNUVVZXWFlaW1xdXl9gYmNkZWZnaWprbG1vcHFzdHV3eHl7fH5+QEFCQ0NERUZHR0hJSktMTE1OT1BRUlNUVVZXWFlaW1xdXl9gYWJkZWZnaGlrbG1ucHFydHV2eHl7fH1+QEFCQkNERUZGR0hJSktLTE1OT1BRUlNUVVZXWFlaW1xdXl9gYWJjZWZnaGlqbG1ub3Fyc3V2d3l6fH1+fw=="
