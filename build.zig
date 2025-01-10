const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const upstream = b.dependency("openh264", .{});

    const build_config = makeBuildConfiguration(target.result);

    // Building in debug mode breaks encoding (Illegal instruction on
    // WRITE_BE_32). For the library itself, we only support release mode.
    // Bindings and the wrapper lib will follow user optimization level.
    const lib_optimize_mode = std.builtin.OptimizeMode.ReleaseFast;

    const lib_openh264_common = addLibraryCommon(b, upstream, &build_config, target, lib_optimize_mode);

    const lib_openh264_processing = addLibraryProcessing(b, upstream, &build_config, target, lib_optimize_mode);
    lib_openh264_processing.linkLibrary(lib_openh264_common);

    const lib_openh264_encoder = addLibraryEncoder(b, upstream, &build_config, target, lib_optimize_mode);
    lib_openh264_encoder.linkLibrary(lib_openh264_common);
    lib_openh264_encoder.linkLibrary(lib_openh264_processing);

    const lib_openh264_decoder = addLibraryDecoder(b, upstream, &build_config, target, lib_optimize_mode);
    lib_openh264_decoder.linkLibrary(lib_openh264_common);

    const install_libs: [2]*std.Build.Step.Compile = .{
        lib_openh264_encoder, lib_openh264_decoder,
    };
    for (install_libs) |lib| {
        lib.installHeader(upstream.path("codec/api/wels/codec_api.h"), "codec_api.h");
        lib.installHeader(upstream.path("codec/api/wels/codec_app_def.h"), "codec_app_def.h");
        lib.installHeader(upstream.path("codec/api/wels/codec_def.h"), "codec_def.h");
        lib.installHeader(upstream.path("codec/api/wels/codec_ver.h"), "codec_ver.h");
        b.installArtifact(lib);
    }

    // Bindings

    const openh264_bindings = b.addModule("openh264_bindings", .{
        .root_source_file = b.path("openh264_bindings.zig"),
        .target = target,
        .optimize = optimize,
    });
    openh264_bindings.linkLibrary(lib_openh264_encoder);
    openh264_bindings.linkLibrary(lib_openh264_decoder);

    // Zig-friendly API

    const openh264 = b.addModule("openh264", .{
        .root_source_file = b.path("openh264.zig"),
        .target = target,
        .optimize = optimize,
    });
    openh264.addImport("openh264_bindings", openh264_bindings);

    // Encoding with raw bindings example

    const example_encode_rainbow_low_level = b.addExecutable(.{
        .name = "example_encode_rainbow_low_level",
        .root_source_file = b.path("examples/encode_rainbow_low_level.zig"),
        .target = target,
        .optimize = optimize,
    });
    example_encode_rainbow_low_level.root_module.addImport("openh264_bindings", openh264_bindings);
    b.installArtifact(example_encode_rainbow_low_level);

    // Encoding with Zig-friendly API example

    const example_encode_rainbow = b.addExecutable(.{
        .name = "example_encode_rainbow",
        .root_source_file = b.path("examples/encode_rainbow.zig"),
        .target = target,
        .optimize = optimize,
    });
    example_encode_rainbow.root_module.addImport("openh264", openh264);
    b.installArtifact(example_encode_rainbow);

    // Decoding with Zig-friendly API example

    const example_decode_rainbow = b.addExecutable(.{
        .name = "example_decode_rainbow",
        .root_source_file = b.path("examples/decode_rainbow.zig"),
        .target = target,
        .optimize = optimize,
    });
    example_decode_rainbow.root_module.addImport("openh264", openh264);
    b.installArtifact(example_decode_rainbow);
}

