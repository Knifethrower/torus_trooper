/*
 * Math functions in hardware floating point, for the PortMaster port.
 *
 * std.math works in D's real type. On x86 that is the FPU's 80-bit format; on aarch64 it is a
 * 128-bit format computed in software, and the game's sin, cos and "* 180 / PI" spent most of
 * the CPU time of a handheld there. The game's values are float, so the names it uses from
 * std.math are provided here as float (and double) functions of the C library.
 */
module abagames.util.math;

private static import core.stdc.math;

public enum float PI = 3.14159265358979323846f;

public float sin(float x) { return core.stdc.math.sinf(x); }
public float cos(float x) { return core.stdc.math.cosf(x); }
public float atan2(float y, float x) { return core.stdc.math.atan2f(y, x); }
public float sqrt(float x) { return core.stdc.math.sqrtf(x); }
public float fabs(float x) { return core.stdc.math.fabsf(x); }

public double sin(double x) { return core.stdc.math.sin(x); }
public double cos(double x) { return core.stdc.math.cos(x); }
public double atan2(double y, double x) { return core.stdc.math.atan2(y, x); }
public double sqrt(double x) { return core.stdc.math.sqrt(x); }
public double fabs(double x) { return core.stdc.math.fabs(x); }

// By the bits: the build uses -ffast-math, which may drop a comparison like x != x.
public bool isNaN(float x) { return (*cast(uint*) &x & 0x7FFFFFFF) > 0x7F800000; }
public bool isNaN(double x) { return (*cast(ulong*) &x & 0x7FFFFFFFFFFFFFFF) > 0x7FF0000000000000; }
