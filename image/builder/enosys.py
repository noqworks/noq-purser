#!/usr/bin/python3 -I
"""Run a command with a few syscalls failing as ENOSYS (seccomp filter, inherited by children).

The proot of Debian 13 (5.1) does not translate statx, faccessat2, openat2 or fchmodat2: under
it, these would resolve paths on the build host instead of the image root. With ENOSYS, glibc
(the host's and the emulated image's) falls back to the older calls, which proot translates.
Only the standard library is used (ctypes, prctl).

    enosys.py command [args...]
"""
import ctypes
import os
import struct
import sys

AUDIT_ARCH_X86_64 = 0xC000003E
NRS = (332, 439, 437, 452)  # x86_64: statx, faccessat2, openat2, fchmodat2
ENOSYS = 38
LD_ABS, JEQ, RET = 0x20, 0x15, 0x06
ALLOW, ERRNO = 0x7FFF0000, 0x00050000

prog = [(LD_ABS, 0, 0, 4), (JEQ, 0, 5, AUDIT_ARCH_X86_64), (LD_ABS, 0, 0, 0)]
for i, nr in enumerate(NRS):
    prog.append((JEQ, len(NRS) - i, 0, nr))
prog += [(RET, 0, 0, ALLOW), (RET, 0, 0, ERRNO | ENOSYS)]
assert len(prog) == 9

if os.uname().machine != "x86_64":
    sys.exit("enosys.py: only x86_64 build hosts are supported")
raw = b"".join(struct.pack("HBBI", *ins) for ins in prog)
buf = ctypes.create_string_buffer(raw, len(raw))


class SockFprog(ctypes.Structure):
    _fields_ = [("len", ctypes.c_ushort), ("filter", ctypes.c_void_p)]


fprog = SockFprog(len(prog), ctypes.addressof(buf))
libc = ctypes.CDLL(None, use_errno=True)
PR_SET_NO_NEW_PRIVS, PR_SET_SECCOMP, SECCOMP_MODE_FILTER = 38, 22, 2
if libc.prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0:
    sys.exit("enosys.py: PR_SET_NO_NEW_PRIVS failed")
if libc.prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, ctypes.byref(fprog), 0, 0) != 0:
    sys.exit("enosys.py: seccomp filter failed: errno %d" % ctypes.get_errno())
if len(sys.argv) < 2:
    sys.exit(__doc__)
os.execvp(sys.argv[1], sys.argv[1:])
