/*
 * $Id: boot.d,v 1.2 2005/01/01 12:40:27 kenta Exp $
 *
 * Copyright 2004 Kenta Cho. Some rights reserved.
 */
module abagames.tt.boot;

private import std.string;
private import std.conv;
private import core.stdc.stdlib;
private import abagames.util.logger;
private import abagames.util.tokenizer;
private import abagames.util.sdl.mainloop;
private import abagames.util.sdl.pad;
private import abagames.util.sdl.recordablepad;
private import abagames.util.sdl.sound;
private import abagames.tt.screen;
private import abagames.tt.gamemanager;
private import abagames.tt.prefmanager;

/**
 * Boot the game.
 */
private:
Screen screen;
Pad input;
GameManager gameManager;
PrefManager prefManager;
MainLoop mainLoop;

version (Win32_release) {
  // Boot as the Windows executable.
  private import core.runtime;
  private import core.sys.windows.windows;

  extern (Windows)
  public int WinMain(HINSTANCE hInstance,
		     HINSTANCE hPrevInstance,
		     LPSTR lpCmdLine,
		     int nCmdShow) {
    int result;
    try {
      Runtime.initialize();
      char[4096] exe;
      GetModuleFileNameA(null, exe.ptr, 4096);
      string[1] prog;
      prog[0] = to!string(exe);
      result = boot(prog ~ std.string.split(to!string(lpCmdLine)));
      Runtime.terminate();
    } catch (Throwable o) {
      Logger.error("Exception: " ~ o.toString());
      result = EXIT_FAILURE;
    }
    return result;
  }
} else {
  // Boot as the general executable.
  public int main(string[] args) {
    return boot(args);
  }
}

public int boot(string[] args) {
  screen = new Screen;
  input = new RecordablePad;
  // PortMaster: gptokeyb2 turns the pad into keys, and raw joystick button
  // numbers differ between handhelds, so the joystick is not read directly.
  version (PORTMASTER) {
  } else {
    try {
      input.openJoystick();
    } catch (Exception e) {}
  }
  gameManager = new GameManager;
  prefManager = new PrefManager;
  mainLoop = new MainLoop(screen, input, gameManager, prefManager);
  try {
    parseArgs(args);
  } catch (Exception e) {
    return EXIT_FAILURE;
  }
  try {
    mainLoop.loop();
  } catch (Exception e) {
    try {
      gameManager.saveErrorReplay();
    } catch (Exception e1) {}
    throw e;
  }
  return EXIT_SUCCESS;
}

private void parseArgs(string[] commandArgs) {
  string[] args = readOptionsIniFile();
  for (int i = 1; i < commandArgs.length; i++)
    args ~= commandArgs[i];
  string progName = commandArgs[0];
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
    case "-brightness":
      if (i >= args.length - 1) {
        usage(progName);
        throw new Exception("Invalid options");
      }
      i++;
      float b = cast(float) to!int(args[i]) / 100;
      if (b < 0 || b > 1) {
        usage(args[0]);
        throw new Exception("Invalid options");
      }
      Screen.brightness = b;
      break;
    case "-luminosity":
    case "-luminous":
      if (i >= args.length - 1) {
        usage(progName);
        throw new Exception("Invalid options");
      }
      i++;
      float l = cast(float) to!int(args[i]) / 100;
      if (l < 0 || l > 1) {
        usage(progName);
        throw new Exception("Invalid options");
      }
      Screen.luminous = l;
      break;
    case "-window":
      Screen.windowMode = true;
      break;
    case "-res":
      if (i >= args.length - 2) {
        usage(progName);
        throw new Exception("Invalid options");
      }
      i++;
      int w = to!int(args[i]);
      i++;
      int h = to!int(args[i]);
      Screen.screenWidth = w;
      Screen.screenHeight = h;
      break;
    case "-nosound":
      SoundManager.noSound = true;
      break;
    case "-reverse":
      (cast (Pad) input).buttonReversed = true;
      break;
    case "-accframe":
      mainLoop.accframe = 1;
      break;
    default:
      usage(progName);
      throw new Exception("Invalid options");
    }
  }
}

private string OPTIONS_INI_FILE = "options.ini";

private string[] readOptionsIniFile() {
  try {
    return Tokenizer.readFile(OPTIONS_INI_FILE, " ");
  } catch (Exception e) {
    return null;
  }
}

private void usage(string progName) {
  Logger.error
    ("Usage: " ~ progName ~ " [-brightness [0-100]] [-luminosity [0-100]] [-window] [-res x y] [-nosound]");
}
