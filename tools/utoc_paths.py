r"""List every asset path packed in the game's IoStore container.

Parses the directory index of ParadiseKiller-WindowsNoEditor.utoc (UE 4.27,
unencrypted). Asset *contents* in .ucas are compressed and not readable this
way, but names/paths are enough to find Blueprint class names for UE4SS.

Usage:
    python tools/utoc_paths.py [path\to\ParadiseKiller-WindowsNoEditor.utoc] > paths.txt
    python tools/utoc_paths.py | findstr /i goldcoin
"""
import struct
import sys

DEFAULT = r"D:\games\steamapps\common\Paradise Killer\ParadiseKiller\Content\Paks\ParadiseKiller-WindowsNoEditor.utoc"
NONE = 0xFFFFFFFF


def main():
    data = open(sys.argv[1] if len(sys.argv) > 1 else DEFAULT, "rb").read()
    # The directory index starts with the mount point FString "../../../".
    pos = data.find(b"../../../") - 4

    def u32():
        nonlocal pos
        v = struct.unpack_from("<I", data, pos)[0]
        pos += 4
        return v

    def fstring():
        nonlocal pos
        n = struct.unpack_from("<i", data, pos)[0]
        pos += 4
        if n < 0:
            s = data[pos:pos - 2 * n].decode("utf-16le")[:-1]
            pos += -2 * n
        else:
            s = data[pos:pos + n].decode("latin1")[:-1]
            pos += n
        return s

    mount = fstring()
    n = u32()
    dirs = [struct.unpack_from("<4I", data, pos + 16 * i) for i in range(n)]  # name, firstChild, nextSibling, firstFile
    pos += 16 * n
    n = u32()
    files = [struct.unpack_from("<3I", data, pos + 12 * i) for i in range(n)]  # name, nextFile, userData
    pos += 12 * n
    strings = [fstring() for _ in range(u32())]

    out = []
    stack = [(0, mount)]
    while stack:
        d, path = stack.pop()
        name, child, _, f = dirs[d]
        if name != NONE:
            path += strings[name] + "/"
        while f != NONE:
            out.append(path + strings[files[f][0]])
            f = files[f][1]
        while child != NONE:
            stack.append((child, path))
            child = dirs[child][2]

    sys.stdout.write("\n".join(sorted(out)) + "\n")


if __name__ == "__main__":
    main()