fn addLibraryCommon(
    b: *std.Build,
    upstream: *std.Build.Dependency,
    build_config: *const BuildConfiguration,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const obj = b.addStaticLibrary(.{
        .name = "openh264_common",
        .target = target,
        .optimize = optimize,
    });

    obj.linkLibC();
    obj.linkLibCpp();

    obj.addIncludePath(upstream.path("codec/api/wels"));
    obj.addIncludePath(upstream.path("codec/common/inc"));

    obj.addCSourceFiles(.{
        .root = upstream.path("codec/common/src"),
        .files = &.{
            "common_tables.cpp",
            "copy_mb.cpp",
            "cpu.cpp",
            "crt_util_safe_x.cpp",
            "deblocking_common.cpp",
            "expand_pic.cpp",
            "intra_pred_common.cpp",
            "mc.cpp",
            "memory_align.cpp",
            "sad_common.cpp",
            "utils.cpp",
            "welsCodecTrace.cpp",
            "WelsTaskThread.cpp",
            "WelsThread.cpp",
            "WelsThreadLib.cpp",
            "WelsThreadPool.cpp",
        },
        .flags = build_config.flags,
    });

    switch (target.result.cpu.arch) {
        .x86, .x86_64 => {
            addNasmFiles(b, upstream, obj, build_config, "codec/common/x86", &.{
                "cpuid.asm",
                "dct.asm",
                "deblock.asm",
                "expand_picture.asm",
                "intra_pred_com.asm",
                "mb_copy.asm",
                "mc_chroma.asm",
                "mc_luma.asm",
                "satd_sad.asm",
                "vaa.asm",
            });
        },
        .arm => {
            obj.addIncludePath(upstream.path("codec/common/arm"));

            obj.addCSourceFiles(.{
                .root = upstream.path("codec/common/arm"),
                .files = &.{
                    "copy_mb_neon.S",
                    "deblocking_neon.S",
                    "expand_picture_neon.S",
                    "intra_pred_common_neon.S",
                    "mc_neon.S",
                },
                .flags = build_config.flags,
            });
        },
        .aarch64 => {
            obj.addIncludePath(upstream.path("codec/common/arm64"));

            obj.addCSourceFiles(.{
                .root = upstream.path("codec/common/arm64"),
                .files = &.{
                    "copy_mb_aarch64_neon.S",
                    "deblocking_aarch64_neon.S",
                    "expand_picture_aarch64_neon.S",
                    "intra_pred_common_aarch64_neon.S",
                    "mc_aarch64_neon.S",
                },
                .flags = build_config.flags,
            });
        },
        .loongarch32, .loongarch64 => {
            obj.addIncludePath(upstream.path("codec/common/loongarch"));

            obj.addCSourceFiles(.{
                .root = upstream.path("codec/common/loongarch"),
                .files = &.{
                    "copy_mb_lsx.c",
                    "deblock_lsx.c",
                    "intra_pred_com_lsx.c",
                    "intra_pred_com_lasx.c",
                    "mc_chroma_lsx.c",
                    "mc_horver_lsx.c",
                    "satd_sad_lasx.c",
                },
                .flags = build_config.flags,
            });
        },
        else => {},
    }

    return obj;
}

