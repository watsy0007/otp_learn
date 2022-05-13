const std = @import("std");
const Allocator = std.mem.Allocator;
const fs = std.fs;
const eql = std.mem.eql;
const debugInfo = std.debug.print;
const readIntBig = std.mem.readIntBig;
const ArrayList = std.ArrayList;
const StringArrayHashMap = std.StringArrayHashMap;

const allocator: std.mem.Allocator = std.heap.c_allocator;



const BeamChunk = struct {
    iff_id: []u8,
    data: []u8,
    size: u32,
};

const Beam = struct {
    atoms: *ArrayList([]u8),
    chunks: *StringArrayHashMap(BeamChunk),
};

pub fn getFilebuffer(relative_path: []const u8) ![]u8 {
    var path_buffer: [fs.MAX_PATH_BYTES]u8 = undefined;
    const path = try std.fs.realpath(relative_path, &path_buffer);
    const file = try std.fs.cwd().openFile(path, .{.mode = .read_only});
    defer file.close();

    return try file.readToEndAlloc(allocator, 4096);
}

pub fn parseHead(buf: []u8) !usize {
    debugInfo("parse BEAM File\n\nheader:\n", .{});
    if (eql(u8, buf[0..4], "FOR1")) {
        debugInfo("{0s: <10}{1s: <10} ✅\n", .{"type:", "FOR1"});
    }
    
    const beam_len = std.mem.readIntBig(u32, buf[4..8]);
    debugInfo("{s: <10}{d: <10} ✅\n", .{"length: ", beam_len});
    if (eql(u8, buf[8..12], "BEAM")) {
        debugInfo("{s: <10}{s: <10} ✅\n", .{"IFF:", "BEAM",});
    }
    debugInfo("\n\n", .{});
    return beam_len;
}

pub fn parseChunks(buf: []u8, index: u32, size: usize, beam: *const Beam) !void {
    var start = index;
    var chunk_id: []u8 = undefined;
    var chunk_size: u32 = undefined;
    var storage_size: u32 = undefined;
    
    // so ugly, because zig don't have multiple return values yet.
    // https://github.com/ziglang/zig/issues/498
    // must refactor !!!
    while (start+4 <= size) {
        // debugInfo("start {d}\n", .{start});
        chunk_id = buf[start..start+4];
        start += 4; 
        chunk_size = readIntBig(u32, buf[start..start+4][0..4]);
        start += 4;
        storage_size = (chunk_size + 3) & ~@intCast(u32, 3);
        // debugInfo("storage size: {0}|{1},{2}\n", .{storage_size, start, start + chunk_size});
        const chunk_data: []u8 = buf[start..start+chunk_size];
        start += storage_size;
        // debugInfo("now {d}\n", .{start});
        // debugInfo("chunk_id: {s}\nchunk_size: {d}\nchunk_data: {any}\n\n", .{chunk_id, chunk_size, chunk_data});
        try beam.chunks.put(chunk_id, BeamChunk{.iff_id = chunk_id, .data = chunk_data, .size = chunk_size});
    }
}

pub fn parseCode(chunk: *const BeamChunk, _: *const Beam) !void {
    // debugInfo("code: {any}", .{chunk});
    debugInfo("  head size: {d}\n", .{readIntBig(u32, chunk.data[0..4])});
    debugInfo("  version: {d}\n", .{readIntBig(u32, chunk.data[4..8])});
    debugInfo("  max opcode: {d}\n", .{readIntBig(u32, chunk.data[8..12])});
    debugInfo("  label count: {d}\n", .{readIntBig(u32, chunk.data[12..16])});
    debugInfo("  function count: {d}\n", .{readIntBig(u32, chunk.data[16..20])});
    debugInfo("  code size: {d}\n", .{chunk.data.len - 20});
}

pub fn parseAtom(chunk: *const BeamChunk, beam: *const Beam) !void {
    // debugInfo("code: {any}", .{chunk});
    const buf: []u8 = chunk.data;
    const count: u32 = readIntBig(u32, buf[0..4]);
    debugInfo("  atom count: {d}\n", .{count});

    var idx: u32 = 1;
    var buf_index: usize = 4;
    while (idx < count + 1) : (idx += 1) {
        const atom_len = readIntBig(u8, buf[buf_index..buf_index+1][0..1]);
        buf_index += 1;
        const atom = buf[buf_index..buf_index + atom_len];
        debugInfo("    atom {d}: {s}\n", .{idx, atom});
        buf_index += atom_len;
        try beam.atoms.append(atom);
    }
}
pub fn parseImpT(chunk: *const BeamChunk, beam: *const Beam) !void {
    // debugInfo("code: {any}", .{chunk});
    const buf: []u8 = chunk.data;
    const count: u32 = readIntBig(u32, buf[0..4]);
    debugInfo("  import count: {d}\n", .{count});

    var idx: u32 = 0;
    var buf_index: usize = 4;
    const atoms = beam.atoms.items;
    while (idx < count) : (idx += 1) {
        const module_atom_index: u32 = readIntBig(u32, buf[buf_index..buf_index+4][0..4]);
        buf_index += 4;
        const function_atom_index: u32 = readIntBig(u32, buf[buf_index..buf_index+4][0..4]);
        buf_index += 4;
        const arity: u32 = readIntBig(u32, buf[buf_index..buf_index+4][0..4]);
        // debugInfo("    module atom index: {d}\n    function atom index: {d}\n    arity: {d}\n", .{module_atom_index, function_atom_index, arity});
        const module = atoms[module_atom_index - 1];
        const func = atoms[function_atom_index - 1];
        debugInfo("    {0s}:{1s}/{2d}\n", .{module, func, arity});
        buf_index += 4;
    }
}

