/*
 * $Id: screen3d.d,v 1.2 2005/01/01 12:40:28 kenta Exp $
 *
 * Copyright 2004 Kenta Cho. Some rights reserved.
 */
module abagames.util.sdl.screen3d;

private import std.string;
private import std.conv;
private import bindbc.sdl;
private import abagames.util.sdl.gl;
private import abagames.util.vector;
private import abagames.util.sdl.screen;
private import abagames.util.sdl.sdlexception;

/**
 * SDL screen handler(3D, OpenGL).
 */
public class Screen3D: Screen {
 public:
  static float brightness = 1;
  static int width = 640;
  static int height = 480;
  static int screenWidth = 640;
  static int screenHeight = 480;
  static int screenStartX = 0;
  static int screenStartY = 0;
  // How far the view reaches beyond the width x height layout (1 = not at all), and the same
  // as margins in layout units on each side.
  static float extendX = 1, extendY = 1;
  static float marginX = 0, marginY = 0;
  static string name = "";
  static SDL_Window* window;
  static SDL_GLContext context;
  static bool windowMode = false;
  static float nearPlane = 0.1;
  static float farPlane = 1000;
 private:

  protected abstract void init();
  protected abstract void close();

  public override void initSDL() {
    // Initialize SDL.
    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
      throw new SDLInitFailedException(
        "Unable to initialize SDL: " ~ to!string(SDL_GetError()));
    }
    // Create an OpenGL ES 2 screen (see abagames.util.sdl.gl).
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);
    uint videoFlags;
      videoFlags = SDL_WINDOW_OPENGL;
    if (windowMode) {
      videoFlags |= SDL_WINDOW_RESIZABLE;
    } else {
      videoFlags |= SDL_WINDOW_FULLSCREEN_DESKTOP;
    }
    window = SDL_CreateWindow(std.string.toStringz(name), SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, screenWidth, screenHeight, videoFlags);
    if (window == null) {
      throw new SDLInitFailedException(
        "Unable to create SDL window: " ~ to!string(SDL_GetError()));
    }
    context = SDL_GL_CreateContext(window);
    if (context == null) {
      SDL_DestroyWindow(window);
      window = null;
      throw new SDLInitFailedException(
        "Unable to initialize OpenGL context: " ~ to!string(SDL_GetError()));
    }
    initGL();
    SDL_GetWindowSize(window, &screenWidth, &screenHeight);
    glViewport(screenStartX, screenStartY, screenWidth, screenHeight);
    glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
    resized(screenWidth, screenHeight);
    SDL_ShowCursor(SDL_DISABLE);
    init();
  }

  // Reset viewport when the screen is resized.

  // The picture fills the screen. The game is laid out for width x height (640x480, 4:3): on
  // a wider screen the view is extended to the sides, on a narrower one (3:2 is wider, 1:1 and
  // 5:4 are narrower) upwards and downwards, so the original view is always inside.

  public void screenResized() {
    static if (SDL_VERSION_ATLEAST(2, 0, 1)) {
      SDL_version linked;
      SDL_GetVersion(&linked);
      if (SDL_version(linked.major, linked.minor, linked.patch) >= SDL_version(2, 0, 1))
        SDL_GL_GetDrawableSize(window, &screenWidth, &screenHeight);
    }
    screenStartX = screenStartY = 0;
    float ratio = (cast(float) screenWidth * height) / (cast(float) screenHeight * width);
    if (ratio >= 1) {
      extendX = ratio;
      extendY = 1;
    } else {
      extendX = 1;
      extendY = 1 / ratio;
    }
    marginX = width * (extendX - 1) / 2;
    marginY = height * (extendY - 1) / 2;
    glViewport(screenStartX, screenStartY, screenWidth, screenHeight);
    setFrustum(nearPlane);
  }

  // The perspective projection with the near plane's half width np.
  public static void setFrustum(float np) {
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glFrustum(-np * extendX,
              np * extendX,
              -np * cast(GLfloat) height / cast(GLfloat) width * extendY,
              np * cast(GLfloat) height / cast(GLfloat) width * extendY,
              0.1f, farPlane);
    glMatrixMode(GL_MODELVIEW);
  }

  public override void resized(int width, int height) {
    this.screenWidth = width;
    this.screenHeight = height;
    screenResized();
  }

  public override void closeSDL() {
    close();
    SDL_ShowCursor(SDL_ENABLE);
    closeGL();
    SDL_GL_DeleteContext(context);
    SDL_DestroyWindow(window);
  }

  public override void flip() {
    flushGL();
    handleError();
    SDL_GL_SwapWindow(window);
  }

  public override void clear() {
    glClear(GL_COLOR_BUFFER_BIT);
  }

  public void handleError() {
    GLenum error = glGetError();
    if (error == GL_NO_ERROR)
      return;
    closeSDL();
    throw new Exception("OpenGL error(" ~ to!string(error) ~ ")");
  }

  protected void setCaption(const char[] name) {
    this.name = name.idup;
    if (window != null) {
      SDL_SetWindowTitle(window, std.string.toStringz(name));
    }
  }

  public static void setColor(float r, float g, float b, float a = 1) {
    glColor4f(r * brightness, g * brightness, b * brightness, a);
  }

  public static void setClearColor(float r, float g, float b, float a = 1) {
    glClearColor(r * brightness, g * brightness, b * brightness, a);
  }

  public static void glVertex(Vector3 v) {
    glVertex3f(v.x, v.y, v.z);
  }

  public static void glTranslate(Vector3 v) {
    glTranslatef(v.x, v.y, v.z);
  }
}
