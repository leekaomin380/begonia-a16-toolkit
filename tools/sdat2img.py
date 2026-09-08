#!/usr/bin/env python3
"""把 Android BLOCK OTA 的 <part>.new.dat + <part>.transfer.list 还原成裸镜像。
用法: sdat2img.py <transfer.list> <new.dat> <out.img>"""
import sys, os

BLK = 4096

def parse_rangeset(text):
    src = [int(x) for x in text.split(',')]
    n = src[0]
    if n != len(src) - 1:
        raise ValueError(f'rangeset 元素数不符: {text}')
    return list(zip(src[1:n:2], src[2:n+1:2]))   # [(begin, end), ...] end 为开区间

def main(tl_path, dat_path, out_path):
    with open(tl_path) as f:
        lines = [l.strip() for l in f if l.strip()]
    version = int(lines[0]); total_blocks = int(lines[1])
    cmds = lines[4:] if version >= 2 else lines[2:]
    print(f'  transfer.list 版本 {version}, 总块数 {total_blocks} ({total_blocks*BLK/1e9:.2f} GB)')

    max_block = 0
    ops = []
    for line in cmds:
        parts = line.split(' ', 1)
        cmd = parts[0]
        if cmd in ('erase', 'free', 'stash'):
            continue
        if cmd not in ('new', 'zero'):
            raise ValueError(f'不支持的指令（可能是增量包）: {cmd}')
        for b, e in parse_rangeset(parts[1]):
            max_block = max(max_block, e)
            ops.append((cmd, b, e))

    written = 0
    with open(dat_path, 'rb') as dat, open(out_path, 'wb') as out:
        out.truncate(max_block * BLK)
        for cmd, b, e in ops:
            if cmd == 'zero':
                continue                      # 稀疏文件天然为 0
            out.seek(b * BLK)
            remaining = (e - b) * BLK
            while remaining:
                chunk = dat.read(min(remaining, 8 << 20))
                if not chunk:
                    raise EOFError('.dat 数据不足，包可能不完整')
                out.write(chunk); remaining -= len(chunk); written += len(chunk)
    print(f'  写出 {out_path}: {os.path.getsize(out_path)/1e9:.2f} GB (实数据 {written/1e9:.2f} GB)')

if __name__ == '__main__':
    main(*sys.argv[1:4])
