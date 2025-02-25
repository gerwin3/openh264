# OpenH264

This is [OpenH264](https://github.com/cisco/openh264), packaged for
[Zig](https://ziglang.org/).

## Support

| Architecture / OS | Linux | MacOS | Windows |
|-------------------|-------|-------|---------|
| x86               | ✅    | ✅    | ✅      |
| x86_64            | ✅    | ✅    | ✅      |
| arm               | ✅    | ✅    | ❌      |
| aarch64           | ✅    | ✅    | ❌      |

> [!NOTE]  
> On Windows, NASM must be installed. On Linux and macOS NASM is automatically compiled as part of the build.

| Zig version | Status |
|-------------|--------|
| 0.12.0      | ✅     |
| 0.12.1      | ✅     |
| 0.13.0      | ✅     |

## Installation

First, update your `build.zig.zon`:

```bash
zig fetch --save git+https://github.com/gerwin3/openh264.git
```

### To use the Zig-friendly bindings

Add this snippet to your `build.zig` script:

```zig
const openh264_dep = b.dependency("openh264", .{
    .target = target,
    .optimize = optimize,
});
your_compilation.root_module.addImport("openh264", openh264_dep.module("openh264"));
```

You can now import and use the `openh264` module. See the `examples` directory
for usage. This will automatically link the OpenH264 library.

### To use the raw bindings

Add this snippet to your `build.zig` script:

```zig
const openh264_dep = b.dependency("openh264", .{
    .target = target,
    .optimize = optimize,
});
your_compilation.root_module.addImport("openh264_bindings", openh264_dep.module("openh264_bindings"));
```

You can now import and use the `openh264_bindings` module. See the `examples`
directory for usage. This will automatically link the OpenH264 library.

### To use the static OpenH264 library without bindings

Add this snippet to your `build.zig` script:

```zig
const openh264_dep = b.dependency("openh264", .{
    .target = target,
    .optimize = optimize,
});
your_compilation.linkLibrary(openh264_dep.artifact("openh264"));
```

This will provide OpenH264 as a static library to `your_compilation` without the
included bindings.

## H.264 Patent Disclaimer

This project uses H.264 technology and may be subject to patent licenses. This
project deliberately only distributes source code, and thus the burden of
compyling with patent and licensing law remains with the user.

## Contribute

It should work on most platforms and architectures, but has only been tested on
Linux x86_64. If anything is broken or missing please inspect `build.zig` and
update accordingly. Use the original Meson build files as reference.
Specifically, you may want to update the `BuildConfiguration` for your platform
and architecture to ensure correct compilation of assembly code.

## License

Licensed under either of

 * Apache License, Version 2.0
   ([LICENSE-APACHE](LICENSE-APACHE) or http://www.apache.org/licenses/LICENSE-2.0)
 * MIT license
   ([LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT)

at your option.

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in the work by you, as defined in the Apache-2.0 license, shall be
dual licensed as above, without any additional terms or conditions.

## Credits

This project is made possible by:

* [Cisco's OpenH264 library](https://github.com/cisco/openh264) licensed under
  the BSD 2-Clause License. Please find the [original license](./codec/LICENSE)
  in the `codec` directory.
