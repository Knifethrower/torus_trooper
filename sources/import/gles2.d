/*
 * OpenGL ES 2.0 bindings for the PortMaster port: only the functions and constants the game's
 * renderer (abagames.util.sdl.gl) uses. The entry points are loaded with SDL_GL_GetProcAddress
 * after the context exists, so the binary has no link-time dependency on a GL library.
 */
module gles2;

private import std.conv;
private import bindbc.sdl;

alias GLenum = uint;
alias GLboolean = ubyte;
alias GLbitfield = uint;
alias GLint = int;
alias GLsizei = int;
alias GLuint = uint;
alias GLfloat = float;
alias GLclampf = float;
alias GLchar = char;
alias GLsizeiptr = ptrdiff_t;
alias GLintptr = ptrdiff_t;
alias GLvoid = void;

enum : GLenum {
  GL_FALSE = 0,
  GL_TRUE = 1,
  GL_NO_ERROR = 0,
  GL_ZERO = 0,
  GL_ONE = 1,
  GL_LINES = 0x0001,
  GL_LINE_LOOP = 0x0002,
  GL_LINE_STRIP = 0x0003,
  GL_TRIANGLES = 0x0004,
  GL_TRIANGLE_STRIP = 0x0005,
  GL_TRIANGLE_FAN = 0x0006,
  GL_DEPTH_BUFFER_BIT = 0x00000100,
  GL_COLOR_BUFFER_BIT = 0x00004000,
  GL_SRC_ALPHA = 0x0302,
  GL_ONE_MINUS_SRC_ALPHA = 0x0303,
  GL_CULL_FACE = 0x0B44,
  GL_DEPTH_TEST = 0x0B71,
  GL_BLEND = 0x0BE2,
  GL_DITHER = 0x0BD0,
  GL_VIEWPORT = 0x0BA2,
  GL_TEXTURE_2D = 0x0DE1,
  GL_UNPACK_ALIGNMENT = 0x0CF5,
  GL_UNSIGNED_BYTE = 0x1401,
  GL_FLOAT = 0x1406,
  GL_RGB = 0x1907,
  GL_RGBA = 0x1908,
  GL_VENDOR = 0x1F00,
  GL_RENDERER = 0x1F01,
  GL_VERSION = 0x1F02,
  GL_LINEAR = 0x2601,
  GL_TEXTURE_MAG_FILTER = 0x2800,
  GL_TEXTURE_MIN_FILTER = 0x2801,
  GL_TEXTURE_WRAP_S = 0x2802,
  GL_TEXTURE_WRAP_T = 0x2803,
  GL_CLAMP_TO_EDGE = 0x812F,
  GL_ALIASED_LINE_WIDTH_RANGE = 0x846E,
  GL_TEXTURE0 = 0x84C0,
  GL_ARRAY_BUFFER = 0x8892,
  GL_STREAM_DRAW = 0x88E0,
  GL_STATIC_DRAW = 0x88E4,
  GL_FRAGMENT_SHADER = 0x8B30,
  GL_VERTEX_SHADER = 0x8B31,
  GL_COMPILE_STATUS = 0x8B81,
  GL_LINK_STATUS = 0x8B82,
  GL_INFO_LOG_LENGTH = 0x8B84,
}

