#!/system/bin/sh

# exit on error
set -e
unset LD_PRELOAD

clear_screen() {
  echo -e "\033c"
}

# checking busybox
if test -x /data/adb/magisk/busybox; then
	BB=/data/adb/magisk/busybox
elif test -x /data/adb/ksu/bin/busybox; then
	BB=/data/adb/ksu/bin/busybox
else
	echo "busybox not found or not executable. Check magisk/ksu installation." >&2
	exit 1
fi


# checking container path
clear_screen
echo "Enter a location to install debian or press enter to use /data/local as default"
echo -n "> "
read installation_path
if test -z "$installation_path"; then
	installation_path="/data/local"
else
	if ! test -d "$installation_path"; then
		echo "Invalid directory." >&2
		exit 1
	fi
fi
echo "Enter a name for debian container folder or press enter to use 'debianSid' as default"
echo -n "> "
read container_dirname
if test -z "$container_dirname"; then
	container_dirname="debianSid"
fi


container_path=$(realpath "$installation_path/$container_dirname")
if ! test -d "$container_path"; then
  mkdir -p "$container_path"
fi
p="$container_path/rootfs"
mkdir -p "$p"


# checking if already installed
if test -f "$container_path/.setup_completed"; then
  echo "Debian sid already installed in $container_path/" >&2
  exit 1
