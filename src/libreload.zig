export fn do_the_thing(value: u64) u64 {
    return value;
}

export fn initialize() u64 {
    return 42;
}

pub const Api = extern struct {
    initialize: @TypeOf(&initialize) = &initialize,
    function: @TypeOf(&do_the_thing) = &do_the_thing,
};

export const LIBRELOAD_API = Api{};
