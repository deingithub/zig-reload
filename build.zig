const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();

    const lib = b.addSharedLibrary("reload", "src/libreload.zig", b.version(0, 0, 1));
    lib.install();

    const exe = b.addExecutable("run", "src/main.zig");
    exe.setBuildMode(mode);
    exe.linkSystemLibrary("c");
    exe.step.dependOn(&lib.step);

    b.addNativeSystemRPath("./zig-cache/lib");
    exe.need_system_paths = true;

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
