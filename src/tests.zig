const std = @import("std");
const ecs = @import("zflecs.zig");
const builtin = @import("builtin");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const print = std.log.info;

const Position = struct { x: f32, y: f32 };
const Velocity = struct { x: f32, y: f32 };
const Walking = struct {};
const Direction = enum { north, south, east, west };

test {
    std.testing.refAllDeclsRecursive(@This());
}

test "extern struct ABI compatibility" {
    @setEvalBranchQuota(50_000);
    const flecs_c = @cImport({
        @cDefine("FLECS_SANITIZE", if (builtin.mode == .Debug) "1" else {});
        @cDefine("FLECS_USE_OS_ALLOC", "1");
        @cDefine("FLECS_NO_CPP", "1");
        @cInclude("flecs.h");
    });
    inline for (comptime std.meta.declarations(@This())) |decl| {
        const ZigType = @field(@This(), decl.name);
        if (@TypeOf(ZigType) != type) {
            continue;
        }
        if (comptime std.meta.activeTag(@typeInfo(ZigType)) == .@"struct" and
            @typeInfo(ZigType).@"struct".layout == .@"extern")
        {
            const flecs_name = if (comptime std.mem.startsWith(u8, decl.name, "Ecs")) decl.name else "ecs_" ++ decl.name;

            const CType = @field(flecs_c, flecs_name);
            std.testing.expectEqual(@sizeOf(CType), @sizeOf(ZigType)) catch |err| {
                std.log.err("@sizeOf({s}) != @sizeOf({s})", .{ flecs_name, decl.name });
                return err;
            };
            comptime var i: usize = 0;
            inline for (comptime std.meta.fieldNames(CType)) |c_field_name| {
                std.testing.expectEqual(
                    @offsetOf(CType, c_field_name),
                    @offsetOf(ZigType, std.meta.fieldNames(ZigType)[i]),
                ) catch |err| {
                    std.log.err(
                        "@offsetOf({s}, {s}) != @offsetOf({s}, {s})",
                        .{ flecs_name, c_field_name, decl.name, std.meta.fieldNames(ZigType)[i] },
                    );
                    return err;
                };
                i += 1;
            }
        }
    }
}

test "zflecs.entities.basics" {
    print("\n", .{});

    const world = try ecs.init();
    defer world.fini();

    world.component(Position);
    world.tag(Walking);

    const bob = world.set_name(0, "Bob");

    _ = world.set(bob, Position, .{ .x = 10, .y = 20 });
    world.add(bob, Walking);

    const ptr = world.get(bob, Position).?;
    print("({d}, {d})\n", .{ ptr.x, ptr.y });

    _ = world.set(bob, Position, .{ .x = 10, .y = 30 });

    const alice = world.set_name(0, "Alice");
    _ = world.set(alice, Position, .{ .x = 10, .y = 50 });
    world.add(alice, Walking);
    
    const t = world.get_type(alice).?;
    const str = world.type_str(t).?;
    defer ecs.os.free(@ptrCast(@constCast(str)));
    print("[{s}]\n", .{str});

    world.remove(alice, Walking);

    {
        var it = world.each(Position);
        while (it.each_next()) {
            if (it.field(Position, 0)) |positions| {
                for (positions, it.entities()) |p, e| {
                    try std.testing.expectEqual(p.x, 10);
                    print(
                        "Term loop: {s}: ({d}, {d})\n",
                        .{ world.get_name(e).?, p.x, p.y },
                    );
                }
            }
        }
    }

    {
        var desc = ecs.query_desc_t{};
        desc.terms[0].id = ecs.id(Position);
        const query = try world.query_init(&desc);
        defer query.query_fini();
    }

    {
        const query = try world.query_init(&.{
            .terms = [_]ecs.term_t{
                .{ .id = ecs.id(Position) },
                .{ .id = ecs.id(Walking) },
            } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 2),
        });
        defer query.query_fini();

        var it = query.query_iter();
        while (it.query_next()) {
            for (it.entities()) |e| {
                print("Filter loop: {s}\n", .{world.get_name(e).?});
            }
        }
    }

    {
        const query = _: {
            var desc = ecs.query_desc_t{};
            desc.terms[0].id = ecs.id(Position);
            desc.terms[1].id = ecs.id(Walking);
            break :_ try world.query_init(&desc);
        };
        defer query.query_fini();
    }

    {
        const query = try world.query_init(&.{
            .terms = [_]ecs.term_t{
                .{ .id = ecs.id(Position) },
                .{ .id = ecs.id(Walking) },
            } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 2),
        });
        defer query.query_fini();
    }
}

