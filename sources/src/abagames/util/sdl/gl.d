/*
 * OpenGL 1.x style drawing on OpenGL ES 2.0, written for the PortMaster port.
 *
 * The game was written for immediate-mode OpenGL 1.x: glBegin/glEnd, the matrix stacks and
 * display lists. This module keeps that interface, so the drawing code stays as Kenta Cho wrote
 * it, and implements it on GLES 2.
 *
 * Draw calls and buffer updates are what is expensive on the handhelds' GPU drivers (on a Mali
 * blob about 0.1 ms per call, and far more for every update of a buffer that is in use), so
 * nothing is drawn when the game asks for it. Everything is turned into triangles on the CPU
 * and appended to one array, in the order the game draws it, and the array is drawn with a
 * single call at the end of the frame:
 *  - Positions are transformed to clip space with the GL_MODELVIEW and GL_PROJECTION stacks
 *    kept here (GL 1.x formulas), so matrix changes never split the array.
 *  - Lines become quads one pixel wide (glLineWidth pixels): the line is clipped at the near
 *    plane and widened along its minor axis in window space, which covers the same pixels as
 *    GL's line rule apart from single end pixels.
 *  - Colors are premultiplied by the blending in force when the vertex is drawn and the one
 *    blend function (GL_ONE, GL_ONE_MINUS_SRC_ALPHA) serves all three cases the game uses:
 *    blending off (rgb, 1), GL_SRC_ALPHA/GL_ONE_MINUS_SRC_ALPHA (rgb * a, a) and additive
 *    GL_SRC_ALPHA/GL_ONE (rgb * a, 0). So blending changes never split the array either.
 *  - GL_CULL_FACE is applied on the CPU (counterclockwise is the front, as in GL).
 *  - A display list is recorded at creation: matrix operations inside the list are applied to
 *    the recorded vertices, colors are recorded per vertex, and vertices recorded before the
 *    list's first glColor take the color that is current when the list is called, as in GL.
 *  - Textured primitives (the title logo, the luminous effect) are drawn on their own, after
 *    the array so far. A viewport change, glClear and glCopyTexImage2D draw the array first.
 * GL_LINE_SMOOTH, GL_LIGHTING and GL_COLOR_MATERIAL do not exist in GLES and are ignored, as
 * gl4es ignored them before. Unsupported uses throw, so a mistake shows up in a PC test.
 */
module abagames.util.sdl.gl;

private import abagames.util.math;
private import std.conv;
private import std.string;
private import core.stdc.stdlib : getenv;
private import bindbc.sdl;
private import abagames.util.logger;
static import gles2;
public import gles2 : GLenum, GLboolean, GLbitfield, GLint, GLsizei, GLuint, GLfloat, GLclampf,
  GLvoid, GL_NO_ERROR, GL_ZERO, GL_ONE, GL_LINES, GL_LINE_LOOP, GL_LINE_STRIP, GL_TRIANGLES,
  GL_TRIANGLE_STRIP, GL_TRIANGLE_FAN, GL_DEPTH_BUFFER_BIT, GL_COLOR_BUFFER_BIT, GL_SRC_ALPHA,
  GL_ONE_MINUS_SRC_ALPHA, GL_CULL_FACE, GL_DEPTH_TEST, GL_BLEND, GL_TEXTURE_2D, GL_UNSIGNED_BYTE,
  GL_FLOAT, GL_RGB, GL_RGBA, GL_LINEAR, GL_TEXTURE_MAG_FILTER, GL_TEXTURE_MIN_FILTER;

alias GLdouble = double;

// OpenGL 1.x names that GLES 2 does not have.
enum : GLenum {
  GL_QUADS = 0x0007,
  GL_LINE_SMOOTH = 0x0B20,
  GL_LIGHTING = 0x0B50,
  GL_COLOR_MATERIAL = 0x0B57,
  GL_COMPILE = 0x1300,
  GL_MODELVIEW = 0x1700,
  GL_PROJECTION = 0x1701,
}

// ---------------------------------------------------------------------------------------------
// Matrices: column-major float[16] as in GL, m[col * 4 + row].

private alias Mat4 = float[16];

private void identity(ref Mat4 m) {
  m[] = 0;
  m[0] = m[5] = m[10] = m[15] = 1;
}

private bool isIdentity(ref Mat4 m) {
  for (int i = 0; i < 16; i++)
    if (m[i] != ((i % 5 == 0) ? 1.0f : 0.0f))
      return false;
  return true;
}

// m = m * n (GL multiplies new transformations onto the right).
private void multiply(ref Mat4 m, ref Mat4 n) {
  Mat4 r;
  for (int c = 0; c < 4; c++)
    for (int row = 0; row < 4; row++)
      r[c * 4 + row] = m[row] * n[c * 4] + m[4 + row] * n[c * 4 + 1] +
                       m[8 + row] * n[c * 4 + 2] + m[12 + row] * n[c * 4 + 3];
  m = r;
}

private void translate(ref Mat4 m, float x, float y, float z) {
  for (int row = 0; row < 4; row++)
    m[12 + row] += m[row] * x + m[4 + row] * y + m[8 + row] * z;
}

