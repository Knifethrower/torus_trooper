/*
 * $Id: particle.d,v 1.3 2005/01/01 12:40:28 kenta Exp $
 *
 * Copyright 2004 Kenta Cho. Some rights reserved.
 */
module abagames.tt.particle;

private import abagames.util.math;
private import abagames.util.sdl.gl;
private import abagames.util.actor;
private import abagames.util.vector;
private import abagames.util.rand;
private import abagames.util.sdl.luminous;
private import abagames.util.sdl.vertexbatch;
private import abagames.tt.tunnel;
private import abagames.tt.ship;
private import abagames.tt.screen;

/**
 * Particles.
 */
public class Particle: LuminousActor {
 public:
  static enum PType {
    SPARK, STAR, FRAGMENT, JET,
  };
 private:
  static const float GRAVITY = 0.02;
  static const float SIZE = 0.3;
  static Rand rand;
  // Sparks and stars of all particles are collected here and drawn by ParticlePool.draw.
  static VertexBatch sparkBatch, starBatch;
  Tunnel tunnel;
  Ship ship;
  Vector3 pos;
  Vector3 vel;
  Vector3 sp, psp;
  Vector3 rsp, rpsp;  // Mirror point.
  Vector icp;
  float r, g, b;
  float lumAlp;
  int cnt;
  bool inCourse;
  int type;
  float d1, d2, md1, md2;
  float width, height;

  public static void initRand() {
    rand = new Rand;
    sparkBatch = new VertexBatch(GL_TRIANGLES, 4096);
    starBatch = new VertexBatch(GL_LINES, 1024);
  }

  public static void flushBatches() {
    sparkBatch.flush();
    starBatch.flush();
  }

  // Triangle fan of the center and the 4 corners of a square (the first corner repeated at
  // the end) as 4 triangles.
  private static void addSparkFan(Vector3 c, float r, float g, float b, float a,
                                  float x, float y, float z) {
    static const float[2][5] corner =
      [[-SIZE, -SIZE], [SIZE, -SIZE], [SIZE, SIZE], [-SIZE, SIZE], [-SIZE, -SIZE]];
    for (int i = 0; i < 4; i++) {
      sparkBatch.color(r, g, b, a);
      sparkBatch.vertex(c);
      sparkBatch.color(r, g, b, 0);
      sparkBatch.vertex(x + corner[i][0], y + corner[i][1], z);
      sparkBatch.vertex(x + corner[i + 1][0], y + corner[i + 1][1], z);
    }
  }

  public static void setRandSeed(long seed) {
    rand.setSeed(seed);
  }

  public override void init(Object[] args) {
    tunnel = cast(Tunnel) args[0];
    ship = cast(Ship) args[1];
    pos = new Vector3;
    vel = new Vector3;
    sp = new Vector3;
    psp = new Vector3;
    rsp = new Vector3;
    rpsp = new Vector3;
    icp = new Vector;
  }

  public void set(Vector p, float z, float d, float mz, float speed,
                  float r, float g, float b, int c = 16,
                  int t = PType.SPARK, float w = 0, float h = 0) {
    pos.x = p.x;
    pos.y = p.y;
    pos.z = z;
    float sb = rand.nextFloat(0.8) + 0.4;
    const float dSin = sin(d);
    const float dCos = cos(d);
    vel.x = dSin * speed * sb;
    vel.y = dCos * speed * sb;
    vel.z = mz;
    this.r = r;
    this.g = g;
    this.b = b;
    cnt = c + rand.nextInt(c / 2);
    type = t;
    lumAlp = 0.8 + rand.nextFloat(0.2);
    if (type == PType.STAR)
      inCourse = false;
    else
      inCourse = true;
    if (type == PType.FRAGMENT) {
      d1 = d2 = 0;
      md1 = rand.nextSignedFloat(12);
      md2 = rand.nextSignedFloat(12);
      width = w;
      height = h;
    }
    checkInCourse();
    calcScreenPos();
    exists = true;
  }