fn addLibraryProcessing(
    b: *std.Build,
    upstream: *std.Build.Dependency,
    build_config: *const BuildConfiguration,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const obj = b.addStaticLibrary(.{
        .name = "openh264_processing",
        .target = target,
        .optimize = optimize,
    });

    obj.linkLibC();
    if (target.result.abi != .msvc)
        obj.linkLibCpp();

    obj.addIncludePath(upstream.path("codec/api/wels"));
    obj.addIncludePath(upstream.path("codec/common/inc"));

    obj.addIncludePath(upstream.path("codec/processing/interface"));
    obj.addIncludePath(upstream.path("codec/processing/src/common"));
    obj.addIncludePath(upstream.path("codec/processing/src/adaptivequantization"));
    obj.addIncludePath(upstream.path("codec/processing/src/downsample"));
    obj.addIncludePath(upstream.path("codec/processing/src/scrolldetection"));
    obj.addIncludePath(upstream.path("codec/processing/src/vaacalc"));

    obj.addCSourceFiles(.{
        .root = upstream.path("codec/processing/src"),
        .files = &.{
            "adaptivequantization/AdaptiveQuantization.cpp",
            "backgrounddetection/BackgroundDetection.cpp",
            "common/memory.cpp",
            "common/WelsFrameWork.cpp",
            "common/WelsFrameWorkEx.cpp",
            "complexityanalysis/ComplexityAnalysis.cpp",
            "denoise/denoise.cpp",
            "denoise/denoise_filter.cpp",
            "downsample/downsample.cpp",
            "downsample/downsamplefuncs.cpp",
            "imagerotate/imagerotate.cpp",
            "imagerotate/imagerotatefuncs.cpp",
            "scenechangedetection/SceneChangeDetection.cpp",
            "scrolldetection/ScrollDetection.cpp",
            "scrolldetection/ScrollDetectionFuncs.cpp",
            "vaacalc/vaacalcfuncs.cpp",
            "vaacalc/vaacalculation.cpp",
        },
        .flags = build_config.flags,
    });

    switch (target.result.cpu.arch) {
        .x86, .x86_64 => {
            addNasmFiles(b, upstream, obj, build_config, "codec/processing/src/x86", &.{
                "denoisefilter.asm",
                "downsample_bilinear.asm",
                "vaa.asm",
            });
        },
        .arm => {
            obj.addIncludePath(upstream.path("codec/common/arm"));

            obj.addCSourceFiles(.{
                .root = upstream.path("codec/processing/src/arm"),
                .files = &.{
                    "adaptive_quantization.S",
                    "down_sample_neon.S",
                    "pixel_sad_neon.S",
                    "vaa_calc_neon.S",
                },
                .flags = build_config.flags,
            });
        },
        .aarch64 => {
            obj.addIncludePath(upstream.path("codec/common/arm64"));

            obj.addCSourceFiles(.{
                .root = upstream.path("codec/processing/src/arm64"),
                .files = &.{
                    "adaptive_quantization_aarch64_neon.S",
                    "down_sample_aarch64_neon.S",
                    "pixel_sad_aarch64_neon.S",
                    "vaa_calc_aarch64_neon.S",
                },
                .flags = build_config.flags,
            });
        },
        .loongarch32, .loongarch64 => {
            obj.addIncludePath(upstream.path("codec/common/loongarch"));

            obj.addCSourceFiles(.{
                .root = upstream.path("codec/processing/src/loongarch"),
                .files = &.{
                    "vaa_lsx.c",
                    "vaa_lasx.c",
                },
                .flags = build_config.flags,
            });
        },
        else => {},
    }

    return obj;
}