private void scale(ref Mat4 m, float x, float y, float z) {
  for (int row = 0; row < 4; row++) {
    m[row] *= x;
    m[4 + row] *= y;
    m[8 + row] *= z;
  }
}

// glRotatef: the rotation matrix of the GL specification about the normalized axis.
private void rotate(ref Mat4 m, float angle, float x, float y, float z) {
  float len = sqrt(x * x + y * y + z * z);
  if (len == 0)
    return;
  x /= len;
  y /= len;
  z /= len;
  float a = angle * cast(float) (PI / 180);
  float c = cos(a), s = sin(a), t = 1 - c;
  Mat4 r;
  identity(r);
  r[0] = x * x * t + c;
  r[1] = y * x * t + z * s;
  r[2] = x * z * t - y * s;
  r[4] = x * y * t - z * s;
  r[5] = y * y * t + c;
  r[6] = y * z * t + x * s;
  r[8] = x * z * t + y * s;
  r[9] = y * z * t - x * s;
  r[10] = z * z * t + c;
  multiply(m, r);
}

private void frustum(ref Mat4 m, float l, float r, float b, float t, float n, float f) {
  Mat4 p;
  p[] = 0;
  p[0] = 2 * n / (r - l);
  p[5] = 2 * n / (t - b);
  p[8] = (r + l) / (r - l);
  p[9] = (t + b) / (t - b);
  p[10] = -(f + n) / (f - n);
  p[11] = -1;
  p[14] = -2 * f * n / (f - n);
  multiply(m, p);
}

private void ortho(ref Mat4 m, float l, float r, float b, float t, float n, float f) {
  Mat4 p;
  identity(p);
  p[0] = 2 / (r - l);
  p[5] = 2 / (t - b);
  p[10] = -2 / (f - n);
  p[12] = -(r + l) / (r - l);
  p[13] = -(t + b) / (t - b);
  p[14] = -(f + n) / (f - n);
  multiply(m, p);
}

// Display list recording: a point through the list's own matrix.
private void transformPoint(ref Mat4 m, ref float[3] p) {
  float x = p[0], y = p[1], z = p[2];
  p[0] = m[0] * x + m[4] * y + m[8] * z + m[12];
  p[1] = m[1] * x + m[5] * y + m[9] * z + m[13];
  p[2] = m[2] * x + m[6] * y + m[10] * z + m[14];
}

// ---------------------------------------------------------------------------------------------
// Renderer state.

// A vertex as the game specifies it.
private struct Vtx {
  float[3] p;
  float[4] c;
  float[2] t;
}

// A vertex as it is drawn: clip-space position, premultiplied color.
private struct Out {
  float[4] p;
  float[4] c;
}

private struct OutTex {
  float[4] p;
  float[4] c;
  float[2] t;
}

private struct Chunk {
  GLenum mode;      // GL_LINES or GL_TRIANGLES
  int first, count; // vertices in DList.data
}

private final class DList {
  Vtx[] data;
  bool[] inherit;      // vertex takes the color current at glCallList
  Chunk[] chunks;      // in recording order
  bool hasFinalColor;
  float[4] finalColor;
  bool hasPostMatrix;
  Mat4 postMatrix;
}

private __gshared {
  Mat4[32] mvStack;
  int mvDepth;
  Mat4[4] pjStack;
  int pjDepth;
  GLenum matrixMode = GL_MODELVIEW;
  Mat4 mvp;
  bool mvpDirty = true;
  float[4] curColor = [1, 1, 1, 1];
  float[2] curTex = [0, 0];
  bool texEnabled, blendEnabled, cullEnabled;
  GLenum blendSrc = GL_ONE, blendDst = GL_ZERO;
  float lineWidth = 1;
  float viewW = 640, viewH = 480;

  // glBegin/glEnd in progress.
  bool inBegin;
  GLenum beginMode;
  int beginCount;
  Vtx first, prev, quad0, quad1, quad2;
  bool firstInh, prevInh, quad0Inh, quad1Inh, quad2Inh;
  Vtx[] prim;
  bool[] primInh;
  int primN;

  // Display lists.
  DList[] lists;       // index = list name, 0 unused
  DList recList;
  Mat4 recMat;
  Mat4[8] recStack;
  int recDepth;
  bool recColorSet;

  // The frame's triangles.
  Out[] outBuf;
  int outN;
  OutTex[] texBuf;

  // Shader program.
  GLuint program;
  GLint aPos, aColor, aTex, uTexture;
  int texUniform = -1;
  bool debugLog;          // TT_GLDEBUG=1: log the draws (PC tests)
}

/// Vertices drawn since the start (for the test builds' log).
public __gshared long statVertices;

private bool recording() {
  return recList !is null;
}

private ref Mat4 top() {
  return matrixMode == GL_PROJECTION ? pjStack[pjDepth] : mvStack[mvDepth];
}

private void check(GLuint obj, bool shader) {
  GLint ok;
  if (shader)
    gles2.glGetShaderiv(obj, gles2.GL_COMPILE_STATUS, &ok);
  else
    gles2.glGetProgramiv(obj, gles2.GL_LINK_STATUS, &ok);
  if (ok)
    return;
  char[2048] log;
  GLsizei len;
  if (shader)
    gles2.glGetShaderInfoLog(obj, log.length, &len, log.ptr);
  else
    gles2.glGetProgramInfoLog(obj, log.length, &len, log.ptr);
  throw new Exception((shader ? "Shader compile error: " : "Shader link error: ") ~ log[0 .. len].idup);
}