  public override void move() {
    cnt--;
    //if (cnt < 0 || (type == PType.STAR && sp.z < -2)) {
    if (cnt < 0 || pos.y < -2) {
      exists = false;
      return;
    }
    psp.x = sp.x;
    psp.y = sp.y;
    psp.z = sp.z;
    if (inCourse) {
      rpsp.x = rsp.x;
      rpsp.y = rsp.y;
      rpsp.z = rsp.z;
    }
    pos += vel;
    if (type == PType.FRAGMENT)
      pos.y -= ship.speed / 2;
    else if (type == PType.SPARK)
      pos.y -= ship.speed * 0.33f;
    else
      pos.y -= ship.speed;
    if (type != PType.STAR) {
      if (type == PType.FRAGMENT)
        vel.z -= GRAVITY / 2;
      else
        vel.z -= GRAVITY;
      if (inCourse && pos.z < 0) {
        if (type == PType.FRAGMENT)
          vel.z *= -0.6;
        else
          vel.z *= -0.8;
        vel *= 0.9;
        pos.z += vel.z * 2;
        checkInCourse();
      }
    }
    if (type == PType.FRAGMENT) {
      d1 += md1;
      d2 += md2;
      md1 *= 0.98f;
      md2 *= 0.98f;
      width *= 0.98f;
      height *= 0.98f;
    }
    lumAlp *= 0.98;
    calcScreenPos();
  }

  private void calcScreenPos() {
    Vector3 p = tunnel.getPos(pos);
    sp.x = p.x;
    sp.y = p.y;
    sp.z = p.z;
    if (inCourse) {
      pos.z = -pos.z;
      p = tunnel.getPos(pos);
      rsp.x = p.x;
      rsp.y = p.y;
      rsp.z = p.z;
      pos.z = -pos.z;
    }
  }

  private void checkInCourse() {
    icp.x = pos.x;
    icp.y = pos.y;
    if (tunnel.checkInCourse(icp) != 0)
      inCourse = false;
  }

  public override void draw() {
    switch (type) {
    case PType.SPARK:
    case PType.JET:
      drawSpark();
      break;
    case PType.STAR:
      drawStar();
      break;
    case PType.FRAGMENT:
      drawFragment();
      break;
    default:
      break;
    }
  }

  private void drawSpark() {
    addSparkFan(psp, r, g, b, 0.5, sp.x, sp.y, sp.z);
    if (inCourse)
      addSparkFan(rpsp, r, g, b, 0.2, rsp.x, rsp.y, sp.z);
  }

  private void drawStar() {
    starBatch.color(r, g, b, 1);
    starBatch.vertex(psp);
    starBatch.color(r, g, b, 0.2);
    starBatch.vertex(sp);
  }

  private void drawFragment() {
    glPushMatrix();
    glTranslatef(sp.x, sp.y, sp.z);
    glRotatef(d1, 0, 0, 1);
    glRotatef(d2, 0, 1, 0);
    glBegin(GL_LINE_LOOP);
    Screen.setColor(r, g, b, 0.5);
    glVertex3f(width, 0, height);
    glVertex3f(-width, 0, height);
    glVertex3f(-width, 0, -height);
    glVertex3f(width, 0, -height);
    glEnd();
    glBegin(GL_TRIANGLE_FAN);
    Screen.setColor(r, g, b, 0.2);
    glVertex3f(width, 0, height);
    glVertex3f(-width, 0, height);
    glVertex3f(-width, 0, -height);
    glVertex3f(width, 0, -height);
    glEnd();
    glPopMatrix();
  }

  public override void drawLuminous() {
    if (lumAlp < 0.2 || type != PType.SPARK) return;
    glBegin(GL_TRIANGLE_FAN);
    Screen.setColor(r, g, b, lumAlp * 0.6);
    Screen.glVertex(psp);
    Screen.setColor(r, g, b, 0);
    glVertex3f(sp.x - SIZE, sp.y - SIZE, sp.z);
    glVertex3f(sp.x + SIZE, sp.y - SIZE, sp.z);
    glVertex3f(sp.x + SIZE, sp.y + SIZE, sp.z);
    glVertex3f(sp.x - SIZE, sp.y + SIZE, sp.z);
    glVertex3f(sp.x - SIZE, sp.y - SIZE, sp.z);
    glEnd();
  }
}

public class ParticlePool: LuminousActorPool!(Particle) {
  public this(int n, Object[] args) {
    super(n, args);
  }

  // Particles are drawn with additive blending (GL_SRC_ALPHA, GL_ONE), so drawing the sparks and
  // stars together after the fragments gives the same picture as drawing them one by one.
  public override void draw() {
    super.draw();
    Particle.flushBatches();
  }
}
