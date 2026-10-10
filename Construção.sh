#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
KERNEL_DIR="$ROOT/linux-7.2.9"
GRUB_DIR="$ROOT/grub-master"
ISO_OUT="$ROOT/MaiLinux.iso"
JOBS="$(nproc)"

echo "=== [1/5] Compilando o kernel Linux 7.2.9 (x86_64) ==="
make -C "$KERNEL_DIR" x86_64_defconfig
make -C "$KERNEL_DIR" olddefconfig
make -C "$KERNEL_DIR" -j"$JOBS"
test -f "$KERNEL_DIR/arch/x86/boot/bzImage"

echo "=== [2/5] Bootstrap do GRUB (autogen/autoreconf) ==="
cd "$GRUB_DIR"
if [ ! -x ./configure ]; then
    ./bootstrap
fi
if [ ! -x ./configure ]; then
    ./autogen.sh
fi

echo "=== [3/5] Compilando o GRUB (i386-pc) ==="
if [ ! -f Makefile ]; then
    ./configure --target=i386 --with-platform=pc --prefix=/usr
fi
make -j"$JOBS"
make install DESTDIR="$GRUB_DIR/dist"

GRUB_MKIMAGE="$GRUB_DIR/dist/usr/bin/grub-mkimage"
GRUB_MODS="$GRUB_DIR/dist/usr/lib/grub/i386-pc"
test -x "$GRUB_MKIMAGE"
test -d "$GRUB_MODS"

echo "=== [4/5] Montando a árvore da ISO ==="
ISO_DIR="$(mktemp -d)"
trap 'rm -rf "$ISO_DIR"' EXIT
mkdir -p "$ISO_DIR/boot/grub/i386-pc"
cp "$KERNEL_DIR/arch/x86/boot/bzImage" "$ISO_DIR/boot/vmlinuz"
cp "$GRUB_MODS"/* "$ISO_DIR/boot/grub/i386-pc/"
"$GRUB_MKIMAGE" -O i386-pc-eltorito -p /boot/grub -d "$GRUB_MODS" \
    -o "$ISO_DIR/boot/grub/i386-pc/eltorito.img" biosdisk iso9660

cat > "$ISO_DIR/boot/grub/grub.cfg" <<'EOF'
set timeout=5
set default=0

menuentry "Mai Linux" {
    echo "Carregando o kernel Mai Linux..."
    linux /boot/vmlinuz console=tty0
}
EOF

echo "=== [5/5] Gerando $ISO_OUT com genisoimage ==="
rm -f "$ISO_OUT"
genisoimage -quiet -o "$ISO_OUT" -R \
    -b boot/grub/i386-pc/eltorito.img \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -V "MaiLinux" \
    "$ISO_DIR"

echo "Concluído: $ISO_OUT"