private GLuint compile(GLenum type, string src) {
  GLuint s = gles2.glCreateShader(type);
  const(char)* p = src.ptr;
  GLint len = cast(GLint) src.length;
  gles2.glShaderSource(s, 1, &p, &len);
  gles2.glCompileShader(s);
  check(s, true);
  return s;
}

private enum VERTEX_SHADER = q{
  attribute vec4 aPos;
  attribute vec4 aColor;
  attribute vec2 aTex;
  varying vec4 vColor;
  varying vec2 vTex;
  void main() {
    gl_Position = aPos;
    vColor = aColor;
    vTex = aTex;
  }
};

private enum FRAGMENT_SHADER = q{
  precision mediump float;
  uniform sampler2D uSampler;
  uniform int uTexture;
  varying vec4 vColor;
  varying vec2 vTex;
  void main() {
    vec4 c = vColor;
    if (uTexture != 0)
      c *= texture2D(uSampler, vTex);
    gl_FragColor = c;
  }
};

/**
 * Call once after SDL_GL_CreateContext.
 */
public void initGL() {
  gles2.loadGLES2();
  debugLog = getenv("TT_GLDEBUG") !is null;
  Logger.info("GL_VENDOR: " ~ to!string(cast(const(char)*) gles2.glGetString(gles2.GL_VENDOR)));
  Logger.info("GL_RENDERER: " ~ to!string(cast(const(char)*) gles2.glGetString(gles2.GL_RENDERER)));
  Logger.info("GL_VERSION: " ~ to!string(cast(const(char)*) gles2.glGetString(gles2.GL_VERSION)));
  GLuint vs = compile(gles2.GL_VERTEX_SHADER, VERTEX_SHADER);
  GLuint fs = compile(gles2.GL_FRAGMENT_SHADER, FRAGMENT_SHADER);
  program = gles2.glCreateProgram();
  gles2.glAttachShader(program, vs);
  gles2.glAttachShader(program, fs);
  gles2.glLinkProgram(program);
  check(program, false);
  gles2.glDeleteShader(vs);
  gles2.glDeleteShader(fs);
  gles2.glUseProgram(program);
  aPos = gles2.glGetAttribLocation(program, "aPos");
  aColor = gles2.glGetAttribLocation(program, "aColor");
  aTex = gles2.glGetAttribLocation(program, "aTex");
  uTexture = gles2.glGetUniformLocation(program, "uTexture");
  gles2.glUniform1i(gles2.glGetUniformLocation(program, "uSampler"), 0);
  gles2.glActiveTexture(gles2.GL_TEXTURE0);
  gles2.glBindBuffer(gles2.GL_ARRAY_BUFFER, 0);
  gles2.glEnableVertexAttribArray(aPos);
  gles2.glEnableVertexAttribArray(aColor);
  gles2.glDisableVertexAttribArray(aTex);
  gles2.glVertexAttrib4f(aTex, 0, 0, 0, 1);
  // The one blending state: premultiplied colors (see the top of the file).
  gles2.glEnable(GL_BLEND);
  gles2.glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
  gles2.glDisable(GL_CULL_FACE);
  gles2.glDisable(GL_DEPTH_TEST);
  texUniform = -1;
  setTextureUniform(false);
  mvDepth = pjDepth = 0;
  identity(mvStack[0]);
  identity(pjStack[0]);
  matrixMode = GL_MODELVIEW;
  mvpDirty = true;
  curColor[] = 1;
  curTex[] = 0;
  texEnabled = blendEnabled = cullEnabled = false;
  blendSrc = GL_ONE;
  blendDst = GL_ZERO;
  lineWidth = 1;
  lists.length = 1;
  prim.length = 64;
  primInh.length = 64;
  outBuf.length = 65536;
  outN = 0;
  gles2.glGetError();
}

public void closeGL() {
  lists = null;
  if (program) {
    gles2.glDeleteProgram(program);
    program = 0;
  }
}

private void setTextureUniform(bool on) {
  int v = on ? 1 : 0;
  if (v != texUniform) {
    gles2.glUniform1i(uTexture, v);
    texUniform = v;
  }
}

private void notInList(string name) {
  if (recording())
    throw new Exception(name ~ " is not supported inside a display list");
}

// ---------------------------------------------------------------------------------------------
// Vertices to triangles.

private void updateMVP() {
  if (!mvpDirty)
    return;
  mvp = pjStack[pjDepth];
  multiply(mvp, mvStack[mvDepth]);
  mvpDirty = false;
}

// These run for every vertex of every frame on the device's CPU: inlined, results computed
// before they are stored (the compiler cannot know that o is not the matrix), no default
// initialisation of locals.
pragma(inline, true)
private void toClip(ref const(float[3]) p, ref float[4] o) {
  const float x = p[0], y = p[1], z = p[2];
  const float r0 = mvp[0] * x + mvp[4] * y + mvp[8] * z + mvp[12];
  const float r1 = mvp[1] * x + mvp[5] * y + mvp[9] * z + mvp[13];
  const float r2 = mvp[2] * x + mvp[6] * y + mvp[10] * z + mvp[14];
  const float r3 = mvp[3] * x + mvp[7] * y + mvp[11] * z + mvp[15];
  o[0] = r0;
  o[1] = r1;
  o[2] = r2;
  o[3] = r3;
}