else

  # creating seperate namespace for container management
  if ! test -f "$container_path/.pid"; then
    echo "$BB nohup sleep 8648398 > /dev/null 2>&1 &
    echo -n \$! > $container_path/.pid" | $BB unshare -m --propagation private -- sh
  else
    container_namespace_pid=$(cat "$container_path/.pid")
    if ! test -d "/proc/$container_namespace_pid"; then
      echo "$BB nohup sleep 8648398 > /dev/null 2>&1 &
      echo -n \$! > $container_path/.pid" | $BB unshare -m --propagation private -- sh
    fi
  fi
  container_namespace_pid=$(cat "$container_path/.pid")
  nBB="$BB nsenter -m -t $container_namespace_pid -- $BB"


  # starter configs check
  prompt_cfg_and_temporarily_save() {
    echo "Enter a location for scripts or press enter to use '$container_path' as default"
    echo -n "> "
    read scripts_path
    if test -z "$scripts_path"; then
      scripts_path="$container_path"
    else
      if ! test -d "$scripts_path"; then
        echo "Invalid directory." >&2
        exit 1
      fi
    fi
    scripts_path=$(realpath "$scripts_path")

    echo "Enter your usesrname or press enter to select 'tst'"
    echo -n "> "
    read user
    if test -z "$user"; then
      user=tst
    else
      if ! echo "$user" | grep -Eq "^[a-z][-a-z0-9_]+$"; then
        echo "Invalid username" >&2
        exit 1
      fi	
    fi

    echo "Enter a password for $user or press enter to use default '1234'"
    echo -n "> "
    read password_main_user
    if test -z "$password_main_user"; then
      password_main_user="1234"
    fi
    echo "Enter password for root or press enter to use default '1234'"
    echo -n "> "
    read password_root
    if test -z "$password_root"; then
      password_root="1234"
    fi

    echo "Enter external sdcard path if have any"
    echo -n "> "
    read ext_sdcard_path
    if ! test -z "$ext_sdcard_path"; then
      if ! test -d "$ext_sdcard_path"; then
        echo "Invalid directory." >&2
        exit 1
      fi
    fi
    
    echo "Use fish shell? Press 'y' to use confirm or press any other key to use default bash shell"
    echo -n "> "
    read -n 1 useFishShell
    echo
    
    echo "$scripts_path $user $password_main_user $password_root $ext_sdcard_path $useFishShell" > $container_path/.prompt_complete
  }

  if test -f "$container_path/.prompt_complete"; then
    echo "old setup config found."
    
    # retriving old configs
    scripts_path_old=$(cat "$container_path/.prompt_complete" | awk '{print $1}')
    user_old=$(cat "$container_path/.prompt_complete" | awk '{print $2}')
    password_main_user_old=$(cat "$container_path/.prompt_complete" | awk '{print $3}')
    password_root_old=$(cat "$container_path/.prompt_complete" | awk '{print $4}')
    ext_sdcard_path_old=$(cat "$container_path/.prompt_complete" | awk '{print $5}')
    useFishShell_old=$(cat "$container_path/.prompt_complete" | awk '{print $6}')
    
    echo "script path: $scripts_path_old"
    echo "user: $user_old"
    echo "user password: $password_main_user_old"
    echo "root password: $password_root_old"
    echo "external sdcard path: $ext_sdcard_path_old"
    echo "use fish: $useFishShell_old"
    echo "Use it?"
    echo "press n to ignore and create new config or press any other key to use it"
    echo -n "> "
    read -n 1 useOldCfg
    echo

    if test "$useOldCfg" == 'n'; then
      prompt_cfg_and_temporarily_save
    elif test -z "$useOldCfg"; then
      scripts_path="$scripts_path_old"
      user="$user_old"
      password_main_user="$password_main_user_old"
      password_root="$password_root_old"
      ext_sdcard_path="$ext_sdcard_path_old"
      useFishShell="$useFishShell_old"
    else
      echo "Wrong option" >&2
      exit 1
    fi
  else
    prompt_cfg_and_temporarily_save
  fi


  # Downloading and extracting rootfs
  cd "$container_path"
  echo -e "\nDownloading rootfs..."
  rm -rf debian-sid.tar.gz
  $BB wget --no-check-certificate -q -O bindfs "https://raw.githubusercontent.com/tstmax67/debian-sid-chroot-termux/main/bindfs"
  chmod +x bindfs
  $BB wget --no-check-certificate -q "https://github.com/tstmax67/debian-sid-chroot-termux/releases/download/Debian/debian-sid.tar.gz"
  echo "Downloading completed"
  echo "Installing Debian Sid"


  if ! test -f "$container_path/.extract-complete"; then
    $BB tar xzpf 'debian-sid.tar.gz' -C $p --numeric-owner
    touch "$container_path/.extract-complete"
  fi

  # creating directory for snapshots
  mkdir -p "$container_path/snapshot"
  snap_dir="$container_path/snapshot"

  # setting up exit function for unmounting pseudo files systems
  unmount_on_exit() {
    mnt=$($BB readlink /proc/"$container_namespace_pid/ns/mnt")
    for pid in /proc/[0-9]*; do
      ns=$($BB readlink "$pid/ns/mnt" || true)
      if test "$ns" == "$mnt"; then
        $BB kill -9 "$(echo $pid | cut -c 7-)" 2>/dev/null
      fi
    done
    rm -rf "$container_path/.pid"
  }
  trap 'unmount_on_exit' INT EXIT

  # Mounting necessary filesystems
  $nBB mount -o remount,dev,suid /data
  if ! $nBB mount | $BB grep -q $p/dev; then
    $nBB mount --rbind /dev $p/dev
  fi
  if ! $nBB mount | $BB grep -q $p/sys; then
    $nBB mount --rbind /sys $p/sys
  fi
  if ! $nBB mount | $BB grep -q $p/proc; then
    $nBB mount --rbind /proc $p/proc
  fi
  if ! $nBB mount | $BB grep -q $p/dev/pts; then
    $nBB mount -t devpts devpts $p/dev/pts
  fi

  if ! $nBB mount | $BB grep -q $p/dev/shm; then
    $nBB mkdir -p $p/dev/shm
    $nBB mount -t tmpfs tmpfs $p/dev/shm
  fi

  # setting up internals
  if ! test -f "$container_path/.int_setup"; then
    PATH=/usr/bin/:/usr/sbin/ $nBB chroot $p usr/bin/bash -c '
      echo "nameserver 8.8.8.8" > /etc/resolv.conf
      echo "127.0.0.1 localhost" >> /etc/hosts
      groupadd -g 3003 aid_inet
      groupadd -g 3004 aid_net_raw
      groupadd -g 1003 aid_graphics
      usermod -g 3003 -G 3003,3004 -a _apt
      usermod -G 3003 -a root
      groupadd storage
      
      echo "XDG_RUNTIME_DIR=/tmp/runtime" >> /etc/environment
      echo "TMPDIR=/tmp" >> /etc/environment
      mkdir -p /tmp/runtime
      chmod 700 /tmp/runtime
      sed -i "s/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/" /etc/locale.gen
      locale-gen
    '
    touch "$container_path/.int_setup"
  fi
  PATH=/usr/bin/:/usr/sbin/ $nBB chroot $p usr/bin/bash -c '
    apt update
    apt upgrade -y
    apt install sudo -y
  '



  # creating new user
  echo -e "\033c"
  if ! test -f "$container_path/.new_user"; then
    if test "$useFishShell" == "y"; then
      PATH=/usr/bin/:/usr/sbin/ $nBB chroot $p usr/bin/bash -c "
        apt install fish -y
        useradd -m -g users -G sudo,audio,video,storage,aid_inet -s /usr/bin/fish $user
      "
    else
      PATH=/usr/bin/:/usr/sbin/ $nBB chroot $p useradd -m -g users -G sudo,audio,video,storage,aid_inet -s /usr/bin/bash $user
    fi
    echo "$password_main_user" | PATH=/usr/bin/:/usr/sbin/ $nBB chroot $p passwd --stdin $user
    echo "$password_root" | PATH=/usr/bin/:/usr/sbin/ $nBB chroot $p passwd --stdin
    touch "$container_path/.new_user"
  fi
  touch "$container_path/.setup_completed"
  rm -rf "$container_path/.prompt_complete"
  rm -rf "$container_path/.int_setup"
  rm -rf "$container_path/.new_user"
  rm -rf "$container_path/.extract-complete"
  rm -rf "$container_path/debian-sid.tar.gz"
