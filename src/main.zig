const std = @import("std");
const libc = @cImport({
    @cInclude("limits.h");
    @cInclude("sys/inotify.h");
    @cInclude("dlfcn.h");
});

// type of the reloadable function
const do_the_thing_fn = fn (u64) u64;

// inotify related constants
const bufsize = @sizeOf(c_int) + @sizeOf(u32) * 3 + libc.NAME_MAX + 1;
const libname = "libreload.so\u{0}";

pub fn main() !void {
    // our persistent state
    var value: u64 = 42;

    // set up inotify
    const inotify_fd = libc.inotify_init();
    if (inotify_fd < 0) {
        return error.InotifyInitFailure;
    }
    defer std.os.close(inotify_fd);

    var inotify_wd = libc.inotify_add_watch(inotify_fd, "./zig-cache/lib", libc.IN_MOVED_TO);
    if (inotify_wd < 0) {
        return error.InotifyWatchFailure;
    }

    // set up libdl
    errdefer std.debug.warn("{s}\n", .{@ptrCast([*:0]u8, libc.dlerror())});

    var handle = libc.dlopen("libreload.so", libc.RTLD_NOW) orelse return error.DlOpenFailure;
    var c_pointer = libc.dlsym(handle, "do_the_thing") orelse return error.DlSymFailure;
    var do_the_thing = @ptrCast(do_the_thing_fn, c_pointer);

    // initial run of reloadable function
    value = do_the_thing(value);
    std.debug.warn("value after running with fourty-two: {}\n", .{value});

    var buf: [bufsize]u8 = [_]u8{0} ** bufsize;
    while (true) {
        const size = try std.os.read(inotify_fd, &buf);

        var cursor: u32 = 0;
        while (cursor < size) {
            const data = unwrap_event(buf[cursor..]);

            // ignore non-update events and events not caused by the library symlink we want
            if (data.mask & libc.IN_MOVED_TO != 0 and std.mem.eql(u8, data.name[0..libname.len], libname)) {
                std.debug.warn("Updated!\n", .{});

                if (libc.dlclose(handle) != 0) {
                    return error.DLCloseFailure;
                }
                handle = libc.dlopen("libreload.so", libc.RTLD_NOW) orelse return error.DlOpenFailure;
                c_pointer = libc.dlsym(handle, "do_the_thing") orelse return error.DlSymFailure;
                do_the_thing = @ptrCast(do_the_thing_fn, c_pointer);

                value = do_the_thing(value);

                std.debug.warn("value: {}\n", .{value});
            }

            cursor += data.memsize;
        }
    }
}

// curse you, variable sized structs.
// the returned workaround zig struct is only valid for the life-time of the data
// in the buffer it was created from.
fn unwrap_event(buf: []const u8) inotify_event {
    const wd_offset = 0;
    const mask_offset = wd_offset + @sizeOf(c_int);
    const cookie_offset = mask_offset + @sizeOf(u32);
    const len_offset = cookie_offset + @sizeOf(u32);
    const name_offset = len_offset + @sizeOf(u32);

    // the @bytesToSlice calls instead of @bitCast are a workaround for ziglang/zig#3818
    const len = @bytesToSlice(u32, buf[len_offset..name_offset])[0];
    return .{
        .wd = @bytesToSlice(c_int, buf[wd_offset..mask_offset])[0],
        .mask = @bytesToSlice(u32, buf[mask_offset..cookie_offset])[0],
        .cookie = @bytesToSlice(u32, buf[cookie_offset..len_offset])[0],
        .len = len,
        .name = buf[name_offset .. name_offset + len],
        .memsize = name_offset + len,
    };
}

const inotify_event = struct {
    wd: c_int,
    mask: u32,
    cookie: u32,
    len: u32,
    name: []const u8,
    memsize: u32,
};