// The sides of the view volume a clip-space point is beyond, one bit each; gx and gy widen the
// volume sideways (1 = not at all). A primitive whose vertices are all beyond the same side
// cannot be seen, and the GPU would clip it away: it is left out of the frame's array.
pragma(inline, true)
private uint sidesBeyond(ref const(float[4]) p, float gx, float gy) {
  const float wx = p[3] * gx, wy = p[3] * gy, w = p[3];
  return (p[0] < -wx ? 1 : 0) | (p[0] > wx ? 2 : 0) | (p[1] < -wy ? 4 : 0) | (p[1] > wy ? 8 : 0) |
         (p[2] < -w ? 16 : 0) | (p[2] > w ? 32 : 0);
}

// 0: blending off, 1: GL_SRC_ALPHA/GL_ONE_MINUS_SRC_ALPHA, 2: GL_SRC_ALPHA/GL_ONE.
private int blendMode() {
  if (!blendEnabled)
    return 0;
  if (blendSrc == GL_SRC_ALPHA && blendDst == GL_ONE_MINUS_SRC_ALPHA)
    return 1;
  if (blendSrc == GL_SRC_ALPHA && blendDst == GL_ONE)
    return 2;
  throw new Exception("unsupported glBlendFunc " ~ to!string(blendSrc) ~ " " ~ to!string(blendDst));
}

pragma(inline, true)
private void premultiply(int mode, ref const(float[4]) c, ref float[4] o) {
  if (mode == 0) {
    o[0] = c[0];
    o[1] = c[1];
    o[2] = c[2];
    o[3] = 1;
  } else {
    float a = c[3];
    o[0] = c[0] * a;
    o[1] = c[1] * a;
    o[2] = c[2] * a;
    o[3] = mode == 1 ? a : 0;
  }
}

private void reserveOut(int extra) {
  if (outN + extra > outBuf.length) {
    size_t len = outBuf.length;
    while (len < outN + extra)
      len *= 2;
    outBuf.length = len;
  }
}

// GL culls what is not counterclockwise in window space; the sign of this determinant of the
// clip coordinates is the sign of that area, also for triangles that cross the near plane.
private bool backFacing(ref const(float[4]) a, ref const(float[4]) b, ref const(float[4]) c) {
  float det = a[0] * (b[1] * c[3] - b[3] * c[1]) -
              a[1] * (b[0] * c[3] - b[3] * c[0]) +
              a[3] * (b[0] * c[1] - b[1] * c[0]);
  return det <= 0;
}

private void addTriangle(int mode, ref const(float[3]) p0, ref const(float[4]) c0,
                         ref const(float[3]) p1, ref const(float[4]) c1,
                         ref const(float[3]) p2, ref const(float[4]) c2) {
  reserveOut(3);
  Out* o = &outBuf[outN];
  toClip(p0, o[0].p);
  toClip(p1, o[1].p);
  toClip(p2, o[2].p);
  if (sidesBeyond(o[0].p, 1, 1) & sidesBeyond(o[1].p, 1, 1) & sidesBeyond(o[2].p, 1, 1))
    return;
  if (cullEnabled && backFacing(o[0].p, o[1].p, o[2].p))
    return;
  premultiply(mode, c0, o[0].c);
  premultiply(mode, c1, o[1].c);
  premultiply(mode, c2, o[2].c);
  outN += 3;
}

// A line as two triangles: clipped at the near plane, then widened by lineWidth pixels along
// its minor axis in window space, which is how GL describes a line of that width.
private void addLine(int mode, ref const(float[3]) p0, ref const(float[4]) c0,
                     ref const(float[3]) p1, ref const(float[4]) c1) {
  float[4] a = void, b = void, ca = void, cb = void;
  toClip(p0, a);
  toClip(p1, b);
  // The quad reaches lineWidth / 2 pixels beyond the line; twice that is allowed for.
  const float gx = 1 + 2 * lineWidth / viewW, gy = 1 + 2 * lineWidth / viewH;
  if (sidesBeyond(a, gx, gy) & sidesBeyond(b, gx, gy))
    return;
  premultiply(mode, c0, ca);
  premultiply(mode, c1, cb);
  float da = a[2] + a[3], db = b[2] + b[3];
  if (da < 0 && db < 0)
    return;
  if (da < 0 || db < 0) {
    float t = da / (da - db);
    float[4] m = void, cm = void;
    for (int i = 0; i < 4; i++) {
      m[i] = a[i] + (b[i] - a[i]) * t;
      cm[i] = ca[i] + (cb[i] - ca[i]) * t;
    }
    if (da < 0) {
      a = m;
      ca = cm;
    } else {
      b = m;
      cb = cm;
    }
  }
  if (a[3] <= 0 || b[3] <= 0)
    return;
  float ax = a[0] / a[3], ay = a[1] / a[3];
  float bx = b[0] / b[3], by = b[1] / b[3];
  float dx = (bx - ax) * viewW, dy = (by - ay) * viewH;
  if (dx == 0 && dy == 0)
    return;
  float ox = 0, oy = 0;
  if (fabs(dx) >= fabs(dy))
    oy = lineWidth / viewH;
  else
    ox = lineWidth / viewW;
  reserveOut(6);
  Out* o = &outBuf[outN];
  // a-, a+, b+ and a-, b+, b-
  setOut(o[0], a, ca, -ox, -oy);
  setOut(o[1], a, ca, ox, oy);
  setOut(o[2], b, cb, ox, oy);
  o[3] = o[0];
  o[4] = o[2];
  setOut(o[5], b, cb, -ox, -oy);
  outN += 6;
}

