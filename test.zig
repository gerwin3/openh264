const std = @import("std");

const openh264 = @import("openh264");

test "default full hd" {
    try test_encoder_decoder(.{
        .resolution = .{ .width = 1920, .height = 1080 },
    }, 256);
}

test "default 4k" {
    try test_encoder_decoder(.{
        .resolution = .{ .width = 3840, .height = 2160 },
    }, 128);
}

test "full hd target bitrate 1mb" {
    try test_encoder_decoder(.{
        .resolution = .{ .width = 1920, .height = 1080 },
        .target_bitrate = 10_000_000,
        .rate_control_mode = .bitrate_mode,
    }, 128);
}

test "full hd target bitrate 10mb" {
    try test_encoder_decoder(.{
        .resolution = .{ .width = 1920, .height = 1080 },
        .target_bitrate = 10_000_000,
        .rate_control_mode = .bitrate_mode,
    }, 128);
}

test "full hd idr interval 2" {
    try test_encoder_decoder(.{
        .resolution = .{ .width = 1920, .height = 1080 },
        .idr_interval = 2,
    }, 128);
}

test "full hd enable ssei and enable prefix nal adding" {
    try test_encoder_decoder(.{
        .resolution = .{ .width = 1920, .height = 1080 },
        .enable_ssei = true,
        .enable_prefix_nal_adding = true,
    }, 128);
}

const TestColor = enum {
    red,
    green,
    blue,
    pink,

    fn to_yuv(self: TestColor) [3]f32 {
        return switch (self) {
            .red => rgb2yuv(.{ 255.0, 0.0, 0.0 }),
            .green => rgb2yuv(.{ 0.0, 255.0, 0.0 }),
            .blue => rgb2yuv(.{ 0.0, 0.0, 255.0 }),
            .pink => rgb2yuv(.{ 255.0, 0.0, 255.0 }),
        };
    }

    fn from_yuv(yuv: [3]f32) ?TestColor {
        const epsilon = 5.0;
        const rgb = yuv2rgb(yuv);
        if ((255.0 - rgb[0] < epsilon) and rgb[1] < epsilon and rgb[2] < epsilon)
            return .red
        else if (rgb[0] < epsilon and (255.0 - rgb[1] < epsilon) and rgb[2] < epsilon)
            return .green
        else if (rgb[0] < epsilon and rgb[1] < epsilon and (255.0 - rgb[2] < epsilon))
            return .blue
        else if ((255.0 - rgb[0] < epsilon) and rgb[1] < epsilon and (255.0 - rgb[2] < epsilon))
            return .pink
        else
            return null;
    }
};

const TestFrame = struct {
    /// Top left
    q1: TestColor,
    /// Top right
    q2: TestColor,
    /// Bottom left
    q3: TestColor,
    /// Bottom right
    q4: TestColor,

    fn from_rotation_no(index: usize) TestFrame {
        return switch (index % 4) {
            0 => .{ .q1 = .red, .q2 = .green, .q3 = .blue, .q4 = .pink },
            1 => .{ .q1 = .green, .q2 = .blue, .q3 = .pink, .q4 = .red },
            2 => .{ .q1 = .blue, .q2 = .pink, .q3 = .red, .q4 = .green },
            3 => .{ .q1 = .pink, .q2 = .red, .q3 = .green, .q4 = .blue },
            else => unreachable,
        };
    }

    fn copy_to_frame(self: *const TestFrame, frame: *openh264.Frame) void {
        std.debug.assert(frame.dims.width % 2 == 0);
        std.debug.assert(frame.dims.height % 2 == 0);
        for (0..frame.dims.height) |y| {
            for (0..frame.dims.width) |x| {
                const top = y <= (frame.dims.height / 2);
                const left = x <= (frame.dims.width / 2);
                const color = if (top and left) self.q1 else if (top and !left) self.q2 else if (!top and left) self.q3 else if (!top and !left) self.q4 else unreachable;
                const yuv = color_bytes(color.to_yuv());
                frame.data.y[(frame.dims.width * y) + x] = yuv[0];
                if (x % 2 == 0 and y % 2 == 0) {
                    frame.data.u[((frame.dims.width / 2) * (y / 2)) + (x / 2)] = yuv[1];
                    frame.data.v[((frame.dims.width / 2) * (y / 2)) + (x / 2)] = yuv[2];
                }
            }
        }
    }

    fn expect_similar(self: *const TestFrame, frame: *const openh264.Frame) !void {
        // You will just have to believe me that this function tests whether
        // the decoded frame is the same frame as the original test frame
        // during encoding.
        const w = frame.dims.width;
        const w2 = w / 2;
        const h = frame.dims.height;
        const h2 = h / 2;
        const y_stride = frame.strides.y;
        const u_stride = frame.strides.u;
        const v_stride = frame.strides.v;
        const q1 = .{
            frame.data.y[((h / 4) * y_stride) + (w / 4)],
            frame.data.u[((h2 / 4) * u_stride) + (w2 / 4)],
            frame.data.v[((h2 / 4) * v_stride) + (w2 / 4)],
        };
        const q2 = .{
            frame.data.y[((h / 4) * y_stride) + (w / 4 * 3)],
            frame.data.u[((h2 / 4) * u_stride) + (w2 / 4 * 3)],
            frame.data.v[((h2 / 4) * v_stride) + (w2 / 4 * 3)],
        };
        const q3 = .{
            frame.data.y[((h / 4 * 3) * y_stride) + (w / 4)],
            frame.data.u[((h2 / 4 * 3) * u_stride) + (w2 / 4)],
            frame.data.v[((h2 / 4 * 3) * v_stride) + (w2 / 4)],
        };
        const q4 = .{
            frame.data.y[((h / 4 * 3) * y_stride) + (w / 4 * 3)],
            frame.data.u[((h2 / 4 * 3) * u_stride) + (w2 / 4 * 3)],
            frame.data.v[((h2 / 4 * 3) * v_stride) + (w2 / 4 * 3)],
        };
        const got_test_frame = TestFrame{
            .q1 = TestColor.from_yuv(color_f32(q1)) orelse return error.TestUnmatchedColor,
            .q2 = TestColor.from_yuv(color_f32(q2)) orelse return error.TestUnmatchedColor,
            .q3 = TestColor.from_yuv(color_f32(q3)) orelse return error.TestUnmatchedColor,
            .q4 = TestColor.from_yuv(color_f32(q4)) orelse return error.TestUnmatchedColor,
        };
        try std.testing.expectEqualDeep(self.*, got_test_frame);
    }
};

