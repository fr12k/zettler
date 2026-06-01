```
/Users/frankittermann/github/zettler/src/core/Game.zig:155:47: 0x1041fbf8b in updateBuildings (freeserf)
                    building.production_count += 1;
                                              ^
/Users/frankittermann/github/zettler/src/core/Game.zig:117:29: 0x1041fb8ff in processTick (freeserf)
        self.updateBuildings(game_tick);
                            ^
/Users/frankittermann/github/zettler/src/core/Game.zig:109:25: 0x1041fb8ab in tick (freeserf)
        self.processTick();
                        ^
/Users/frankittermann/github/zettler/src/render/app.zig:343:27: 0x1041f3443 in run (freeserf)
            self.game.tick(const_tick);
                          ^
/Users/frankittermann/github/zettler/src/main.zig:71:12: 0x1041f38ff in runGlfwDemo (freeserf)
    app.run() catch |e| {
           ^
/Users/frankittermann/github/zettler/src/main.zig:35:35: 0x1041f400f in main (freeserf)
    const app_result = runGlfwDemo(allocator);
                                  ^
/opt/homebrew/Cellar/zig/0.16.0_1/lib/zig/std/start.zig:699:88: 0x1041f43b3 in callMain (freeserf)
    if (fn_info.params[0].type.? == std.process.Init.Minimal) return wrapMain(root.main(.{
                                                                                       ^
???:?:?: 0x186bbfda3 in start (/usr/lib/dyld)
run
└─ run exe freeserf failure
error: process terminated with signal ABRT
failed command: /Users/frankittermann/github/zettler/zig-out/bin/freeserf

Build Summary: 3/5 steps succeeded (1 failed)
run transitive failure
└─ run exe freeserf failure
```