#![allow(dead_code)]

use std::ffi::CString;
use std::fs::{self, OpenOptions};
use std::os::raw::{c_char, c_int, c_ulong, c_void};
use std::os::unix::io::AsRawFd;
use std::thread::sleep;
use std::time::Duration;

const FBIOGET_VSCREENINFO: c_ulong = 0x4600;
const FBIOGET_FSCREENINFO: c_ulong = 0x4602;
const PROT_READ: c_int = 0x1;
const PROT_WRITE: c_int = 0x2;
const MAP_SHARED: c_int = 0x1;

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct FbBitfield {
    offset: u32,
    length: u32,
    msb_right: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct FbVarScreeninfo {
    xres: u32,
    yres: u32,
    xres_virtual: u32,
    yres_virtual: u32,
    xoffset: u32,
    yoffset: u32,
    bits_per_pixel: u32,
    grayscale: u32,
    red: FbBitfield,
    green: FbBitfield,
    blue: FbBitfield,
    transp: FbBitfield,
    nonstd: u32,
    activate: u32,
    height: u32,
    width: u32,
    accel_flags: u32,
    pixclock: u32,
    left_margin: u32,
    right_margin: u32,
    upper_margin: u32,
    lower_margin: u32,
    hsync_len: u32,
    vsync_len: u32,
    sync: u32,
    vmode: u32,
    rotate: u32,
    colorspace: u32,
    reserved: [u32; 4],
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct FbFixScreeninfo {
    id: [u8; 16],
    smem_start: c_ulong,
    smem_len: u32,
    type_: u32,
    type_aux: u32,
    visual: u32,
    xpanstep: u16,
    ypanstep: u16,
    ywrapstep: u16,
    line_length: u32,
    mmio_start: c_ulong,
    mmio_len: u32,
    accel: u32,
    capabilities: u16,
    reserved: [u16; 2],
}

extern "C" {
    fn ioctl(fd: c_int, request: c_ulong, ...) -> c_int;
    fn mmap(
        addr: *mut c_void,
        length: usize,
        prot: c_int,
        flags: c_int,
        fd: c_int,
        offset: i64,
    ) -> *mut c_void;
    fn mount(
        source: *const c_char,
        target: *const c_char,
        fstype: *const c_char,
        flags: c_ulong,
        data: *const c_void,
    ) -> c_int;
}

/// Com initramfs o kernel nao monta /dev automaticamente: montamos aqui.
/// Sem devtmpfs nao existe /dev/fb0 para pintar de preto.
fn mount_fs(source: &str, target: &str, fstype: &str) {
    let source = CString::new(source).unwrap();
    let target = CString::new(target).unwrap();
    let fstype = CString::new(fstype).unwrap();
    unsafe {
        mount(
            source.as_ptr(),
            target.as_ptr(),
            fstype.as_ptr(),
            0,
            std::ptr::null(),
        );
    }
}

fn prepare_fs() {
    let _ = fs::create_dir_all("/dev");
    let _ = fs::create_dir_all("/proc");
    let _ = fs::create_dir_all("/sys");
    mount_fs("devtmpfs", "/dev", "devtmpfs");
    mount_fs("proc", "/proc", "proc");
    mount_fs("sysfs", "/sys", "sysfs");
}

/// Pinta o framebuffer primario de preto, mantendo a resolucao atual.
fn black_screen() -> std::io::Result<()> {
    // sem cursor piscando por cima da tela preta
    let _ = fs::write("/sys/class/graphics/fbcon/cursor_blink", "0");

    let fb = OpenOptions::new().read(true).write(true).open("/dev/fb0")?;
    let fd = fb.as_raw_fd();

    let mut var: FbVarScreeninfo = Default::default();
    let mut fix: FbFixScreeninfo = Default::default();
    unsafe {
        ioctl(fd, FBIOGET_VSCREENINFO, &mut var as *mut _);
        ioctl(fd, FBIOGET_FSCREENINFO, &mut fix as *mut _);
    }

    eprintln!(
        "MaiLinux init: framebuffer {}x{} @ {} bpp",
        var.xres, var.yres, var.bits_per_pixel
    );

    let len = fix.smem_len as usize;
    if len == 0 {
        return Ok(());
    }

    unsafe {
        let p = mmap(
            std::ptr::null_mut(),
            len,
            PROT_READ | PROT_WRITE,
            MAP_SHARED,
            fd,
            0,
        );
        if p.is_null() || p == usize::MAX as *mut c_void {
            return Ok(());
        }
        std::slice::from_raw_parts_mut(p as *mut u8, len).fill(0);
    }

    Ok(())
}

/// Silencia o console do kernel (so emergencias), pra nada repintar a tela.
fn quiet_console() {
    let _ = fs::write("/proc/sys/kernel/printk", "1 4 1 7\n");
}

fn main() {
    prepare_fs();

    if let Err(e) = black_screen() {
        eprintln!("MaiLinux init: {e}");
    }
    quiet_console();

    // PID 1 nunca pode terminar: mantem a tela preta pra sempre.
    loop {
        sleep(Duration::from_secs(3600));
    }
}