fn registerComponents(world: *ecs.world_t) void {
    ecs.COMPONENT(world, *const Position);
    ecs.COMPONENT(world, ?*const Position);
}

test "zflecs.basic" {
    print("\n", .{});

    const world = try ecs.init();
    defer world.fini();

    try expect(ecs.is_fini(world) == false);

    ecs.dim(world.world_ptr, 100);

    const e0 = ecs.entity_init(world.world_ptr, &.{ .name = "aaa" });
    try expect(e0 != 0);
    try expect(ecs.is_alive(world.world_ptr, e0));
    try expect(ecs.is_valid(world.world_ptr, e0));

    const e1 = world.new_id();
    try expect(ecs.is_alive(world.world_ptr, e1));
    try expect(ecs.is_valid(world.world_ptr, e1));

    _ = ecs.clone(world.world_ptr, e1, e0, false);
    try expect(ecs.is_alive(world.world_ptr, e1));
    try expect(ecs.is_valid(world.world_ptr, e1));

    ecs.delete(world.world_ptr, e1);
    try expect(!ecs.is_alive(world.world_ptr, e1));
    try expect(!ecs.is_valid(world.world_ptr, e1));

    registerComponents(world.world_ptr);
    ecs.COMPONENT(world.world_ptr, *Position);
    ecs.COMPONENT(world.world_ptr, Position);
    ecs.COMPONENT(world.world_ptr, ?*const Position);
    ecs.COMPONENT(world.world_ptr, Direction);
    ecs.COMPONENT(world.world_ptr, f64);
    ecs.COMPONENT(world.world_ptr, u31);
    ecs.COMPONENT(world.world_ptr, u32);
    ecs.COMPONENT(world.world_ptr, f32);
    ecs.COMPONENT(world.world_ptr, f64);
    ecs.COMPONENT(world.world_ptr, i8);
    ecs.COMPONENT(world.world_ptr, ?*const i8);

    {
        const p0 = ecs.pair(ecs.id(u31), e0);
        const p1 = ecs.pair(e0, e0);
        const p2 = ecs.pair(ecs.OnUpdate, ecs.id(Direction));
        {
            const str = ecs.id_str(world.world_ptr, p0).?;
            defer ecs.os.free(str);
            print("{s}\n", .{str});
        }
        {
            const str = ecs.id_str(world.world_ptr, p1).?;
            defer ecs.os.free(str);
            print("{s}\n", .{str});
        }
        {
            const str = ecs.id_str(world.world_ptr, p2).?;
            defer ecs.os.free(str);
            print("{s}\n", .{str});
        }
    }

    const S0 = struct {
        a: f32 = 3.0,
    };
    ecs.COMPONENT(world.world_ptr, S0);

    ecs.TAG(world.world_ptr, Walking);

    const PrintIdHelper = struct {
        fn printId(in_world: *ecs.world_t, comptime T: type) void {
            const id_str = ecs.id_str(in_world, ecs.id(T)).?;
            defer ecs.os.free(id_str);

            print("{s} id: {d}\n", .{ id_str, ecs.id(T) });
        }
    };

    PrintIdHelper.printId(world.world_ptr, *const Position);
    PrintIdHelper.printId(world.world_ptr, ?*const Position);
    PrintIdHelper.printId(world.world_ptr, *Position);
    PrintIdHelper.printId(world.world_ptr, Position);
    PrintIdHelper.printId(world.world_ptr, *Direction);
    PrintIdHelper.printId(world.world_ptr, *Walking);
    PrintIdHelper.printId(world.world_ptr, *u31);

    const p: Position = .{ .x = 1.0, .y = 2.0 };
    _ = world.set( e0, *const Position, &p);
    _ = world.set( e0, ?*const Position, null);
    _ = world.set( e0, Position, .{ .x = 1.0, .y = 2.0 });
    _ = world.set( e0, Direction, .west);
    _ = world.set( e0, u31, 123);
    _ = world.set( e0, u31, 1234);
    _ = world.set( e0, u32, 987);
    _ = world.set( e0, S0, .{});

    world.add(e0, Walking);

    try expect(world.get( e0, u31).?.* == 1234);
    try expect(world.get( e0, u32).?.* == 987);
    try expect(world.get( e0, S0).?.a == 3.0);
    try expect(world.get( e0, ?*const Position).?.* == null);
    try expect(world.get( e0, *const Position).?.* == &p);
    if (world.get(e0, Position)) |pos| {
        try expect(pos.x == p.x and pos.y == p.y);
    }

    const e0_type_str = ecs.type_str(world, world.get_type(e0).?).?;
    defer ecs.os.free(@ptrCast(@constCast(e0_type_str)));

    const e0_table_str = ecs.table_str(world.world_ptr, ecs.get_table(world.world_ptr,e0).?).?;
    defer ecs.os.free(e0_table_str);

    const e0_str = ecs.entity_str(world.world_ptr, e0).?;
    defer ecs.os.free(e0_str);

    print("type str: {s}\n", .{e0_type_str});
    print("table str: {s}\n", .{e0_table_str});
    print("entity str: {s}\n", .{e0_str});

    {
        const str = world.type_str(world.get_type(ecs.id(Position)).?).?;
        defer ecs.os.free(@ptrCast(@constCast(str)));
        print("{s}\n", .{str});
    }
    {
        const str = ecs.id_str(world.world_ptr, ecs.id(Position)).?;
        defer ecs.os.free(str);
        print("{s}\n", .{str});
    }
}

