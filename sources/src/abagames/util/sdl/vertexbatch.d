/*
 * Vertex batching added for the PortMaster port (gl4es).
 */
module abagames.util.sdl.vertexbatch;

private import abagames.util.sdl.gl;
private import abagames.util.vector;
private import abagames.util.sdl.screen3d;

/**
 * Collects colored vertices of one primitive type (GL_LINES or GL_TRIANGLES) and draws them
 * with a single glDrawArrays. Used instead of many small glBegin/glEnd blocks, which gl4es
 * turns into one GLES draw call each. Primitives are drawn in the order they were added.
 */
public class VertexBatch {
 private:
  GLenum mode;
  float[] vert;
  float[] col;
  int num;
  float r = 1, g = 1, b = 1, a = 1;

  public this(GLenum mode, int maxVertexNum) {
    this.mode = mode;
    vert = new float[maxVertexNum * 3];
    col = new float[maxVertexNum * 4];
  }

  // Same as Screen3D.setColor.
  public void color(float r, float g, float b, float a = 1) {
    this.r = r * Screen3D.brightness;
    this.g = g * Screen3D.brightness;
    this.b = b * Screen3D.brightness;
    this.a = a;
  }

  public void vertex(float x, float y, float z) {
    if (num * 3 >= vert.length) {
      vert.length *= 2;
      col.length *= 2;
    }
    vert[num * 3] = x;
    vert[num * 3 + 1] = y;
    vert[num * 3 + 2] = z;
    col[num * 4] = r;
    col[num * 4 + 1] = g;
    col[num * 4 + 2] = b;
    col[num * 4 + 3] = a;
    num++;
  }

  public void vertex(Vector3 v) {
    vertex(v.x, v.y, v.z);
  }

  public void flush() {
    if (num <= 0)
      return;
    drawArrays(mode, vert.ptr, col.ptr, num);
    // Leave the current color where glBegin/glEnd drawing would have left it.
    glColor4f(r, g, b, a);
    num = 0;
  }
}
