const std = @import("std");
const assert = std.debug.assert;
const warn = std.debug.warn;
const eql = std.mem.eql;

const libc = @cImport({
    @cInclude("limits.h");
    @cInclude("sys/inotify.h");
    @cInclude("dlfcn.h");
});

const libreload_api_struct = @import("libreload.zig").Api;

// inotify related constants
const inotify_buf_size = @sizeOf(inotify_event) + libc.NAME_MAX + 1;
const libname = "libreload.so\u{0}";
const libpath = "../lib/libreload.so";

pub fn main() !void {
    // set up inotify
    const inotify_fd = libc.inotify_init();
    if (inotify_fd < 0) return error.InotifyInitFailure;

    const inotify_file = std.fs.File{ .handle = inotify_fd, .io_mode = std.io.mode };
    defer inotify_file.close();

    var inotify_wd = libc.inotify_add_watch(inotify_fd, "../lib", libc.IN_MOVED_TO);
    if (inotify_wd < 0) return error.InotifyWatchFailure;

    // set up libdl
    errdefer warn("{s}\n", .{@ptrCast([*:0]u8, libc.dlerror())});
    var handle = libc.dlopen(libpath, libc.RTLD_NOW) orelse return error.DlOpenFailure;
    var Api = @ptrCast(
        *libreload_api_struct,
        @alignCast(8, libc.dlsym(handle, "LIBRELOAD_API") orelse return error.DlSymFailure),
    );

    // initial run of reloadable function
    var value = Api.initialize.*();
    warn("initialized: {}\n", .{value});

    var buf: [inotify_buf_size]u8 = [_]u8{0} ** inotify_buf_size;
    var inotify_in_stream = inotify_file.inStream();
    while (true) {
        const bytes_read = try inotify_in_stream.stream.read(&buf);
        var cursor: usize = 0;

        while (cursor < bytes_read) {
            const mask_offset = cursor + @sizeOf(c_int);
            const cookie_offset = mask_offset + @sizeOf(u32);
            const len_offset = cookie_offset + @sizeOf(u32);
            const name_offset = len_offset + @sizeOf(u32);

            const event = inotify_event{
                .wd = std.mem.readIntSliceNative(c_int, buf[cursor..mask_offset]),
                .mask = std.mem.readIntSliceNative(u32, buf[mask_offset..cookie_offset]),
                .cookie = std.mem.readIntSliceNative(u32, buf[cookie_offset..len_offset]),
                .len = std.mem.readIntSliceNative(u32, buf[len_offset..name_offset]),
            };
            const filename = if (event.len > 0) buf[name_offset .. name_offset + event.len - 1 :0] else null;

            assert(event.wd == inotify_wd);
            cursor += @sizeOf(inotify_event) + event.len;

            if (event.mask & libc.IN_MOVED_TO != 0 and eql(u8, filename.?[0..libname.len], libname)) {
                if (libc.dlclose(handle) != 0) {
                    return error.DLCloseFailure;
                }
                handle = libc.dlopen(libpath, libc.RTLD_NOW) orelse return error.DlOpenFailure;
                Api = @ptrCast(
                    *libreload_api_struct,
                    @alignCast(8, libc.dlsym(handle, "LIBRELOAD_API") orelse return error.DlSymFailure),
                );

                value = Api.function.*(value);
                warn("value: {}\n", .{value});
            }
        }
    }
}

const inotify_event = extern struct {
    wd: c_int,
    mask: u32,
    cookie: u32,
    len: u32,
};
