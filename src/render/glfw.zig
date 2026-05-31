//! GLFW bindings — window creation and input handling.
//!
//! Minimal bindings for GLFW 3.x used by Freeserf.
//! Only the functions needed for the game are included.

pub const GLFWwindow = opaque {};
pub const GLFWmonitor = opaque {};

pub const GLFW_KEY_UNKNOWN: c_int = -1;
pub const GLFW_KEY_SPACE: c_int = 32;
pub const GLFW_KEY_ESCAPE: c_int = 256;
pub const GLFW_KEY_ENTER: c_int = 257;
pub const GLFW_KEY_TAB: c_int = 258;
pub const GLFW_KEY_BACKSPACE: c_int = 259;
pub const GLFW_KEY_LEFT: c_int = 263;
pub const GLFW_KEY_RIGHT: c_int = 262;
pub const GLFW_KEY_UP: c_int = 265;
pub const GLFW_KEY_DOWN: c_int = 264;
pub const GLFW_KEY_W: c_int = 87;
pub const GLFW_KEY_A: c_int = 65;
pub const GLFW_KEY_S: c_int = 83;
pub const GLFW_KEY_D: c_int = 68;
pub const GLFW_KEY_Q: c_int = 81;
pub const GLFW_KEY_E: c_int = 69;
pub const GLFW_KEY_F1: c_int = 290;
pub const GLFW_KEY_F2: c_int = 291;
pub const GLFW_KEY_F3: c_int = 292;
pub const GLFW_KEY_F4: c_int = 293;
pub const GLFW_KEY_F5: c_int = 294;
pub const GLFW_KEY_F6: c_int = 295;
pub const GLFW_KEY_F7: c_int = 296;
pub const GLFW_KEY_F8: c_int = 297;
pub const GLFW_KEY_F9: c_int = 298;
pub const GLFW_KEY_F10: c_int = 299;

pub const GLFW_PRESS: c_int = 1;
pub const GLFW_RELEASE: c_int = 0;
pub const GLFW_REPEAT: c_int = 2;

pub const GLFW_MOUSE_BUTTON_LEFT: c_int = 0;
pub const GLFW_MOUSE_BUTTON_RIGHT: c_int = 1;
pub const GLFW_MOUSE_BUTTON_MIDDLE: c_int = 2;

pub const GLFW_CURSOR: c_int = 0x00033001;
pub const GLFW_CURSOR_NORMAL: c_int = 0x00034001;
pub const GLFW_CURSOR_HIDDEN: c_int = 0x00034002;
pub const GLFW_CURSOR_DISABLED: c_int = 0x00034003;

pub const GLFW_RESIZABLE: c_int = 0x00020003;
pub const GLFW_VISIBLE: c_int = 0x00020004;
pub const GLFW_DECORATED: c_int = 0x00020005;
pub const GLFW_CONTEXT_VERSION_MAJOR: c_int = 0x00022002;
pub const GLFW_CONTEXT_VERSION_MINOR: c_int = 0x00022003;
pub const GLFW_OPENGL_PROFILE: c_int = 0x00022008;
pub const GLFW_OPENGL_CORE_PROFILE: c_int = 0x00032001;
pub const GLFW_OPENGL_COMPAT_PROFILE: c_int = 0x00032002;

pub const GLFW_TRUE: c_int = 1;
pub const GLFW_FALSE: c_int = 0;