alias PFN_glGetError = extern(C) GLenum function();
alias PFN_glGetString = extern(C) const(ubyte)* function(GLenum name);
alias PFN_glGetIntegerv = extern(C) void function(GLenum pname, GLint* params);
alias PFN_glGetFloatv = extern(C) void function(GLenum pname, GLfloat* params);
alias PFN_glEnable = extern(C) void function(GLenum cap);
alias PFN_glDisable = extern(C) void function(GLenum cap);
alias PFN_glViewport = extern(C) void function(GLint x, GLint y, GLsizei width, GLsizei height);
alias PFN_glClearColor = extern(C) void function(GLclampf red, GLclampf green, GLclampf blue, GLclampf alpha);
alias PFN_glClear = extern(C) void function(GLbitfield mask);
alias PFN_glBlendFunc = extern(C) void function(GLenum sfactor, GLenum dfactor);
alias PFN_glLineWidth = extern(C) void function(GLfloat width);
alias PFN_glGenTextures = extern(C) void function(GLsizei n, GLuint* textures);
alias PFN_glDeleteTextures = extern(C) void function(GLsizei n, const(GLuint)* textures);
alias PFN_glBindTexture = extern(C) void function(GLenum target, GLuint texture);
alias PFN_glActiveTexture = extern(C) void function(GLenum texture);
alias PFN_glTexImage2D = extern(C) void function(GLenum target, GLint level, GLint internalformat, GLsizei width, GLsizei height, GLint border, GLenum format, GLenum type, const(void)* pixels);
alias PFN_glTexParameteri = extern(C) void function(GLenum target, GLenum pname, GLint param);
alias PFN_glCopyTexImage2D = extern(C) void function(GLenum target, GLint level, GLenum internalformat, GLint x, GLint y, GLsizei width, GLsizei height, GLint border);
alias PFN_glPixelStorei = extern(C) void function(GLenum pname, GLint param);
alias PFN_glCreateShader = extern(C) GLuint function(GLenum type);
alias PFN_glShaderSource = extern(C) void function(GLuint shader, GLsizei count, const(GLchar*)* string, const(GLint)* length);
alias PFN_glCompileShader = extern(C) void function(GLuint shader);
alias PFN_glGetShaderiv = extern(C) void function(GLuint shader, GLenum pname, GLint* params);
alias PFN_glGetShaderInfoLog = extern(C) void function(GLuint shader, GLsizei bufSize, GLsizei* length, GLchar* infoLog);
alias PFN_glDeleteShader = extern(C) void function(GLuint shader);
alias PFN_glCreateProgram = extern(C) GLuint function();
alias PFN_glAttachShader = extern(C) void function(GLuint program, GLuint shader);
alias PFN_glLinkProgram = extern(C) void function(GLuint program);
alias PFN_glGetProgramiv = extern(C) void function(GLuint program, GLenum pname, GLint* params);
alias PFN_glGetProgramInfoLog = extern(C) void function(GLuint program, GLsizei bufSize, GLsizei* length, GLchar* infoLog);
alias PFN_glDeleteProgram = extern(C) void function(GLuint program);
alias PFN_glUseProgram = extern(C) void function(GLuint program);
alias PFN_glGetAttribLocation = extern(C) GLint function(GLuint program, const(GLchar)* name);
alias PFN_glGetUniformLocation = extern(C) GLint function(GLuint program, const(GLchar)* name);
alias PFN_glUniformMatrix4fv = extern(C) void function(GLint location, GLsizei count, GLboolean transpose, const(GLfloat)* value);
alias PFN_glUniform1i = extern(C) void function(GLint location, GLint v0);
alias PFN_glEnableVertexAttribArray = extern(C) void function(GLuint index);
alias PFN_glDisableVertexAttribArray = extern(C) void function(GLuint index);
alias PFN_glVertexAttribPointer = extern(C) void function(GLuint index, GLint size, GLenum type, GLboolean normalized, GLsizei stride, const(void)* pointer);
alias PFN_glVertexAttrib4f = extern(C) void function(GLuint index, GLfloat x, GLfloat y, GLfloat z, GLfloat w);
alias PFN_glDrawArrays = extern(C) void function(GLenum mode, GLint first, GLsizei count);
alias PFN_glGenBuffers = extern(C) void function(GLsizei n, GLuint* buffers);
alias PFN_glDeleteBuffers = extern(C) void function(GLsizei n, const(GLuint)* buffers);
alias PFN_glBindBuffer = extern(C) void function(GLenum target, GLuint buffer);
alias PFN_glBufferData = extern(C) void function(GLenum target, GLsizeiptr size, const(void)* data, GLenum usage);
alias PFN_glBufferSubData = extern(C) void function(GLenum target, GLintptr offset, GLsizeiptr size, const(void)* data);

__gshared {
  PFN_glGetError glGetError;
  PFN_glGetString glGetString;
  PFN_glGetIntegerv glGetIntegerv;
  PFN_glGetFloatv glGetFloatv;
  PFN_glEnable glEnable;
  PFN_glDisable glDisable;
  PFN_glViewport glViewport;
  PFN_glClearColor glClearColor;
  PFN_glClear glClear;
  PFN_glBlendFunc glBlendFunc;
  PFN_glLineWidth glLineWidth;
  PFN_glGenTextures glGenTextures;
  PFN_glDeleteTextures glDeleteTextures;
  PFN_glBindTexture glBindTexture;
  PFN_glActiveTexture glActiveTexture;
  PFN_glTexImage2D glTexImage2D;
  PFN_glTexParameteri glTexParameteri;
  PFN_glCopyTexImage2D glCopyTexImage2D;
  PFN_glPixelStorei glPixelStorei;
  PFN_glCreateShader glCreateShader;
  PFN_glShaderSource glShaderSource;
  PFN_glCompileShader glCompileShader;
  PFN_glGetShaderiv glGetShaderiv;
  PFN_glGetShaderInfoLog glGetShaderInfoLog;
  PFN_glDeleteShader glDeleteShader;
  PFN_glCreateProgram glCreateProgram;
  PFN_glAttachShader glAttachShader;
  PFN_glLinkProgram glLinkProgram;
  PFN_glGetProgramiv glGetProgramiv;
  PFN_glGetProgramInfoLog glGetProgramInfoLog;
  PFN_glDeleteProgram glDeleteProgram;
  PFN_glUseProgram glUseProgram;
  PFN_glGetAttribLocation glGetAttribLocation;
  PFN_glGetUniformLocation glGetUniformLocation;
  PFN_glUniformMatrix4fv glUniformMatrix4fv;
  PFN_glUniform1i glUniform1i;
  PFN_glEnableVertexAttribArray glEnableVertexAttribArray;
  PFN_glDisableVertexAttribArray glDisableVertexAttribArray;
  PFN_glVertexAttribPointer glVertexAttribPointer;
  PFN_glVertexAttrib4f glVertexAttrib4f;
  PFN_glDrawArrays glDrawArrays;
  PFN_glGenBuffers glGenBuffers;
  PFN_glDeleteBuffers glDeleteBuffers;
  PFN_glBindBuffer glBindBuffer;
  PFN_glBufferData glBufferData;
  PFN_glBufferSubData glBufferSubData;
}