fn addLibraryEncoder(
    b: *std.Build,
    upstream: *std.Build.Dependency,
    build_config: *const BuildConfiguration,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const obj = b.addStaticLibrary(.{
        .name = "openh264_encoder",
        .target = target,
        .optimize = optimize,
    });

    obj.linkLibC();
    obj.linkLibCpp();

    obj.addIncludePath(upstream.path("codec/api/wels"));
    obj.addIncludePath(upstream.path("codec/common/inc"));

    // NOTE: Encoder needs processing headers.
    obj.addIncludePath(upstream.path("codec/processing/interface"));
    obj.addIncludePath(upstream.path("codec/processing/src/common"));
    obj.addIncludePath(upstream.path("codec/processing/src/adaptivequantization"));
    obj.addIncludePath(upstream.path("codec/processing/src/downsample"));
    obj.addIncludePath(upstream.path("codec/processing/src/scrolldetection"));
    obj.addIncludePath(upstream.path("codec/processing/src/vaacalc"));

    obj.addIncludePath(upstream.path("codec/encoder/core/inc"));
    obj.addIncludePath(upstream.path("codec/encoder/plus/inc"));

    obj.addCSourceFiles(.{
        .root = upstream.path("codec/encoder/core/src/"),
        .files = &.{
            "au_set.cpp",
            "deblocking.cpp",
            "decode_mb_aux.cpp",
            "encode_mb_aux.cpp",
            "encoder.cpp",
            "encoder_data_tables.cpp",
            "encoder_ext.cpp",
            "get_intra_predictor.cpp",
            "md.cpp",
            "mv_pred.cpp",
            "nal_encap.cpp",
            "paraset_strategy.cpp",
            "picture_handle.cpp",
            "ratectl.cpp",
            "ref_list_mgr_svc.cpp",
            "sample.cpp",
            "set_mb_syn_cabac.cpp",
            "set_mb_syn_cavlc.cpp",
            "slice_multi_threading.cpp",
            "svc_base_layer_md.cpp",
            "svc_enc_slice_segment.cpp",
            "svc_encode_mb.cpp",
            "svc_encode_slice.cpp",
            "svc_mode_decision.cpp",
            "svc_motion_estimate.cpp",
            "svc_set_mb_syn_cabac.cpp",
            "svc_set_mb_syn_cavlc.cpp",
            "wels_preprocess.cpp",
            "wels_task_base.cpp",
            "wels_task_encoder.cpp",
            "wels_task_management.cpp",
        },
        .flags = build_config.flags,
    });
    obj.addCSourceFile(.{
        .file = upstream.path("codec/encoder/plus/src/welsEncoderExt.cpp"),
        .flags = build_config.flags,
    });

    switch (target.result.cpu.arch) {
        .x86, .x86_64 => {
            addNasmFiles(b, upstream, obj, build_config, "codec/encoder/core/x86/", &.{
                "coeff.asm",
                "dct.asm",
                "intra_pred.asm",
                "matrix_transpose.asm",
                "memzero.asm",
                "quant.asm",
                "sample_sc.asm",
                "score.asm",
            });
        },
        .arm => {
            obj.addIncludePath(upstream.path("codec/common/arm"));

            obj.addCSourceFiles(.{
                .root = upstream.path("codec/encoder/core/arm"),
                .files = &.{
                    "intra_pred_neon.S",
                    "intra_pred_sad_3_opt_neon.S",
                    "memory_neon.S",
                    "pixel_neon.S",
                    "reconstruct_neon.S",
                    "svc_motion_estimation.S",
                },
                .flags = build_config.flags,
            });
        },
        .aarch64 => {
            obj.addIncludePath(upstream.path("codec/common/arm64"));

            obj.addCSourceFiles(.{
                .root = upstream.path("codec/encoder/core/arm64"),
                .files = &.{
                    "intra_pred_aarch64_neon.S",
                    "intra_pred_sad_3_opt_aarch64_neon.S",
                    "memory_aarch64_neon.S",
                    "pixel_aarch64_neon.S",
                    "reconstruct_aarch64_neon.S",
                    "svc_motion_estimation_aarch64_neon.S",
                },
                .flags = build_config.flags,
            });
        },
        .loongarch32, .loongarch64 => {
            obj.addIncludePath(upstream.path("codec/common/loongarch"));

            obj.addCSourceFiles(.{
                .root = upstream.path("codec/encoder/core/loongarch"),
                .files = &.{
                    "quant_lsx.c",
                    "get_intra_predictor_lsx.c",
                    "dct_lasx.c",
                    "svc_motion_estimate_lsx.c",
                    "sample_lasx.c",
                },
                .flags = build_config.flags,
            });
        },
        else => {},
    }

    return obj;
}