pub const GLFWwindow_close_callback = *const fn (window: *GLFWwindow) callconv(.c) void;
pub const GLFWkeyfun = *const fn (window: *GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.c) void;
pub const GLFWmousebuttonfun = *const fn (window: *GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(.c) void;
pub const GLFWcursorposfun = *const fn (window: *GLFWwindow, xpos: f64, ypos: f64) callconv(.c) void;
pub const GLFWscrollfun = *const fn (window: *GLFWwindow, xoffset: f64, yoffset: f64) callconv(.c) void;
pub const GLFWwindowsizefun = *const fn (window: *GLFWwindow, width: c_int, height: c_int) callconv(.c) void;
pub const GLFWcharfun = *const fn (window: *GLFWwindow, codepoint: c_uint) callconv(.c) void;

pub const c = struct {
    extern "c" fn glfwInit() callconv(.c) c_int;
    extern "c" fn glfwTerminate() void;
    extern "c" fn glfwWindowHint(hint: c_int, value: c_int) void;
    extern "c" fn glfwCreateWindow(width: c_int, height: c_int, title: [*:0]const u8, monitor: ?*GLFWmonitor, share: ?*GLFWwindow) callconv(.c) ?*GLFWwindow;
    extern "c" fn glfwDestroyWindow(window: *GLFWwindow) void;
    extern "c" fn glfwMakeContextCurrent(window: *GLFWwindow) void;
    extern "c" fn glfwSwapBuffers(window: *GLFWwindow) void;
    extern "c" fn glfwPollEvents() void;
    extern "c" fn glfwWindowShouldClose(window: *GLFWwindow) callconv(.c) c_int;
    extern "c" fn glfwGetTime() callconv(.c) f64;
    extern "c" fn glfwSetWindowShouldClose(window: *GLFWwindow, value: c_int) void;
    extern "c" fn glfwGetFramebufferSize(window: *GLFWwindow, width: *c_int, height: *c_int) void;
    extern "c" fn glfwGetWindowSize(window: *GLFWwindow, width: *c_int, height: *c_int) void;
    extern "c" fn glfwSetWindowTitle(window: *GLFWwindow, title: [*:0]const u8) void;
    extern "c" fn glfwGetKey(window: *GLFWwindow, key: c_int) callconv(.c) c_int;
    extern "c" fn glfwSetKeyCallback(window: *GLFWwindow, callback: ?GLFWkeyfun) callconv(.c) ?GLFWkeyfun;
    extern "c" fn glfwSetMouseButtonCallback(window: *GLFWwindow, callback: ?GLFWmousebuttonfun) callconv(.c) ?GLFWmousebuttonfun;
    extern "c" fn glfwSetCursorPosCallback(window: *GLFWwindow, callback: ?GLFWcursorposfun) callconv(.c) ?GLFWcursorposfun;
    extern "c" fn glfwSetScrollCallback(window: *GLFWwindow, callback: ?GLFWscrollfun) callconv(.c) ?GLFWscrollfun;
    extern "c" fn glfwSetWindowSizeCallback(window: *GLFWwindow, callback: ?GLFWwindowsizefun) callconv(.c) ?GLFWwindowsizefun;
    extern "c" fn glfwSetCharCallback(window: *GLFWwindow, callback: ?GLFWcharfun) callconv(.c) ?GLFWcharfun;
    extern "c" fn glfwSetWindowCloseCallback(window: *GLFWwindow, callback: ?GLFWwindow_close_callback) callconv(.c) ?GLFWwindow_close_callback;
    extern "c" fn glfwSetInputMode(window: *GLFWwindow, mode: c_int, value: c_int) void;
    extern "c" fn glfwSwapInterval(interval: c_int) void;
};

pub fn init() bool { return c.glfwInit() != GLFW_FALSE; }
pub fn terminate() void { c.glfwTerminate(); }
pub fn windowHint(hint: c_int, value: c_int) void { c.glfwWindowHint(hint, value); }
pub fn createWindow(width: c_int, height: c_int, title: [:0]const u8) ?*GLFWwindow {
    return c.glfwCreateWindow(width, height, title.ptr, null, null);
}
pub fn destroyWindow(window: *GLFWwindow) void { c.glfwDestroyWindow(window); }
pub fn makeContextCurrent(window: *GLFWwindow) void { c.glfwMakeContextCurrent(window); }
pub fn swapBuffers(window: *GLFWwindow) void { c.glfwSwapBuffers(window); }
pub fn pollEvents() void { c.glfwPollEvents(); }
pub fn windowShouldClose(window: *GLFWwindow) bool { return c.glfwWindowShouldClose(window) != GLFW_FALSE; }
pub fn getTime() f64 { return c.glfwGetTime(); }
pub fn setWindowShouldClose(window: *GLFWwindow, value: bool) void {
    c.glfwSetWindowShouldClose(window, if (value) GLFW_TRUE else GLFW_FALSE);
}
pub fn getFramebufferSize(window: *GLFWwindow) struct { width: c_int, height: c_int } {
    var w: c_int = 0; var h: c_int = 0;
    c.glfwGetFramebufferSize(window, &w, &h);
    return .{ .width = w, .height = h };
}
pub fn getWindowSize(window: *GLFWwindow) struct { width: c_int, height: c_int } {
    var w: c_int = 0; var h: c_int = 0;
    c.glfwGetWindowSize(window, &w, &h);
    return .{ .width = w, .height = h };
}
pub fn setWindowTitle(window: *GLFWwindow, title: [:0]const u8) void { c.glfwSetWindowTitle(window, title.ptr); }
pub fn getKey(window: *GLFWwindow, key: c_int) c_int { return c.glfwGetKey(window, key); }
pub fn setKeyCallback(window: *GLFWwindow, callback: ?GLFWkeyfun) void { _ = c.glfwSetKeyCallback(window, callback); }
pub fn setMouseButtonCallback(window: *GLFWwindow, callback: ?GLFWmousebuttonfun) void { _ = c.glfwSetMouseButtonCallback(window, callback); }
pub fn setCursorPosCallback(window: *GLFWwindow, callback: ?GLFWcursorposfun) void { _ = c.glfwSetCursorPosCallback(window, callback); }
pub fn setScrollCallback(window: *GLFWwindow, callback: ?GLFWscrollfun) void { _ = c.glfwSetScrollCallback(window, callback); }
pub fn setWindowSizeCallback(window: *GLFWwindow, callback: ?GLFWwindowsizefun) void { _ = c.glfwSetWindowSizeCallback(window, callback); }
pub fn setCharCallback(window: *GLFWwindow, callback: ?GLFWcharfun) void { _ = c.glfwSetCharCallback(window, callback); }
pub fn setInputMode(window: *GLFWwindow, mode: c_int, value: c_int) void { c.glfwSetInputMode(window, mode, value); }
pub fn swapInterval(interval: c_int) void { c.glfwSwapInterval(interval); }
