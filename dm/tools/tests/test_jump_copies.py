"""Exercise the rewriter's copied-base recognition on real AArch64 instructions, without game files."""
import ast
from pathlib import Path
import re
import struct
import sys
import unittest

from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
from nso_asm import ADRP, ADDI, BLR, NOP

# patch_nso.py is a command-line program whose top level loads and rewrites an image.
# Compile its actual recognition functions without executing that driver.
tree = ast.parse((TOOLS / 'patch_nso.py').read_text())
scope = {'re': re}
exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in ('num', 'copied_base')], type_ignores=[]), str(TOOLS / 'patch_nso.py'), 'exec'), scope)


def mov(dst, src, wide=True): return (0xaa0003e0 if wide else 0x2a0003e0) | src << 16 | dst


class CopiedBase(unittest.TestCase):
    def follow(self, words, reg='x7'):
        md = Cs(CS_ARCH_ARM64, CS_MODE_ARM); md.detail = True
        ins = list(md.disasm(struct.pack('<' + 'I' * len(words), *words), 0))
        self.assertEqual(len(ins), len(words))
        return scope['copied_base'](ins, len(ins), reg)

    def base(self, reg=7): return [ADRP(reg, 0, 0x4000), ADDI(reg, reg, 0x40c)]

    def test_far_copy_through_lr(self):
        self.assertEqual(self.follow(self.base() + [mov(30, 7)] + [NOP] * 688 + [mov(7, 30)]), 0x440c)

    def test_32_bit_writers_destroy_base(self):
        for clobber in (mov(7, 0, False), 0x52800027, ADDI(7, 7, 1) & 0x7fffffff):
            with self.subTest(clobber=hex(clobber)):
                self.assertIsNone(self.follow(self.base() + [clobber, mov(30, 7), mov(7, 30)]))
        self.assertIsNone(self.follow(self.base() + [mov(30, 7), mov(30, 0, False), mov(7, 30)]))

    def test_calls_clobber_volatile_and_link_registers(self):
        for call in (0x94000000, BLR(0)):
            self.assertIsNone(self.follow(self.base() + [call]))
            self.assertIsNone(self.follow(self.base() + [mov(30, 7), call, mov(7, 30)]))
            self.assertEqual(self.follow(self.base(19) + [call, mov(7, 19)]), 0x440c)

    def test_aliases_and_unrelated_writes(self):
        self.assertEqual(self.follow(self.base(29) + [mov(7, 29)]), 0x440c)
        self.assertEqual(self.follow(self.base(30), 'lr'), 0x440c)
        self.assertEqual(self.follow(self.base() + [mov(8, 0, False)]), 0x440c)
        self.assertIsNone(self.follow(self.base() + [mov(7, 0)]))


# jump_offsets with the image it reads the table from (IMG, a global of patch_nso.py)
jscope = {'re': re, 'struct': struct}
exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in ('num', 'copied_base', 'table_base', 'check_before_copy', 'jump_offsets')], type_ignores=[]),
             str(TOOLS / 'patch_nso.py'), 'exec'), jscope)


class OffsetTable(unittest.TestCase):
    """OCTOPATH TRAVELER main+0x16769f0 (UE 4.18): cmp x22,#0x10; b.hi; adrp x18 + add x18; mov x0,x18; ldrsw x18,[x0,x22,lsl #2]; add x18,x18,x0; br x18"""
    TABLE = 0x1000

    def site(self, cmp):
        code = [cmp, 0x54000088, ADRP(18, 8, self.TABLE), ADDI(18, 18, 0), mov(0, 18),
                0xB8A00800 | 22 << 16 | 3 << 13 | 1 << 12 | 0 << 5 | 18, 0x8B000000 | 18 << 5 | 18, 0xD61F0240] + [NOP] * 17   # the cases follow the br
        img = bytearray(self.TABLE + 4 * 17)
        struct.pack_into('<' + 'I' * len(code), img, 0, *code)
        cases = [4 * (8 + i) for i in range(17)]
        struct.pack_into('<' + 'i' * 17, img, self.TABLE, *[c - self.TABLE for c in cases])
        md = Cs(CS_ARCH_ARM64, CS_MODE_ARM); md.detail = True
        ins = list(md.disasm(bytes(img[:4 * len(code)]), 0))
        self.assertEqual([i.mnemonic for i in ins[4:8]], ['mov', 'ldrsw', 'add', 'br'])
        jscope['IMG'] = img
        return ins, cases

    def test_64_bit_check_only_in_the_last_attempt(self):
        ins, cases = self.site(0xF10042DF)   # cmp x22, #0x10
        self.assertIsNone(jscope['jump_offsets'](ins, 7))
        self.assertIsNone(jscope['jump_offsets'](ins, 7, copy_first=True))
        self.assertEqual(jscope['jump_offsets'](ins, 7, copy_first=True, far_base=True), cases)

    def test_32_bit_check_unchanged(self):
        ins, cases = self.site(0x710042DF)   # cmp w22, #0x10
        self.assertEqual(jscope['jump_offsets'](ins, 7, copy_first=True, far_base=True), cases)


if __name__ == '__main__': unittest.main()
