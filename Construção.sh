#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
KERNEL_DIR="$ROOT/linux-7.2.9"
GRUB_DIR="$ROOT/grub-master"
ISO_OUT="$ROOT/MaiLinux.iso"
JOBS="$(nproc)"

echo "=== [1/6] Compilando o kernel Linux 7.2.9 (x86_64) ==="
# mailinux_defconfig ja fixa framebuffer de sistema (VBE/EFI) + console grafico em 1920x1080
make -C "$KERNEL_DIR" mailinux_defconfig
make -C "$KERNEL_DIR" olddefconfig
make -C "$KERNEL_DIR" -j"$JOBS"
test -f "$KERNEL_DIR/arch/x86/boot/bzImage"

echo "=== [2/6] Compilando o init (Rust) ==="
INIT_SRC="$ROOT/inicio/inicio.rs"
INIT_BIN="$ROOT/inicio/init"
if ! command -v rustc >/dev/null 2>&1 && [ -f "$HOME/.cargo/env" ]; then
    # shellcheck disable=SC1091
    . "$HOME/.cargo/env"
fi
if ! command -v rustc >/dev/null 2>&1; then
    echo "rustc nao encontrado. Instale com:"
    echo "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
    exit 1
fi
# binario estatico: roda sozinho dentro do initramfs, sem libs
rustc -O -C target-feature=+crt-static -o "$INIT_BIN" "$INIT_SRC"
test -x "$INIT_BIN"

echo "=== [3/6] Bootstrap do GRUB (autogen/autoreconf) ==="
cd "$GRUB_DIR"
if [ ! -x ./configure ]; then
    ./bootstrap
fi
if [ ! -x ./configure ]; then
    ./autogen.sh
fi

echo "=== [4/6] Compilando o GRUB (i386-pc) ==="
if [ ! -f Makefile ]; then
    ./configure --target=i386 --with-platform=pc --prefix=/usr
fi
make -j"$JOBS"
make install DESTDIR="$GRUB_DIR/dist"

GRUB_MKIMAGE="$GRUB_DIR/dist/usr/bin/grub-mkimage"
GRUB_MODS="$GRUB_DIR/dist/usr/lib/grub/i386-pc"
GRUB_FONT="$GRUB_DIR/dist/usr/share/grub/themes/starfield/dejavu_16.pf2"
test -x "$GRUB_MKIMAGE"
test -d "$GRUB_MODS"
test -f "$GRUB_FONT"

echo "=== [5/6] Montando a árvore da ISO ==="
ISO_DIR="$(mktemp -d)"
trap 'rm -rf "$ISO_DIR"' EXIT
mkdir -p "$ISO_DIR/boot/grub/i386-pc" "$ISO_DIR/boot/grub/fonts"
cp "$KERNEL_DIR/arch/x86/boot/bzImage" "$ISO_DIR/boot/vmlinuz"
cp "$GRUB_MODS"/* "$ISO_DIR/boot/grub/i386-pc/"
cp "$GRUB_FONT" "$ISO_DIR/boot/grub/fonts/dejavu16.pf2"

# initramfs com /init: o kernel procura por /init dentro do initrd e executa
INITRAMFS_DIR="$(mktemp -d)"
cp "$INIT_BIN" "$INITRAMFS_DIR/init"
chmod 0755 "$INITRAMFS_DIR/init"
( cd "$INITRAMFS_DIR" && find . -print0 | cpio --null --create --format=newc 2>/dev/null | gzip -9 ) > "$ISO_DIR/boot/initrd.gz"
rm -rf "$INITRAMFS_DIR"
test -s "$ISO_DIR/boot/initrd.gz"

"$GRUB_MKIMAGE" -O i386-pc-eltorito -p /boot/grub -d "$GRUB_MODS" \
    -o "$ISO_DIR/boot/grub/i386-pc/eltorito.img" \
    biosdisk iso9660 all_video gfxterm gfxterm_background videoinfo font

cat > "$ISO_DIR/boot/grub/grub.cfg" <<'EOF'
set timeout=5
set default=0

insmod all_video
insmod gfxterm

if loadfont /boot/grub/fonts/dejavu16.pf2 ; then
    set gfxmode=1920x1080x32,1920x1080,auto
    set gfxpayload=keep
    terminal_output gfxterm
fi

menuentry "Mai Linux" {
    echo "Carregando o kernel Mai Linux..."
    linux /boot/vmlinuz console=tty0 rdinit=/init
    initrd /boot/initrd.gz
}
EOF

echo "=== [6/6] Gerando $ISO_OUT com genisoimage ==="
rm -f "$ISO_OUT"
genisoimage -quiet -o "$ISO_OUT" -R \
    -b boot/grub/i386-pc/eltorito.img \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -V "MaiLinux" \
    "$ISO_DIR"

echo "Concluído: $ISO_OUT"