fi





















# making variables for common commands
at_start="#!/system/bin/sh

set -e
unset LD_PRELOAD

# checking busybox
if test -x /data/adb/magisk/busybox; then
	BB=/data/adb/magisk/busybox
elif test -x /data/adb/ksu/bin/busybox; then
	BB=/data/adb/ksu/bin/busybox
else
	echo 'busybox not found or not executable. Check magisk/ksu installation.' >&2
	exit 1
fi"

kill_debian_func='# getting pid of seperate mount namespace program
if test -f $container_path/.pid; then
  container_namespace_pid=$(cat $container_path/.pid)
  if test -d /proc/$container_namespace_pid; then
    mnt=$($BB readlink /proc/$container_namespace_pid/ns/mnt)
    for pid in /proc/[0-9]*; do
      ns=$($BB readlink $pid/ns/mnt || true)
      if test "$ns" == "$mnt"; then
        $BB kill -9 "$(echo $pid | $BB cut -c 7-)" 2>/dev/null
      fi
    done
  fi
  
  rm -rf $container_path/.pid
fi'










# creating start script
cat << EOF > "$scripts_path/start_debian.sh"
$at_start

#Path of DEBIAN rootfs
p='$p'
ext_sdcard_path='$ext_sdcard_path'
container_path='$container_path'


# creating seperate namespace for container management
if ! test -f \$container_path/.pid; then
  echo "\$BB nohup sleep 8648398 > /dev/null 2>&1 &
  echo -n \\\$! > \$container_path/.pid" | \$BB unshare -m --propagation private -- sh
else
  container_namespace_pid=\$(cat \$container_path/.pid)
  if ! test -d /proc/\$container_namespace_pid; then
    echo "\$BB nohup sleep 8648398 > /dev/null 2>&1 &
    echo -n \\\$! > \$container_path/.pid" | \$BB unshare -m --propagation private -- sh
  fi
fi
container_namespace_pid=\$(cat \$container_path/.pid)
nBB="\$BB nsenter -m -t \$container_namespace_pid -- \$BB"
n="\$BB nsenter -m -t \$container_namespace_pid --"

# Fix setuid issue
\$nBB mount -o remount,dev,suid /data

# mounding necessary pseudo file systems
if ! \$nBB mount | \$BB grep -q \$p/dev; then
  \$nBB mount --rbind /dev \$p/dev
fi
if ! \$nBB mount | \$BB grep -q \$p/sys; then
  \$nBB mount --rbind /sys \$p/sys
fi
if ! \$nBB mount | \$BB grep -q \$p/proc; then
  \$nBB mount --rbind /proc \$p/proc
fi
if ! \$nBB mount | \$BB grep -q \$p/dev/pts; then
  \$nBB mount -t devpts devpts \$p/dev/pts
fi

# /dev/shm for Electron apps
if ! \$nBB mount | \$BB grep -q \$p/dev/shm; then
  \$nBB mkdir -p \$p/dev/shm
  \$nBB mount -t tmpfs tmpfs \$p/dev/shm
fi

if ! \$nBB mount | \$BB grep -q \$p/mnt/internal; then
  mkdir -p \$p/mnt/internal
  \$n $container_path/bindfs --force-user=1000 --create-for-user=1000 --force-group=100 --create-for-group=100 --chmod-allow-x /data/media/0 \$p/mnt/internal
fi

if ! test -z \$ext_sdcard_path; then
  if ! \$nBB mount | \$BB grep -q \$p/mnt/ext_sdcard; then
    mkdir -p \$p/mnt/ext_sdcard
    \$n $container_path/bindfs --force-user=1000 --create-for-user=1000 --force-group=100 --create-for-group=100 --chmod-allow-x "\$ext_sdcard_path" \$p/mnt/ext_sdcard
  fi
