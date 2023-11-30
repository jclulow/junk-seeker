use std::{
    fs::File,
    io::Write,
    os::fd::AsRawFd,
    path::PathBuf,
    time::{Duration, Instant},
};

use anyhow::{bail, Result};
use libc::{___errno, lseek, ENXIO, SEEK_DATA};

static mut START: Option<Instant> = None;

fn log(msg: &str) {
    let msec =
        Instant::now().duration_since(unsafe { START.unwrap() }).as_millis();

    println!("[{msec:>10} ms] {msg}");
}

fn seeker(f: File) {
    /*
     * Our job in this thread is to SEEK_DATA over and over, waiting for a
     * result which does not suggest an empty file.  Unfortunately the Rust
     * File wrapper does not expose SEEK_DATA as a safe Rust interface, so
     * we'll have to do it on our own:
     */
    log("starting seeker thread");
    let mut cc = 0;
    loop {
        let off = unsafe { lseek(f.as_raw_fd(), 0, SEEK_DATA) };
        if off < 0 {
            let errno = unsafe { *___errno() };
            if errno == ENXIO {
                /*
                 * This is what we expect when there is no data in the file.
                 */
                cc += 1;
                continue;
            }

            log(&format!("seek failed with an unexpected errno {errno}"));
            std::process::exit(1);
        }

        log(&format!(
            "seek found data after {cc} calls!  offset = {off} bytes"
        ));
        std::process::exit(0);
    }
}

fn main() -> Result<()> {
    unsafe { START = Some(Instant::now()) };

    let args = std::env::args().skip(1).collect::<Vec<_>>();
    if args.len() != 1
        || args[0].is_empty()
        || args[0].chars().next().unwrap() == '-'
    {
        bail!("usage: seeker DATAFILE    (note, DATAFILE will be destroyed)");
    }

    let fp = PathBuf::from(args[0].clone());
    if let Err(e) = std::fs::remove_file(&fp) {
        if e.kind() != std::io::ErrorKind::NotFound {
            bail!("removing {fp:?}: {e}");
        }
    }

    /*
     * Create the empty file.
     */
    let mut f1 = std::fs::OpenOptions::new()
        .create_new(true)
        .create(false)
        .truncate(false)
        .read(true)
        .write(true)
        .open(&fp)?;

    /*
     * Open the file a second time, so that we have an independent file pointer
     * to give to the seeking thread.
     */
    let f2 = std::fs::File::open(&fp)?;

    /*
     * Create our seeking thread.
     */
    std::thread::Builder::new()
        .name("seeker".into())
        .spawn(move || seeker(f2))?;

    /*
     * Use the main thread to begin lazily appending to the file, one byte at a
     * time.  Stop when we get to the end of the second 128K record in the file.
     */
    let mut c = 0;
    for _ in 0..=(2 * 128 * 1024 + 1) {
        /*
         * Delay _first_ to give the seeker thread time to get moving.  Write a
         * byte every quarter second.
         */
        std::thread::sleep(Duration::from_millis(250));

        let buf = [b'A'];

        match f1.write(&buf) {
            Ok(1) => {
                /*
                 * Everything went as expected.
                 */
                log(&format!("wrote up to offset {c}"));
                c += 1;
            }
            Ok(n) => bail!("unexpected write size {n}"),
            Err(e) => bail!("write failed: {e}"),
        }
    }

    Ok(())
}