fn addLibraryDecoder(
    b: *std.Build,
    upstream: *std.Build.Dependency,
    build_config: *const BuildConfiguration,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const obj = b.addStaticLibrary(.{
        .name = "openh264_decoder",
        .target = target,
        .optimize = optimize,
    });

    obj.linkLibC();
    obj.linkLibCpp();

    obj.addIncludePath(upstream.path("codec/api/wels"));
    obj.addIncludePath(upstream.path("codec/common/inc"));

    obj.addIncludePath(upstream.path("codec/decoder/core/inc"));
    obj.addIncludePath(upstream.path("codec/decoder/plus/inc"));

    obj.addCSourceFiles(.{
        .root = upstream.path("codec/decoder/core/src"),
        .files = &.{
            "au_parser.cpp",
            "bit_stream.cpp",
            "cabac_decoder.cpp",
            "deblocking.cpp",
            "decode_mb_aux.cpp",
            "decode_slice.cpp",
            "decoder.cpp",
            "decoder_core.cpp",
            "decoder_data_tables.cpp",
            "error_concealment.cpp",
            "fmo.cpp",
            "get_intra_predictor.cpp",
            "manage_dec_ref.cpp",
            "memmgr_nal_unit.cpp",
            "mv_pred.cpp",
            "parse_mb_syn_cabac.cpp",
            "parse_mb_syn_cavlc.cpp",
            "pic_queue.cpp",
            "rec_mb.cpp",
            "wels_decoder_thread.cpp",
        },
        .flags = build_config.flags,
    });
    obj.addCSourceFile(.{
        .file = upstream.path("codec/decoder/plus/src/welsDecoderExt.cpp"),
        .flags = build_config.flags,
    });

    switch (target.result.cpu.arch) {
        .x86, .x86_64 => {
            addNasmFiles(b, upstream, obj, build_config, "codec/decoder/core/x86", &.{
                "dct.asm",
                "intra_pred.asm",
            });
        },
        .arm => {
            obj.addIncludePath(upstream.path("codec/common/arm"));

            obj.addCSourceFiles(.{
                .root = upstream.path("codec/decoder/core/arm"),
                .files = &.{
                    "block_add_neon.S",
                    "intra_pred_neon.S",
                },
                .flags = build_config.flags,
            });
        },
        .aarch64 => {
            obj.addIncludePath(upstream.path("codec/common/arm64"));

            obj.addCSourceFiles(.{
                .root = upstream.path("codec/decoder/core/arm64"),
                .files = &.{
                    "block_add_aarch64_neon.S",
                    "intra_pred_aarch64_neon.S",
                },
                .flags = build_config.flags,
            });
        },
        .loongarch32, .loongarch64 => {
            obj.addIncludePath(upstream.path("codec/common/loongarch"));

            obj.addCSourceFiles(.{
                .root = upstream.path("codec/decoder/core/loongarch"),
                .files = &.{
                    "mb_aux_lsx.c",
                },
                .flags = build_config.flags,
            });
        },
        else => {},
    }

    return obj;
}

fn addNasmFiles(
    b: *std.Build,
    upstream: *std.Build.Dependency,
    obj: *std.Build.Step.Compile,
    build_config: *const BuildConfiguration,
    comptime asm_source_files_root: []const u8,
    comptime asm_source_files: []const []const u8,
) void {
    // For x86, x86_64 we need nasm to compile the assembly code.
    // Luckily for (most) of the other architectures clang should
    // be able to compile the assembly just fine.

    const nasm_exe: ?*std.Build.Step.Compile = if (obj.rootModuleTarget().os.tag != .windows) blk: {
        const nasm_dep = b.dependency("nasm", .{ .optimize = .ReleaseFast });
        break :blk nasm_dep.artifact("nasm");
    } else null;

    inline for (asm_source_files) |asm_source_file| {
        const asm_object_file = o_name: {
            const basename = std.fs.path.basename(asm_source_file);
            const ext = std.fs.path.extension(basename);
            break :o_name b.fmt("{s}{s}", .{ basename[0 .. basename.len - ext.len], ".o" });
        };

        const nasm_run = if (nasm_exe) |nasm_builtin| b.addRunArtifact(nasm_builtin) else b.addSystemCommand(&.{"nasm"});
        nasm_run.addArgs(&.{ "-f", build_config.nasm_format });
        nasm_run.addArg("-i");
        nasm_run.addDirectoryArg(upstream.path("codec/common/x86"));
        nasm_run.addArg("-o");
        obj.addObjectFile(nasm_run.addOutputFileArg(asm_object_file));
        nasm_run.addArgs(build_config.nasm_flags);
        nasm_run.addFileArg(upstream.path(asm_source_files_root ++ "/" ++ asm_source_file));
    }
}