const Eats = struct {};
const Apples = struct {};

fn move(it: *ecs.iter_t) callconv(.c) void {
    const p = ecs.field(it, Position, 0).?;
    const v = ecs.field(it, Velocity, 1).?;

    const type_str = ecs.table_str(it.world, it.table).?;
    print("Move entities with [{s}]\n", .{type_str});
    defer ecs.os.free(type_str);

    for (0..it.count()) |i| {
        p[i].x += v[i].x;
        p[i].y += v[i].y;
    }
}

test "zflecs.helloworld.world_ptr" {
    print("\n", .{});

    const world = try ecs.init();
    defer world.fini();

    ecs.COMPONENT(world.world_ptr, Position);
    ecs.COMPONENT(world.world_ptr, Velocity);

    ecs.TAG(world.world_ptr, Eats);
    ecs.TAG(world.world_ptr, Apples);

    {
        _ = ecs.ADD_SYSTEM_WITH_FILTERS(world.world_ptr, "move system", ecs.OnUpdate, move, &.{
            .{ .id = ecs.id(Position) },
            .{ .id = ecs.id(Velocity) },
        });
    }

    const bob = world.new_entity("Bob");
    _ = world.set(bob, Position, .{ .x = 0, .y = 0 });
    _ = world.set(bob, Velocity, .{ .x = 1, .y = 2 });
    ecs.add_pair(world.world_ptr, bob, ecs.id(Eats), ecs.id(Apples));

    _ = world.progress(0);
    _ = world.progress(0);

    const p = world.get(bob, Position).?;
    print("Bob's position is ({d}, {d})\n", .{ p.x, p.y });
}

fn move_system(positions: []Position, velocities: []const Velocity) void {
    for (positions, velocities) |*p, v| {
        p.x += v.x;
        p.y += v.y;
    }
}