pub fn parseExpT(chunk: *const BeamChunk, beam: *const Beam) !void {
    // debugInfo("code: {any}", .{chunk});
    const buf: []u8 = chunk.data;
    const count: u32 = readIntBig(u32, buf[0..4]);
    debugInfo("  export count: {d}\n", .{count});

    var idx: u32 = 0;
    var buf_index: usize = 4;
    const atoms = beam.atoms.items;
    while (idx < count) : (idx += 1) {
        const atom_index: u32 = readIntBig(u32, buf[buf_index..buf_index+4][0..4]);
        buf_index += 4;
        const arity: u32 = readIntBig(u32, buf[buf_index..buf_index+4][0..4]);
        buf_index += 4;
        const label: u32 = readIntBig(u32, buf[buf_index..buf_index+4][0..4]);
        const func = atoms[atom_index - 1];
        debugInfo("    function: {0s}/{1d} -> label: {2d}\n", .{func, arity, label});
        buf_index += 4;
    }
}

pub fn parseFunT(chunk: *const BeamChunk, _: *const Beam) !void {
    debugInfo("function: {any}", .{chunk});
    const buf: []u8 = chunk.data;
    const count: u32 = readIntBig(u32, buf[0..4]);
    debugInfo("  lambda count: {d}\n", .{count});

    // TODO mock data
}

pub fn parseLitT(chunk: *const BeamChunk, _: *const Beam) !void {
    debugInfo("literal: {any}", .{chunk});
    const buf: []u8 = chunk.data;
    const count: u32 = readIntBig(u32, buf[0..4]);
    debugInfo("  lambda count: {d}\n", .{count});

    // TODO mock data
}

pub fn parseLine(chunk: *const BeamChunk, _: *const Beam) !void {
    // debugInfo("line: {any}", .{chunk});
    const buf: []u8 = chunk.data;
    const version: u32 = readIntBig(u32, buf[0..4]);
    debugInfo("  version (must equal 0): {d}\n", .{version});

    const flags: u32 = readIntBig(u32, buf[4..8]);
    const instr_count: u32 = readIntBig(u32, buf[8..12]);
    const item_count: u32 = readIntBig(u32, buf[12..16]);
    const name_count: u32 = readIntBig(u32, buf[16..20]);
    debugInfo("  flags:{d}\n  instr count:{d}\n  item count:{d}\n  name count:{d}\n", .{flags, instr_count, item_count, name_count});

    // TODO mock data
}

pub fn parseType(chunk: *const BeamChunk, _: *const Beam) !void {
    debugInfo("type: {any}", .{chunk});
    const buf: []u8 = chunk.data;
    const count: u32 = readIntBig(u32, buf[0..4]);
    debugInfo("  version: {d}\n", .{count});

    // TODO mock data
}

pub fn main() !void {
    const buf = try getFilebuffer("./src/add.beam");
    defer allocator.free(buf);

    const beam_len = try parseHead(buf);    
    debugInfo("parse chunks\n\n", .{});


    var chunks = StringArrayHashMap(BeamChunk).init(allocator);
    defer chunks.deinit();

    var atoms = ArrayList([]u8).init(allocator);
    defer atoms.deinit();

    const beam = Beam{.chunks = &chunks, .atoms = &atoms};
    debugInfo("deams:{any}\n", .{beam});

    try parseChunks(buf, 12, beam_len, &beam);

    var it = beam.chunks.iterator();
    while (it.next()) |entry| {
        debugInfo("chunk: {s}, size: {d}\n", .{entry.key_ptr.*, entry.value_ptr.*.size});
    }
    
    
    if (chunks.get("Code")) |*val| { 
        debugInfo("\nparse code\n", .{});
        try parseCode(val, &beam); 
    }
    
    if (chunks.get("AtU8")) |*val| {
        debugInfo("\nparse atoms\n", .{});
        try parseAtom(val, &beam); 
    }
    
    if (chunks.get("ImpT")) |*val| { 
        debugInfo("\nparse imports\n", .{});
        try parseImpT(val, &beam); 
    }

    if (chunks.get("ExpT")) |*val| {
        debugInfo("\nparse exports\n", .{});
        try parseExpT(val, &beam);
    }
    
    if (chunks.get("LocT")) |*val| {
        debugInfo("\nparse locals\n", .{});
        try parseExpT(val, &beam); 
    }
    
    if (chunks.get("FunT")) |*val| { 
        debugInfo("\nparse lambdas\n", .{});
        try parseFunT(val, &beam); 
    }

    if (chunks.get("LitT")) |*val| { 
        debugInfo("\nparse literal\n", .{});
        try parseLitT(val, &beam); 
    }

    if (chunks.get("Line")) |*val| { 
        debugInfo("\nparse line\n", .{});
        try parseLine(val, &beam); 
    }

    if (chunks.get("Type")) |*val| { 
        debugInfo("\nparse type\n", .{});
        try parseType(val, &beam); 
    }
}