pragma(inline, true)
private void setOut(ref Out o, ref const(float[4]) p, ref const(float[4]) c, float ox, float oy) {
  o.p[0] = p[0] + ox * p[3];
  o.p[1] = p[1] + oy * p[3];
  o.p[2] = p[2];
  o.p[3] = p[3];
  o.c[0] = c[0];
  o.c[1] = c[1];
  o.c[2] = c[2];
  o.c[3] = c[3];
}

// Vertices of GL_LINES or GL_TRIANGLES as the game gave them, appended to the frame's array.
private void addVertices(GLenum mode, const(Vtx)* v, const(bool)* inherit, int n) {
  updateMVP();
  int bm = blendMode();
  if (mode == GL_LINES) {
    for (int i = 0; i + 1 < n; i += 2)
      addLine(bm, v[i].p, inherit && inherit[i] ? curColor : v[i].c,
              v[i + 1].p, inherit && inherit[i + 1] ? curColor : v[i + 1].c);
  } else {
    for (int i = 0; i + 2 < n; i += 3)
      addTriangle(bm, v[i].p, inherit && inherit[i] ? curColor : v[i].c,
                  v[i + 1].p, inherit && inherit[i + 1] ? curColor : v[i + 1].c,
                  v[i + 2].p, inherit && inherit[i + 2] ? curColor : v[i + 2].c);
  }
}

/**
 * Draws the triangles collected so far. Called before the buffer swap and before everything
 * that depends on what is on the screen or changes where it goes.
 */
public void flushGL() {
  if (outN == 0)
    return;
  if (debugLog)
    Logger.info("gl: draw " ~ to!string(outN) ~ " vertices");
  statVertices += outN;
  setTextureUniform(false);
  gles2.glDisableVertexAttribArray(aTex);
  gles2.glVertexAttribPointer(aPos, 4, GL_FLOAT, 0, Out.sizeof, outBuf[0].p.ptr);
  gles2.glVertexAttribPointer(aColor, 4, GL_FLOAT, 0, Out.sizeof, outBuf[0].c.ptr);
  gles2.glDrawArrays(GL_TRIANGLES, 0, outN);
  outN = 0;
}

// A textured glBegin/glEnd block: drawn at once, after what came before it.
private void drawTextured(GLenum mode) {
  if (mode != GL_TRIANGLES)
    throw new Exception("textured lines are not supported");
  flushGL();
  updateMVP();
  int bm = blendMode();
  if (texBuf.length < primN)
    texBuf.length = primN;
  int n = 0;
  for (int i = 0; i + 2 < primN; i += 3) {
    for (int k = 0; k < 3; k++) {
      toClip(prim[i + k].p, texBuf[n + k].p);
      premultiply(bm, prim[i + k].c, texBuf[n + k].c);
      texBuf[n + k].t = prim[i + k].t;
    }
    if (cullEnabled && backFacing(texBuf[n].p, texBuf[n + 1].p, texBuf[n + 2].p))
      continue;
    n += 3;
  }
  if (n == 0)
    return;
  setTextureUniform(true);
  gles2.glEnableVertexAttribArray(aTex);
  gles2.glVertexAttribPointer(aPos, 4, GL_FLOAT, 0, OutTex.sizeof, texBuf[0].p.ptr);
  gles2.glVertexAttribPointer(aColor, 4, GL_FLOAT, 0, OutTex.sizeof, texBuf[0].c.ptr);
  gles2.glVertexAttribPointer(aTex, 2, GL_FLOAT, 0, OutTex.sizeof, texBuf[0].t.ptr);
  gles2.glDrawArrays(GL_TRIANGLES, 0, n);
}

// ---------------------------------------------------------------------------------------------
// Matrix stack.

public void glMatrixMode(GLenum mode) {
  notInList("glMatrixMode");
  if (mode != GL_MODELVIEW && mode != GL_PROJECTION)
    throw new Exception("glMatrixMode: unsupported mode");
  matrixMode = mode;
}

public void glLoadIdentity() {
  if (recording()) {
    identity(recMat);
    return;
  }
  identity(top());
  mvpDirty = true;
}