//Optionally, systems can receive the components iterator (usually not necessary)
fn move_system_with_it(it: *ecs.iter_t, positions: []Position, velocities: []const Velocity) void {
    const type_str = ecs.table_str(it.world, it.table).?;
    print("Move entities with [{s}]\n", .{type_str});
    defer ecs.os.free(type_str);

    for (positions, velocities) |*p, v| {
        p.x += v.x;
        p.y += v.y;
    }
}

test "zflecs.helloworld_systemcomptime" {
    print("\n", .{});

    const world = try ecs.init();
    defer world.fini();

    ecs.COMPONENT(world.world_ptr, Position);
    ecs.COMPONENT(world.world_ptr, Velocity);

    ecs.TAG(world.world_ptr, Eats);
    ecs.TAG(world.world_ptr, Apples);

    _ = ecs.ADD_SYSTEM(world.world_ptr, "move system", ecs.OnUpdate, move_system);
    _ = ecs.ADD_SYSTEM(world.world_ptr, "move system with iterator", ecs.OnUpdate, move_system_with_it);

    const bob = world.new_entity("Bob");
    _ = world.set( bob, Position, .{ .x = 0, .y = 0 });
    _ = world.set( bob, Velocity, .{ .x = 1, .y = 2 });
    ecs.add_pair(world.world_ptr, bob, ecs.id(Eats), ecs.id(Apples));

    _ = world.progress(0);
    _ = world.progress(0);

    const p = world.get(bob, Position).?;
    print("Bob's position is ({d}, {d})\n", .{ p.x, p.y });
}

test "zflecs.try_different_alignments" {
    const world = try ecs.init();
    defer world.fini();

    const AlignmentsToTest = [_]usize{ 1, 2, 4, 8, 16 };
    inline for (AlignmentsToTest) |component_alignment| {
        const AlignedComponent = struct {
            fn Component(comptime alignment: usize) type {
                return struct { dummy: u32 align(alignment) = 0 };
            }
        };

        const Component = AlignedComponent.Component(component_alignment);

        ecs.COMPONENT(world.world_ptr, Component);
        const entity = world.new_entity("");

        _ = world.set(entity, Component, .{});
        _ = world.get(entity, Component);
    }
}

test "zflecs.pairs.tag-tag" {
    const world = try ecs.init();
    defer world.fini();

    const Slowly = struct {};
    ecs.TAG(world.world_ptr, Slowly);
    ecs.TAG(world.world_ptr, Walking);

    const entity = world.new_entity("Bob");

    _ = ecs.add_pair(world.world_ptr, entity, ecs.id(Slowly), ecs.id(Walking));
    try expect(ecs.has_pair(world.world_ptr, entity, ecs.id(Slowly), ecs.id(Walking)));

    _ = ecs.remove_pair(world.world_ptr, entity, ecs.id(Slowly), ecs.id(Walking));
    try expect(!ecs.has_pair(world.world_ptr, entity, ecs.id(Slowly), ecs.id(Walking)));
}

test "zflecs.pairs.component-tag" {
    const world = try ecs.init();
    defer world.fini();

    const Speed = u8;
    ecs.COMPONENT(world.world_ptr, Speed);
    ecs.TAG(world.world_ptr, Walking);

    const entity = world.new_entity("Bob");

    _ = ecs.set_pair(world.world_ptr, entity, ecs.id(Speed), ecs.id(Walking), Speed, 2);
    try expect(ecs.has_pair(world.world_ptr, entity, ecs.id(Speed), ecs.id(Walking)));
    try expectEqual(@as(u8, 2), ecs.get_pair(world.world_ptr, entity, ecs.id(Speed), ecs.id(Walking), Speed).?.*);

    _ = ecs.remove_pair(world.world_ptr, entity, ecs.id(Speed), ecs.id(Walking));
    try expect(!ecs.has_pair(world.world_ptr, entity, ecs.id(Speed), ecs.id(Walking)));
    try expectEqual(@as(?*const u8, null), ecs.get_pair(world.world_ptr, entity, ecs.id(Speed), ecs.id(Walking), Speed));
}

