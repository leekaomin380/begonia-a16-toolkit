#!/usr/bin/env python3
"""把 ELF 的 DT_NEEDED 条目重定向到 .dynstr 中已存在的另一个库名。

用途：让一个为旧 Android 编译的 .so 能在新 Android 上被 dlopen —— 当它依赖的
某些库已从系统中移除时。

与常见做法的区别：不改写 .dynstr 的字节内容（那会破坏相邻符号，因为字符串表是
紧凑排列的），而是只修改 DT_NEEDED 条目的 d_val，令其指向表中另一个已有字符串。
非破坏、可逆。

适用前提（重要）：仅当被重定向掉的依赖，其代码路径在运行时不会被执行时才安全。
若这些依赖的函数或数据真的会被调用，程序会在运行时崩溃，而不是加载时失败。

用法：
    elf-redirect-needed.py <input.so> <output.so> <target-lib> <missing1> [missing2 ...]
例：
    elf-redirect-needed.py in.so out.so liblog.so libhidltransport.so libvcodec_cap.so
"""
import struct, sys, shutil


def sections(d):
    e_shoff = struct.unpack('<Q', d[0x28:0x30])[0]
    ess = struct.unpack('<H', d[0x3a:0x3c])[0]
    esn = struct.unpack('<H', d[0x3c:0x3e])[0]
    shstrndx = struct.unpack('<H', d[0x3e:0x40])[0]
    for i in range(esn):
        s = d[e_shoff + i * ess: e_shoff + (i + 1) * ess]
        yield i, shstrndx, s


def locate(d):
    """返回 (.dynamic 的 offset/size, .dynstr 的 offset/size)"""
    dyn = dynstr = None
    for i, shstrndx, s in sections(d):
        sh_type = struct.unpack('<I', s[4:8])[0]
        off = struct.unpack('<Q', s[0x18:0x20])[0]
        size = struct.unpack('<Q', s[0x20:0x28])[0]
        if sh_type == 6:                      # SHT_DYNAMIC
            dyn = (off, size)
        if sh_type == 3 and i != shstrndx:    # SHT_STRTAB，排除节名表
            dynstr = (off, size)
    if dyn is None or dynstr is None:
        raise SystemExit('未找到 .dynamic 或 .dynstr —— 这可能不是动态链接的 ELF')
    return dyn, dynstr


def main(src, dst, target, missing):
    shutil.copyfile(src, dst)
    d = bytearray(open(dst, 'rb').read())
    if d[:4] != b'\x7fELF' or d[4] != 2:
        raise SystemExit('仅支持 64 位 ELF')
    (dyn_off, dyn_size), (str_off, _) = locate(d)

    def name_at(val):
        end = d.index(b'\0', str_off + val)
        return d[str_off + val: end].decode()

    entries = []
    for p in range(dyn_off, dyn_off + dyn_size, 16):
        tag, val = struct.unpack('<QQ', d[p:p + 16])
        if tag == 0:
            break
        entries.append((p, tag, val))

    target_off = next((v for _, t, v in entries if t == 1 and name_at(v) == target), None)
    if target_off is None:
        raise SystemExit(f'目标库 {target} 不在 DT_NEEDED 列表中；'
                         f'请选一个本来就被依赖的库作为重定向目标')

    missing = set(missing)
    changed = []
    for p, tag, val in entries:
        if tag == 1 and name_at(val) in missing:
            changed.append(name_at(val))
            d[p + 8:p + 16] = struct.pack('<Q', target_off)

    open(dst, 'wb').write(d)
    print(f'已重定向 {len(changed)} 条 -> {target}: {", ".join(changed) or "（无匹配）"}')
    # 从修补后的数据重新读取，确保输出反映真实结果而非修补前的快照
    after = sorted({name_at(struct.unpack('<QQ', d[p:p + 16])[1])
                    for p in range(dyn_off, dyn_off + dyn_size, 16)
                    if struct.unpack('<QQ', d[p:p + 16])[0] == 1})
    print('修补后依赖表:', ' '.join(after))


if __name__ == '__main__':
    if len(sys.argv) < 5:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:])