public void glPushMatrix() {
  if (recording()) {
    if (recDepth + 1 >= recStack.length)
      throw new Exception("glPushMatrix: stack overflow in display list");
    recStack[recDepth++] = recMat;
    return;
  }
  if (matrixMode == GL_PROJECTION) {
    if (pjDepth + 1 >= pjStack.length)
      throw new Exception("glPushMatrix: GL_STACK_OVERFLOW (projection)");
    pjStack[pjDepth + 1] = pjStack[pjDepth];
    pjDepth++;
  } else {
    if (mvDepth + 1 >= mvStack.length)
      throw new Exception("glPushMatrix: GL_STACK_OVERFLOW (modelview)");
    mvStack[mvDepth + 1] = mvStack[mvDepth];
    mvDepth++;
  }
}

public void glPopMatrix() {
  if (recording()) {
    if (recDepth <= 0)
      throw new Exception("glPopMatrix: stack underflow in display list");
    recMat = recStack[--recDepth];
    return;
  }
  if (matrixMode == GL_PROJECTION) {
    if (pjDepth <= 0)
      throw new Exception("glPopMatrix: GL_STACK_UNDERFLOW (projection)");
    pjDepth--;
  } else {
    if (mvDepth <= 0)
      throw new Exception("glPopMatrix: GL_STACK_UNDERFLOW (modelview)");
    mvDepth--;
  }
  mvpDirty = true;
}

public void glTranslatef(GLfloat x, GLfloat y, GLfloat z) {
  if (recording()) {
    translate(recMat, x, y, z);
    return;
  }
  translate(top(), x, y, z);
  mvpDirty = true;
}

public void glScalef(GLfloat x, GLfloat y, GLfloat z) {
  if (recording()) {
    scale(recMat, x, y, z);
    return;
  }
  scale(top(), x, y, z);
  mvpDirty = true;
}

public void glRotatef(GLfloat angle, GLfloat x, GLfloat y, GLfloat z) {
  if (recording()) {
    rotate(recMat, angle, x, y, z);
    return;
  }
  rotate(top(), angle, x, y, z);
  mvpDirty = true;
}

public void glFrustum(GLdouble l, GLdouble r, GLdouble b, GLdouble t, GLdouble n, GLdouble f) {
  notInList("glFrustum");
  frustum(top(), l, r, b, t, n, f);
  mvpDirty = true;
}

public void glOrtho(GLdouble l, GLdouble r, GLdouble b, GLdouble t, GLdouble n, GLdouble f) {
  notInList("glOrtho");
  ortho(top(), l, r, b, t, n, f);
  mvpDirty = true;
}

// gluLookAt as in Mesa's GLU: M = [s; u; -f] then translate(-eye), multiplied onto the current matrix.
public void gluLookAt(GLdouble eyex, GLdouble eyey, GLdouble eyez,
                      GLdouble centerx, GLdouble centery, GLdouble centerz,
                      GLdouble upx, GLdouble upy, GLdouble upz) {
  notInList("gluLookAt");
  float[3] f = [cast(float) (centerx - eyex), cast(float) (centery - eyey), cast(float) (centerz - eyez)];
  float[3] up = [cast(float) upx, cast(float) upy, cast(float) upz];
  normalize(f);
  float[3] s;
  cross(f, up, s);
  normalize(s);
  float[3] u;
  cross(s, f, u);
  Mat4 m;
  identity(m);
  m[0] = s[0];
  m[4] = s[1];
  m[8] = s[2];
  m[1] = u[0];
  m[5] = u[1];
  m[9] = u[2];
  m[2] = -f[0];
  m[6] = -f[1];
  m[10] = -f[2];
  multiply(top(), m);
  translate(top(), -cast(float) eyex, -cast(float) eyey, -cast(float) eyez);
  mvpDirty = true;
}

private void normalize(ref float[3] v) {
  float r = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
  if (r == 0)
    return;
  v[0] /= r;
  v[1] /= r;
  v[2] /= r;
}

private void cross(ref float[3] a, ref float[3] b, ref float[3] r) {
  r[0] = a[1] * b[2] - a[2] * b[1];
  r[1] = a[2] * b[0] - a[0] * b[2];
  r[2] = a[0] * b[1] - a[1] * b[0];
}

// ---------------------------------------------------------------------------------------------
// Immediate mode.

public void glColor4f(GLfloat r, GLfloat g, GLfloat b, GLfloat a) {
  curColor[0] = r;
  curColor[1] = g;
  curColor[2] = b;
  curColor[3] = a;
  if (recording()) {
    recColorSet = true;
    recList.hasFinalColor = true;
    recList.finalColor = curColor;
  }
}

public void glTexCoord2f(GLfloat s, GLfloat t) {
  notInList("glTexCoord2f");
  curTex[0] = s;
  curTex[1] = t;
}

public void glBegin(GLenum mode) {
  if (inBegin)
    throw new Exception("glBegin inside glBegin/glEnd");
  switch (mode) {
  case GL_LINES: case GL_LINE_LOOP: case GL_LINE_STRIP:
  case GL_TRIANGLES: case GL_TRIANGLE_STRIP: case GL_TRIANGLE_FAN: case GL_QUADS:
    break;
  default:
    throw new Exception("glBegin: unsupported primitive " ~ to!string(mode));
  }
  inBegin = true;
  beginMode = mode;
  beginCount = 0;
  primN = 0;
}