const BuildConfiguration = struct {
    flags: []const []const u8,
    use_nasm: bool,
    nasm_flags: []const []const u8,
    nasm_format: []const u8,
};

fn makeBuildConfiguration(target: std.Target) BuildConfiguration {
    return switch (target.os.tag) {
        .linux => switch (target.cpu.arch) {
            .x86 => .{
                .flags = &.{ "-DHAVE_AVX2", "-DX86_ASM", "-DX86_32_ASM" },
                .use_nasm = true,
                .nasm_flags = &.{ "-DX86_32", "-DHAVE_AVX2" },
                .nasm_format = "elf",
            },
            .x86_64 => .{
                .flags = &.{ "-DHAVE_AVX2", "-DX86_ASM" },
                .use_nasm = true,
                .nasm_flags = &.{ "-DUNIX64", "-DHAVE_AVX2" },
                .nasm_format = "elf64",
            },
            .arm => .{
                .flags = &.{"-DHAVE_NEON"},
                .use_nasm = false,
                .nasm_flags = &.{},
                .nasm_format = "elf",
            },
            .aarch64 => .{
                .flags = &.{"-DHAVE_NEON_AARCH64"},
                .use_nasm = false,
                .nasm_flags = &.{},
                .nasm_format = "elf64",
            },
            // FUTURE: Adding support for longarch32, longarch64 and some other
            // architectures is relatively easy. See the original meson.build
            // file for more information:
            // https://github.com/cisco/openh264/blob/423eb2c3e47009f4e631b5e413123a003fdff1ed/meson.build#L89
            else => @panic("architecture not supported"),
        },
        .macos, .ios => switch (target.cpu.arch) {
            .x86 => .{
                .flags = &.{ "-DHAVE_AVX2", "-DX86_ASM", "-DX86_32_ASM" },
                .use_nasm = true,
                .nasm_flags = &.{ "-DX86_32", "-DHAVE_AVX2" },
                .nasm_format = "macho32",
            },
            .x86_64 => .{
                .flags = &.{ "-DHAVE_AVX2", "-DX86_ASM" },
                .use_nasm = true,
                .nasm_flags = &.{ "-DUNIX64", "-DHAVE_AVX2" },
                .nasm_format = "macho64",
            },
            .arm => .{
                .flags = &.{"-DHAVE_NEON"},
                .use_nasm = false,
                .nasm_flags = &.{},
                .nasm_format = "macho32",
            },
            .aarch64 => .{
                .flags = &.{"-DHAVE_NEON_AARCH64"},
                .use_nasm = false,
                .nasm_flags = &.{},
                .nasm_format = "macho64",
            },
            else => @panic("architecture not supported"),
        },
        .windows => switch (target.cpu.arch) {
            .x86 => .{
                .flags = &.{},
                .use_nasm = true,
                .nasm_flags = &.{ "-DPREFIX", "-DX86_32" },
                .nasm_format = "win32",
            },
            .x86_64 => .{
                .flags = &.{},
                .use_nasm = true,
                .nasm_flags = &.{"-DWIN64"},
                .nasm_format = "win64",
            },
            // FUTURE: arm and aarch64 can be added but have some complications.
            // See meson.build:
            // https://github.com/cisco/openh264/blob/423eb2c3e47009f4e631b5e413123a003fdff1ed/meson.build#L124
            // Especially arm is complicated since it needs extra preprocessing
            // for the assembly files.
            else => @panic("architecture not supported on Windows (only x86 and x86_64 are supported)"),
        },
        else => @panic("os not supported"),
    };
}