fi

if ! \$nBB mount | \$BB grep -q \$p/mnt/android-data; then
  mkdir -p \$p/mnt/android-data
  \$n $container_path/bindfs --force-user=1000 --create-for-user=1000 --force-group=100 --create-for-group=100 --chmod-allow-x /data/ \$p/mnt/android-data
fi

if ! \$nBB mount | \$BB grep -q \$p/mnt/android-system; then
  mkdir -p \$p/mnt/android-system
  \$n $container_path/bindfs --force-user=1000 --create-for-user=1000 --force-group=100 --create-for-group=100 /system \$p/mnt/android-system
fi

# entering chroot
PATH=/usr/bin/:/usr/sbin/ \$nBB chroot \$p usr/bin/bash -c '
  if ! test -d /tmp/runtime; then
    mkdir -p /tmp/runtime
  fi
  if test "\$(stat -c "%a" /tmp/runtime)" != "700"; then
    chmod 700 /tmp/runtime
  fi
  bin/su - $user
'
EOF
chmod +x "$scripts_path/start_debian.sh"
























# creating stop script
cat << EOF > "$scripts_path/stop_debian.sh"
$at_start

#Path of DEBIAN rootfs
p='$p'
container_path='$container_path'

$kill_debian_func
echo -e "\nDebian Sid stopped"
EOF
chmod +x "$scripts_path/stop_debian.sh"



















# creating remove script
cat << EOF > "$scripts_path/remove_debian.sh"
$at_start

#Path of DEBIAN rootfs
p='$p'
container_path='$container_path'

$kill_debian_func
rm -rf \$container_path
echo -e "\nDebian Sid removed"
EOF
chmod +x "$scripts_path/remove_debian.sh"





















# creating backup script
cat << EOF > "$scripts_path/backup_debian.sh"
$at_start

#Path of DEBIAN rootfs
p='$p'
installation_path='$installation_path'
container_dirname='$container_dirname'
container_path='$container_path'

echo "Enter a directory path to store the backup or press enter to select current directory"
echo -n "> "
read backup_dir
if test -z \$backup_dir; then
  backup_dir="./"
fi
backup_dir=\$(realpath \$backup_dir)
if ! test -d \$backup_dir; then
  echo "Invalid directory path"
  exit 1
fi


$kill_debian_func

echo "Creating backup..."
\$BB tar czpf \$backup_dir/debian_backup.tar.gz -C \$installation_path \$container_dirname --numeric-owner
echo -e "\nBackup created successfully"
EOF
chmod +x "$scripts_path/backup_debian.sh"




















# creating snapshot script
cat << EOF > "$scripts_path/snapshot_debian.sh"
$at_start

#Path of DEBIAN rootfs
p='$p'
snap_dir='$snap_dir'
container_path='$container_path'


echo "Press 1 or 2"
echo "1) create a snapshot"
echo "2) restore from a snapshot"
echo -n "> "
read -n 1 choice
echo -e "\n"


stop_debian() {
  $kill_debian_func
}

if test "\$choice" -eq 1; then
  echo "Creating snapshot..."
  echo "Shutting container before creating snapshot..."
  stop_debian
  \$BB tar czpf \$snap_dir/snap-\$(date "+%S%M%H%Y%m%d").tar.gz -C \$p . --numeric-owner
  echo "Snapshot created successfully"

elif test "\$choice" -eq 2; then
  echo "choose a snapshot to restore"
  count=1
  for snap in \$(ls -1 \$snap_dir/snap-*.tar.gz); do
    echo "\$count) \$(basename -s '.tar.gz' \$snap)"
    ((count++))
  done
  echo -n "> "
  read numb
  
  sel_snap=\$(ls -1 \$snap_dir/snap-*.tar.gz | awk "NR==\$numb")
  echo "Restoring snapshot..."
  echo "Shutting container before restoring snapshot..."
  stop_debian
  rm -rf \$p/*
  \$BB tar xzpf \$sel_snap -C \$p --numeric-owner
  echo -e "\nSnapshot restored successfully"
  
else
  echo -e "\nInvalid option"
  exit 1
fi
EOF
chmod +x "$scripts_path/snapshot_debian.sh"



echo -e "\033c"
echo -e "\nDebian Sid installation completed. Now you can use start_debian.sh script to login to container\n"