private T load(T)(const char* name) {
  void* p = SDL_GL_GetProcAddress(name);
  if (p is null)
    throw new Exception("OpenGL ES 2 function not found: " ~ to!string(name));
  return cast(T) p;
}

/**
 * Load the entry points from the current SDL GL context. Throws if one is missing.
 */
public void loadGLES2() {
  glGetError = load!PFN_glGetError("glGetError");
  glGetString = load!PFN_glGetString("glGetString");
  glGetIntegerv = load!PFN_glGetIntegerv("glGetIntegerv");
  glGetFloatv = load!PFN_glGetFloatv("glGetFloatv");
  glEnable = load!PFN_glEnable("glEnable");
  glDisable = load!PFN_glDisable("glDisable");
  glViewport = load!PFN_glViewport("glViewport");
  glClearColor = load!PFN_glClearColor("glClearColor");
  glClear = load!PFN_glClear("glClear");
  glBlendFunc = load!PFN_glBlendFunc("glBlendFunc");
  glLineWidth = load!PFN_glLineWidth("glLineWidth");
  glGenTextures = load!PFN_glGenTextures("glGenTextures");
  glDeleteTextures = load!PFN_glDeleteTextures("glDeleteTextures");
  glBindTexture = load!PFN_glBindTexture("glBindTexture");
  glActiveTexture = load!PFN_glActiveTexture("glActiveTexture");
  glTexImage2D = load!PFN_glTexImage2D("glTexImage2D");
  glTexParameteri = load!PFN_glTexParameteri("glTexParameteri");
  glCopyTexImage2D = load!PFN_glCopyTexImage2D("glCopyTexImage2D");
  glPixelStorei = load!PFN_glPixelStorei("glPixelStorei");
  glCreateShader = load!PFN_glCreateShader("glCreateShader");
  glShaderSource = load!PFN_glShaderSource("glShaderSource");
  glCompileShader = load!PFN_glCompileShader("glCompileShader");
  glGetShaderiv = load!PFN_glGetShaderiv("glGetShaderiv");
  glGetShaderInfoLog = load!PFN_glGetShaderInfoLog("glGetShaderInfoLog");
  glDeleteShader = load!PFN_glDeleteShader("glDeleteShader");
  glCreateProgram = load!PFN_glCreateProgram("glCreateProgram");
  glAttachShader = load!PFN_glAttachShader("glAttachShader");
  glLinkProgram = load!PFN_glLinkProgram("glLinkProgram");
  glGetProgramiv = load!PFN_glGetProgramiv("glGetProgramiv");
  glGetProgramInfoLog = load!PFN_glGetProgramInfoLog("glGetProgramInfoLog");
  glDeleteProgram = load!PFN_glDeleteProgram("glDeleteProgram");
  glUseProgram = load!PFN_glUseProgram("glUseProgram");
  glGetAttribLocation = load!PFN_glGetAttribLocation("glGetAttribLocation");
  glGetUniformLocation = load!PFN_glGetUniformLocation("glGetUniformLocation");
  glUniformMatrix4fv = load!PFN_glUniformMatrix4fv("glUniformMatrix4fv");
  glUniform1i = load!PFN_glUniform1i("glUniform1i");
  glEnableVertexAttribArray = load!PFN_glEnableVertexAttribArray("glEnableVertexAttribArray");
  glDisableVertexAttribArray = load!PFN_glDisableVertexAttribArray("glDisableVertexAttribArray");
  glVertexAttribPointer = load!PFN_glVertexAttribPointer("glVertexAttribPointer");
  glVertexAttrib4f = load!PFN_glVertexAttrib4f("glVertexAttrib4f");
  glDrawArrays = load!PFN_glDrawArrays("glDrawArrays");
  glGenBuffers = load!PFN_glGenBuffers("glGenBuffers");
  glDeleteBuffers = load!PFN_glDeleteBuffers("glDeleteBuffers");
  glBindBuffer = load!PFN_glBindBuffer("glBindBuffer");
  glBufferData = load!PFN_glBufferData("glBufferData");
  glBufferSubData = load!PFN_glBufferSubData("glBufferSubData");
}