private void emit(ref Vtx v, bool inh) {
  if (primN >= prim.length) {
    prim.length *= 2;
    primInh.length *= 2;
  }
  prim[primN] = v;
  primInh[primN] = inh;
  primN++;
}

public void glVertex3f(GLfloat x, GLfloat y, GLfloat z) {
  if (!inBegin)
    throw new Exception("glVertex3f outside glBegin/glEnd");
  Vtx v;
  v.p[0] = x;
  v.p[1] = y;
  v.p[2] = z;
  v.c = curColor;
  v.t = curTex;
  bool inh = recording() && !recColorSet;
  switch (beginMode) {
  case GL_LINES:
  case GL_TRIANGLES:
    emit(v, inh);
    break;
  case GL_LINE_STRIP:
    if (beginCount > 0) {
      emit(prev, prevInh);
      emit(v, inh);
    }
    prev = v;
    prevInh = inh;
    break;
  case GL_LINE_LOOP:
    if (beginCount == 0) {
      first = v;
      firstInh = inh;
    } else {
      emit(prev, prevInh);
      emit(v, inh);
    }
    prev = v;
    prevInh = inh;
    break;
  case GL_TRIANGLE_FAN:
    if (beginCount == 0) {
      first = v;
      firstInh = inh;
    } else if (beginCount >= 2) {
      emit(first, firstInh);
      emit(prev, prevInh);
      emit(v, inh);
    }
    prev = v;
    prevInh = inh;
    break;
  case GL_TRIANGLE_STRIP:
    if (beginCount >= 2) {
      // Triangle i uses vertices (i, i+1, i+2); odd ones swap the first two to keep the winding.
      if (beginCount % 2 == 0) {
        emit(first, firstInh);
        emit(prev, prevInh);
      } else {
        emit(prev, prevInh);
        emit(first, firstInh);
      }
      emit(v, inh);
    }
    first = prev;
    firstInh = prevInh;
    prev = v;
    prevInh = inh;
    break;
  case GL_QUADS:
    switch (beginCount % 4) {
    case 0: quad0 = v; quad0Inh = inh; break;
    case 1: quad1 = v; quad1Inh = inh; break;
    case 2: quad2 = v; quad2Inh = inh; break;
    default:
      emit(quad0, quad0Inh);
      emit(quad1, quad1Inh);
      emit(quad2, quad2Inh);
      emit(quad0, quad0Inh);
      emit(quad2, quad2Inh);
      emit(v, inh);
      break;
    }
    break;
  default:
    break;
  }
  beginCount++;
}

public void glVertex2f(GLfloat x, GLfloat y) {
  glVertex3f(x, y, 0);
}

private GLenum drawMode(GLenum beginMode) {
  switch (beginMode) {
  case GL_LINES: case GL_LINE_LOOP: case GL_LINE_STRIP:
    return GL_LINES;
  default:
    return GL_TRIANGLES;
  }
}

public void glEnd() {
  if (!inBegin)
    throw new Exception("glEnd without glBegin");
  inBegin = false;
  if (beginMode == GL_LINE_LOOP && beginCount >= 2) {
    emit(prev, prevInh);
    emit(first, firstInh);
  }
  if (primN == 0)
    return;
  GLenum mode = drawMode(beginMode);
  if (recording())
    recordPrimitive(mode);
  else if (texEnabled)
    drawTextured(mode);
  else
    addVertices(mode, prim.ptr, null, primN);
}

/**
 * Draws num vertices from separate position (xyz) and color (rgba) arrays; used by
 * VertexBatch. The current color is left as it is.
 */
public void drawArrays(GLenum mode, const(float)* vert, const(float)* col, int num) {
  if (mode != GL_LINES && mode != GL_TRIANGLES)
    throw new Exception("drawArrays: mode must be GL_LINES or GL_TRIANGLES");
  notInList("drawArrays");
  if (texEnabled)
    throw new Exception("drawArrays: textures are not supported");
  if (num <= 0)
    return;
  updateMVP();
  int bm = blendMode();
  const(float[3])* p = cast(const(float[3])*) vert;
  const(float[4])* c = cast(const(float[4])*) col;
  if (mode == GL_LINES) {
    for (int i = 0; i + 1 < num; i += 2)
      addLine(bm, p[i], c[i], p[i + 1], c[i + 1]);
  } else {
    for (int i = 0; i + 2 < num; i += 3)
      addTriangle(bm, p[i], c[i], p[i + 1], c[i + 1], p[i + 2], c[i + 2]);
  }
}

// ---------------------------------------------------------------------------------------------
// Display lists.

public GLuint glGenLists(GLsizei range) {
  if (range <= 0)
    return 0;
  GLuint base = cast(GLuint) lists.length;
  lists.length += range;
  return base;
}

public void glNewList(GLuint list, GLenum mode) {
  if (recording() || inBegin)
    throw new Exception("glNewList while recording or inside glBegin/glEnd");
  if (mode != GL_COMPILE)
    throw new Exception("glNewList: only GL_COMPILE is supported");
  if (list == 0 || list >= lists.length)
    throw new Exception("glNewList: invalid list " ~ to!string(list));
  recList = new DList;
  lists[list] = recList;
  identity(recMat);
  recDepth = 0;
  recColorSet = false;
}

