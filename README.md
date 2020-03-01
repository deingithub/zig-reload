# zig-reload

Based around the idea of [this](https://nullprogram.com/blog/2014/12/23/), this is a proof-of-concept for code swapping using zig. Accordingly ugly.  
Depends on a POSIX libc with inotify support. To run, first start the main program with `zig build; cd zig-cache/bin; ./run`, then edit the function `do_the_thing` in libreload.zig and rebuild the project using `zig build`. If everything works out, the program will reload the library and run the new function.