test "zflecs.pairs.delete-children" {
    const world = try ecs.init();
    defer world.fini();

    const Camera = struct { id: u8 };

    ecs.COMPONENT(world.world_ptr, Camera);

    const entity = world.new_entity("scene");

    const fps = ecs.new_w_pair(world.world_ptr, ecs.ChildOf, entity);
    _ = world.set(fps, Camera, .{ .id = 1 });
    const third_person = ecs.new_w_pair(world.world_ptr, ecs.ChildOf, entity);
    _ = world.set(third_person, Camera, .{ .id = 2 });

    var found: u8 = 0;
    var it = ecs.children(world.world_ptr, entity);
    while (ecs.children_next(&it)) {
        for (0..it.count()) |i| {
            const child_entity = it.entities()[i];
            const p: ?*const Camera = world.get(child_entity, Camera);
            try expectEqual(@as(u8, @intCast(i)), p.?.id - @as(u8, 1));
            found += 1;
        }
    }
    try expectEqual(@as(u8, 2), found);
    ecs.delete_children(world.world_ptr, entity);

    found = 0;
    it = ecs.children(world.world_ptr, entity);
    while (ecs.children_next(&it)) {
        for (0..it.count()) |_| {
            found += 1;
        }
    }
    try expectEqual(@as(u8, 0), found);
}

test "zflecs.struct-dtor-hook" {
    const world = try ecs.init();
    defer world.fini();

    const Chat = struct {
        messages: std.ArrayList([]const u8) = .{},
        pub fn dtor(self: *@This()) void {
            self.messages.deinit(std.testing.allocator);
        }
    };

    ecs.COMPONENT(world.world_ptr, Chat);
    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = struct {
            pub fn chatSystem(it: *ecs.iter_t) callconv(.c) void {
                const chat_components = ecs.field(it, Chat, 0).?;
                for (0..it.count()) |i| {
                    chat_components[i].messages.append(std.testing.allocator, "some words hi") catch @panic("whomp");
                }
            }
        }.chatSystem;
        system_desc.query.terms[0] = .{ .id = ecs.id(Chat) };
        _ = ecs.SYSTEM(world.world_ptr, "Chat system", ecs.OnUpdate, &system_desc);
    }

    const chat_entity = world.new_entity("Chat entity");
    _ = world.set(chat_entity, Chat, Chat{});

    _ = world.progress(0);

    const chat_component = world.get(chat_entity, Chat).?;
    try std.testing.expect(chat_component.messages.items.len == 1);

    // This test fails if the ".hooks = .{ .dtor = ... }" from COMPONENT is
    // commented out since the cleanup is never called to free the ArrayList
    // memory.
}

const TestModule = struct {
    pub fn import(world: *ecs.World) void {
        world.component(Position);
        world.component(Velocity);
        _ = ecs.ADD_SYSTEM(world.world_ptr, "move system", ecs.OnUpdate, move_system);
    }
};
pub fn CStyleTestModule(world: *ecs.world_t) callconv(.c) void {
    var desc = ecs.component_desc_t{ .entity = 0, .type = .{ .size = 0, .alignment = 0 } };

    _ = ecs.module_init(world, @src().fn_name, &desc);
}
test "zflecs-module" {
    const world = try ecs.init();
    defer world.fini();

    const import_entity = world.import(TestModule);
    try expect(import_entity != 0);

    const cstyle_import_entity  = world.import_c(CStyleTestModule, "CStyleTestModule");
    try expect(cstyle_import_entity != 0);

    const bob = world.new_entity("Bob");
    _ = world.set( bob, Position, .{ .x = 0, .y = 0 });
    _ = world.set( bob, Velocity, .{ .x = 1, .y = 2 });

    _ = world.progress(0);
    _ = world.progress(0);

    const p = world.get(bob, Position).?;
    print("Bob's position is ({d}, {d})\n", .{ p.x, p.y });
}