private void recordPrimitive(GLenum mode) {
  DList l = recList;
  bool merge = l.chunks.length > 0 && l.chunks[$ - 1].mode == mode;
  if (!merge) {
    Chunk c;
    c.mode = mode;
    c.first = cast(int) l.data.length;
    l.chunks ~= c;
  }
  for (int i = 0; i < primN; i++) {
    Vtx v = prim[i];
    transformPoint(recMat, v.p);
    l.data ~= v;
    l.inherit ~= primInh[i];
    l.chunks[$ - 1].count++;
  }
}

public void glEndList() {
  if (!recording())
    throw new Exception("glEndList without glNewList");
  if (inBegin)
    throw new Exception("glEndList inside glBegin/glEnd");
  if (recDepth != 0)
    throw new Exception("glEndList: unbalanced glPushMatrix/glPopMatrix in display list");
  DList l = recList;
  recList = null;
  if (!isIdentity(recMat)) {
    l.hasPostMatrix = true;
    l.postMatrix = recMat;
  }
}

public void glDeleteLists(GLuint list, GLsizei range) {
  for (GLuint i = list; i < list + range && i < lists.length; i++)
    lists[i] = null;
}

public void glCallList(GLuint list) {
  notInList("glCallList");
  if (inBegin)
    throw new Exception("glCallList inside glBegin/glEnd");
  if (list >= lists.length || lists[list] is null)
    return;
  if (texEnabled)
    throw new Exception("glCallList: textures are not supported");
  DList l = lists[list];
  foreach (ref Chunk c; l.chunks)
    addVertices(c.mode, l.data.ptr + c.first, l.inherit.ptr + c.first, c.count);
  if (l.hasPostMatrix) {
    multiply(mvStack[mvDepth], l.postMatrix);
    mvpDirty = true;
  }
  if (l.hasFinalColor)
    curColor = l.finalColor;
}

// ---------------------------------------------------------------------------------------------
// State. Blending, culling and the line width only set what the next vertices are made with.

public void glEnable(GLenum cap) {
  notInList("glEnable");
  switch (cap) {
  case GL_BLEND:
    blendEnabled = true;
    break;
  case GL_CULL_FACE:
    cullEnabled = true;
    break;
  case GL_TEXTURE_2D:
    texEnabled = true;
    break;
  case GL_LINE_SMOOTH:
  case GL_LIGHTING:
  case GL_COLOR_MATERIAL:
    break;
  default:
    throw new Exception("glEnable: unsupported capability " ~ to!string(cap));
  }
}

public void glDisable(GLenum cap) {
  notInList("glDisable");
  switch (cap) {
  case GL_BLEND:
    blendEnabled = false;
    break;
  case GL_CULL_FACE:
    cullEnabled = false;
    break;
  case GL_TEXTURE_2D:
    texEnabled = false;
    break;
  case GL_DEPTH_TEST:
  case GL_LINE_SMOOTH:
  case GL_LIGHTING:
  case GL_COLOR_MATERIAL:
    break;
  default:
    throw new Exception("glDisable: unsupported capability " ~ to!string(cap));
  }
}

public void glBlendFunc(GLenum sfactor, GLenum dfactor) {
  notInList("glBlendFunc");
  blendSrc = sfactor;
  blendDst = dfactor;
}

public void glLineWidth(GLfloat width) {
  notInList("glLineWidth");
  lineWidth = width;
}

public void glViewport(GLint x, GLint y, GLsizei width, GLsizei height) {
  notInList("glViewport");
  flushGL();
  viewW = width;
  viewH = height;
  gles2.glViewport(x, y, width, height);
}

public void glClearColor(GLclampf r, GLclampf g, GLclampf b, GLclampf a) {
  notInList("glClearColor");
  gles2.glClearColor(r, g, b, a);
}

public void glClear(GLbitfield mask) {
  notInList("glClear");
  flushGL();
  gles2.glClear(mask);
}

public GLenum glGetError() {
  flushGL();
  return gles2.glGetError();
}

public void glGenTextures(GLsizei n, GLuint* textures) {
  gles2.glGenTextures(n, textures);
}

public void glDeleteTextures(GLsizei n, const(GLuint)* textures) {
  gles2.glDeleteTextures(n, textures);
}

public void glBindTexture(GLenum target, GLuint texture) {
  notInList("glBindTexture");
  gles2.glBindTexture(target, texture);
}

public void glTexParameteri(GLenum target, GLenum pname, GLint param) {
  gles2.glTexParameteri(target, pname, param);
}

public void glTexImage2D(GLenum target, GLint level, GLint internalformat, GLsizei width,
                         GLsizei height, GLint border, GLenum format, GLenum type,
                         const(void)* pixels) {
  // GLES 2 requires the internal format to equal the format (LuminousScreen passes GL_RGB/GL_RGBA).
  gles2.glTexImage2D(target, level, format, width, height, border, format, type, pixels);
}

public void glCopyTexImage2D(GLenum target, GLint level, GLenum internalformat, GLint x, GLint y,
                             GLsizei width, GLsizei height, GLint border) {
  notInList("glCopyTexImage2D");
  flushGL();
  gles2.glCopyTexImage2D(target, level, internalformat, x, y, width, height, border);
}
