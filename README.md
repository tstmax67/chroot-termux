# 🐧 Linux
Chroot setup for termux

This repo contains automated chroot setup scripts for installing distros on Android devices. These will work with **Termux** or any **root-supported terminal**.  
Easily manage, and interact with a full linux distro environment on your Android phone. Also It uses nsenter and unshare to avoid issues with mouting and unmounting android directories.


---

## 🧰 Requirements

-  [Magisk](https://github.com/topjohnwu/Magisk) or [KernelSU (KSU)](https://github.com/tiann/KernelSU)
- [Termux](https://termux.dev) or any su-supported terminal
- **Internet connection** (for fetching Debian rootfs and installing latest update)

---

## 🗂️ Overview

-  It is compatible with **Magisk** and **KSU**
-  Mounts Android’s key directories inside debian:
	  - `/data` → `/mnt/android-data`
	  - `/system` → `/mnt/android-system`
	  - Internal Storage → `/mnt/internal`
	  - External SD Card → `/mnt/ext_sdcard`
-  Interactive setup with user prompts for:
	  - Installation location  
	  - Script directory  
	  - External SD card path (if any)  
	  - Optional **Fish shell** installation  
-  Provides management scripts in specified script directory:
	  - `start-[DISTRO_NAME].sh` → Starts chroot  
	  - `stop-[DISTRO_NAME].sh` → Stops the environment and unmounts binds  
	  - `remove-[DISTRO_NAME].sh` → Cleanly removes everything  
	  - `backup-[DISTRO_NAME].sh` → Creates a tarball backup
	  - `snapshot-[DISTRO_NAME].sh` → Creates filesystem snapshots

> Note: If container is moved to a different directory then it's path variable needs to be changed in all the scripts.

---

## 🚀 Installation

#### Just run this in ur rooted terminal if you are in magisk
```sh
/data/adb/magisk/busybox wget --no-check-certificate -q "https://raw.githubusercontent.com/tstmax67/chroot-termux/refs/heads/main/setup.sh"; sh setup.sh
```
#### Or if using KSU run this
```sh
/data/adb/ksu/bin/busybox wget --no-check-certificate -q "https://raw.githubusercontent.com/tstmax67/chroot-termux/refs/heads/main/setup.sh"; sh setup.sh
```