const TestFrameIterator = struct {
    const rotate_every: usize = 12;

    index: usize = 0,
    max: usize,

    fn init(max: usize) TestFrameIterator {
        return .{ .max = max };
    }

    fn reset(self: *TestFrameIterator) void {
        self.index = 0;
    }

    fn next(self: *TestFrameIterator) ?TestFrame {
        if (self.index >= self.max) return null;
        const rotation = self.index / rotate_every;
        self.index += 1;
        return TestFrame.from_rotation_no(rotation);
    }
};

const FrameData = struct { y: []u8, uv: []u8 };

fn test_encoder_decoder(encoder_options: openh264.EncoderOptions, num_frames: usize) !void {
    const allocator = std.testing.allocator;

    var encoder = try openh264.Encoder.init(encoder_options, allocator);
    defer encoder.deinit();

    const width = encoder_options.resolution.width;
    const height = encoder_options.resolution.height;
    std.debug.assert(width % 2 == 0);
    std.debug.assert(height % 2 == 0);

    var frame = try openh264.Frame.alloc(width, height, allocator);
    defer frame.free(allocator);

    var bitstream = std.ArrayList(u8).init(allocator);
    defer bitstream.deinit();
    const bitstream_writer = bitstream.writer();

    var test_frames = TestFrameIterator.init(num_frames);
    while (test_frames.next()) |test_frame| {
        test_frame.copy_to_frame(&frame);

        try encoder.encode(&frame, bitstream_writer);
    }

    test_frames.reset();

    const bitstream_buffer = bitstream.items;

    var decoder = try openh264.Decoder.init(.{}, allocator);
    defer decoder.deinit();

    var last_nal: ?usize = 0;

    const len_range = @max(bitstream_buffer.len, 4) - 4;
    for (0..len_range) |index| {
        if (std.mem.eql(u8, bitstream_buffer[index .. index + 4], &.{ 0, 0, 0, 1 })) {
            if (last_nal) |last_nal_index| {
                const nal = bitstream_buffer[last_nal_index..index];
                if (try decoder.decode(nal)) |out_frame| {
                    try test_expected_frame(&test_frames, &out_frame);
                }
                last_nal = index;
            } else {
                last_nal = 0;
            }
        }
    }

    if (last_nal) |last_nal_index| {
        const nal = bitstream_buffer[last_nal_index..];

        if (try decoder.decode(nal)) |out_frame| {
            try test_expected_frame(&test_frames, &out_frame);
        }
    }

    while (try decoder.flush()) |out_frame| {
        try test_expected_frame(&test_frames, &out_frame);
    }

    try std.testing.expectEqual(test_frames.next(), @as(?TestFrame, null));
}

fn test_expected_frame(test_frames_it: *TestFrameIterator, out_frame: *const openh264.Frame) !void {
    const expected_test_frame = test_frames_it.next() orelse return error.TestUnexpectedFrame;

    try expected_test_frame.expect_similar(out_frame);
}

fn rgb2yuv(rgb: [3]f32) [3]f32 {
    return .{
        (0.257 * rgb[0]) + (0.504 * rgb[1]) + (0.098 * rgb[2]) + 16.0,
        (-0.148 * rgb[0]) + (-0.291 * rgb[1]) + (0.439 * rgb[2]) + 128.0,
        (0.439 * rgb[0]) + (-0.368 * rgb[1]) + (-0.071 * rgb[2]) + 128.0,
    };
}

fn yuv2rgb(yuv: [3]f32) [3]f32 {
    const y = yuv[0] - 16.0;
    const u = yuv[1] - 128.0;
    const v = yuv[2] - 128.0;
    return .{
        1.164 * y + 1.596 * v,
        1.164 * y - 0.392 * u - 0.813 * v,
        1.164 * y + 2.017 * u,
    };
}

fn color_f32(color: [3]u8) [3]f32 {
    return .{
        @floatFromInt(color[0]),
        @floatFromInt(color[1]),
        @floatFromInt(color[2]),
    };
}

fn color_bytes(color: [3]f32) [3]u8 {
    return .{
        @intFromFloat(color[0]),
        @intFromFloat(color[1]),
        @intFromFloat(color[2]),
    };
}
