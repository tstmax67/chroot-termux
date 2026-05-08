#!/system/bin/sh

# =============================================
# this will cause the script to exit on error
set -e
# unsetting this variable cause it will cause troubles when initializing chroot
unset LD_PRELOAD

# checking busybox
if test -x /data/adb/magisk/busybox; then
	BB=/data/adb/magisk/busybox
elif test -x /data/adb/ksu/bin/busybox; then
	BB=/data/adb/ksu/bin/busybox
else
	echo "busybox not found or not executable. Check magisk/ksu installation." >&2
	exit 1
fi



# =============================================
# variables
distros="Alpine Debian"
container_names="alpineEdge debianSid"
tar_names="alpine-edge debian-sid"
dl_links="https://github.com/tstmax67/chroot-termux/releases/download/Alpine/alpine-edge.tar.gz https://github.com/tstmax67/chroot-termux/releases/download/Debian/debian-sid.tar.gz"
# random sleep duration so this script won't collide with other scripts
slp_duration=$(awk 'BEGIN{srand(); print int(77777777+rand()*22222222)}')


# =============================================
# functions
clear_screen() {
  echo -e "\033c"
}
# function to simulate arrays: get_item "item1 item2" 2 -> returns item2
get_item() {
  list=$1
  index=$2
  echo "$list" | awk "{print \$$index}"
}


# =============================================
# collecting some basic information from user to kickstart the installation
clear_screen
echo "Which distro to install? Enter a number or press enter to select the default(1)"

i=1
for d in $distros; do
  echo "$i) $d"
  i=$(expr $i + 1)
done
echo -n "> "
read distro_choice
if test -z "$distro_choice"; then
	distro_idx=1
else
  distro_idx=$distro_choice
fi
echo $distro_idx

# validation
max_distros=$(echo $distros | wc -w)
case "$distro_idx" in
''|*[!0-9]*) 
  echo "Error: '$distro_idx' is not a valid number."
  exit 1 
  ;;
esac
if [ "$distro_idx" -lt 1 ] || [ "$distro_idx" -gt "$max_distros" ]; then
  echo "Error: Selection out of range (1-$max_distros)."
  exit 1
fi
# Extract selected values
distro_name=$(get_item "$distros" "$distro_idx")
container_dirname=$(get_item "$container_names" "$distro_idx")
tar_name=$(get_item "$tar_names" "$distro_idx")
dl_link=$(get_item "$dl_links" "$distro_idx")


echo "Enter a location to install your distro or press enter to use /data/local as default"
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

echo "Enter a name for container folder or press enter to use '$container_dirname' as default"
echo -n "> "
read c_name
if ! test -z "$c_name"; then
	container_dirname=$c_name
fi

# =============================================
# setting up parent directories
container_path=$(realpath "$installation_path/$container_dirname")
if ! test -d "$container_path"; then
  mkdir -p "$container_path"
fi
rootfs_path="$container_path/rootfs"
mkdir -p "$rootfs_path"


# checking if already installed
if [ -n "$(find "$rootfs_path" -maxdepth 0 -not -empty)" ]; then
  echo "$rootfs_path is not empty. Clean it first" >&2
  exit 1
else

  # creating seperate namespace for container management
  if ! test -f "$container_path/.pid"; then
    echo "$BB nohup sleep $slp_duration > /dev/null 2>&1 &
    echo -n \$! > $container_path/.pid" | $BB unshare -m --propagation private -- sh
  else
    container_namespace_pid=$(cat "$container_path/.pid")
    if ! test -d "/proc/$container_namespace_pid"; then
      echo "$BB nohup sleep $slp_duration > /dev/null 2>&1 &
      echo -n \$! > $container_path/.pid" | $BB unshare -m --propagation private -- sh
    fi
  fi
  container_namespace_pid=$(cat "$container_path/.pid")
  nBB="$BB nsenter -m -t $container_namespace_pid -- $BB"

  # ==========================================
  # distro configs check
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

  # ===========================================
  # Downloading and extracting rootfs
  cd "$container_path"
  echo -e "\nDownloading rootfs..."
  rm -rf "${tar_name}.tar.gz"
  $BB wget --no-check-certificate -q -O bindfs "https://raw.githubusercontent.com/tstmax67/debian-sid-chroot-termux/main/bindfs"
  chmod +x bindfs
  $BB wget --no-check-certificate -q "$dl_link"
  echo "Downloading completed"
  echo "Installing Debian Sid"


  if ! test -f "$container_path/.extract-complete"; then
    $BB tar xzpf "${tar_name}.tar.gz" -C "$rootfs_path" --numeric-owner
    touch "$container_path/.extract-complete"
  fi

  # ===========================================
  # creating directory for snapshots
  mkdir -p "$container_path/snapshot"
  snap_dir="$container_path/snapshot"


  # ===========================================
  # Mounting necessary filesystems
  $nBB mount -o remount,dev,suid /data
  if ! $nBB mount | $BB grep -q $rootfs_path/dev; then
    $nBB mount --rbind /dev $rootfs_path/dev
  fi
  if ! $nBB mount | $BB grep -q $rootfs_path/sys; then
    $nBB mount --rbind /sys $rootfs_path/sys
  fi
  if ! $nBB mount | $BB grep -q $rootfs_path/proc; then
    $nBB mount --rbind /proc $rootfs_path/proc
  fi
  if ! $nBB mount | $BB grep -q $rootfs_path/dev/pts; then
    $nBB mount -t devpts devpts $rootfs_path/dev/pts
  fi

  if ! $nBB mount | $BB grep -q $rootfs_path/dev/shm; then
    $nBB mkdir -p $rootfs_path/dev/shm
    $nBB mount -t tmpfs tmpfs $rootfs_path/dev/shm
  fi

  # ===========================================
  # setting up internals
  if ! test -f "$container_path/.int_setup"; then
    case "$distro_name" in
    "Alpine")
      PATH=/usr/bin/:/usr/sbin/:/bin/:/sbin/ $nBB chroot $rootfs_path bin/sh -c '
        addgroup -g 3003 aid_inet
        addgroup -g 3004 aid_net_raw
        addgroup -g 1003 aid_graphics
        addgroup root aid_inet
        addgroup storage
      '
      ;;
      
    "Debian")
      PATH=/usr/bin/:/usr/sbin/:/bin/:/sbin/ $nBB chroot $rootfs_path bin/sh -c '
        echo "127.0.0.1 localhost" >> /etc/hosts
        groupadd -g 3003 aid_inet
        groupadd -g 3004 aid_net_raw
        groupadd -g 1003 aid_graphics
        # usermod -g 3003 -G 3003,3004 -a _apt
        usermod -G 3003 -a root
        groupadd storage
        
        sed -i "s/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/" /etc/locale.gen
        locale-gen
      '
      ;;
    esac

    PATH=/usr/bin/:/usr/sbin/:/bin/:/sbin/ $nBB chroot $rootfs_path bin/sh -c '
      echo "nameserver 1.1.1.1" > /etc/resolv.conf
      echo "XDG_RUNTIME_DIR=/tmp/runtime" >> /etc/environment
      echo "TMPDIR=/tmp" >> /etc/environment
      mkdir -p /tmp/runtime
      chmod 700 /tmp/runtime
    '
    touch "$container_path/.int_setup"
  fi
  
  # ===========================================
  # update distro
  case "$distro_name" in
  "Alpine")
    PATH=/usr/bin/:/usr/sbin/:/bin/:/sbin/ TMPDIR=/tmp $nBB chroot $rootfs_path bin/sh -c '
      apk update
      yes | apk upgrade
      yes | apk add sudo
    '
    ;;
  "Debian")
    PATH=/usr/bin/:/usr/sbin/:/bin/:/sbin/ TMPDIR=/tmp $nBB chroot $rootfs_path bin/sh -c '
      apt update
      yes | apt upgrade
      yes | apt install sudo
    '
    ;;
  esac



  # ===========================================
  # creating new user
  echo -e "\033c"
  if test "$useFishShell" == "y"; then
    case "$distro_name" in
    "Alpine")
      PATH=/usr/bin/:/usr/sbin/:/bin/:/sbin/ TMPDIR=/tmp $nBB chroot $rootfs_path bin/sh -c "
        yes | apk add fish
        adduser -D -G users -s /usr/bin/fish $user
        for group in wheel audio video storage aid_inet; do
          addgroup $user \$group
        done
        sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
        printf '$password_root\n$password_root\n' | passwd root
        printf '$password_main_user\n$password_main_user\n' | passwd tst
      "
      ;;
    "Debian")
      PATH=/usr/bin/:/usr/sbin/:/bin/:/sbin/ TMPDIR=/tmp $nBB chroot $rootfs_path bin/sh -c "
        yes | apt install fish
        useradd -m -g users -G sudo,audio,video,storage,aid_inet -s /usr/bin/fish $user
      "
      echo "$password_main_user" | PATH=/usr/bin/:/usr/sbin/ TMPDIR=/tmp $nBB chroot $rootfs_path passwd --stdin $user
      echo "$password_root" | PATH=/usr/bin/:/usr/sbin/ TMPDIR=/tmp $nBB chroot $rootfs_path passwd --stdin root
      ;;
    esac
    
  else
    case "$distro_name" in
    "Alpine")
      PATH=/usr/bin/:/usr/sbin/:/bin/:/sbin/ TMPDIR=/tmp $nBB chroot $rootfs_path bin/sh -c "
        adduser -D -G users -s /usr/bin/bash $user
        for group in wheel audio video storage aid_inet; do
          addgroup $user \$group
        done
        sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
        printf '$password_root\n$password_root\n' | passwd root
        printf '$password_main_user\n$password_main_user\n' | passwd tst
      "
      ;;
    "Debian")
      PATH=/usr/bin/:/usr/sbin/:/bin/:/sbin/ TMPDIR=/tmp $nBB chroot $rootfs_path useradd -m -g users -G sudo,audio,video,storage,aid_inet -s /usr/bin/bash $user
      echo "$password_main_user" | PATH=/usr/bin/:/usr/sbin/ TMPDIR=/tmp $nBB chroot $rootfs_path passwd --stdin $user
      echo "$password_root" | PATH=/usr/bin/:/usr/sbin/ TMPDIR=/tmp $nBB chroot $rootfs_path passwd --stdin root
      ;;
    esac
  fi
  rm -rf "$container_path/.prompt_complete"
  rm -rf "$container_path/.int_setup"
  rm -rf "$container_path/.extract-complete"
  rm -rf "$container_path/${tar_name}.tar.gz"
fi





















# making variables for common commands
at_start="#!/system/bin/sh
set -e
unset LD_PRELOAD"

bb_check_func="# checking busybox
if test -x /data/adb/magisk/busybox; then
	BB=/data/adb/magisk/busybox
elif test -x /data/adb/ksu/bin/busybox; then
	BB=/data/adb/ksu/bin/busybox
else
	echo 'busybox not found or not executable. Check magisk/ksu installation.' >&2
	exit 1
fi"

sleep_func="# random sleep duration so this script won't collide with other scripts
slp_duration=\$(awk 'BEGIN{srand(); print int(77777777+rand()*22222222)}')"

case "$distro_name" in
"Alpine")
  su_path="bin/su"
  ;;
"Debian")
  su_path="usr/bin/su"
  ;;
esac




# creating script to start debian in background
cat << EOF > "$scripts_path/start_${container_dirname}.sh"
$at_start

$bb_check_func

$sleep_func

#Path of distro rootfs
rootfs_path='$rootfs_path'
ext_sdcard_path='$ext_sdcard_path'
container_path='$container_path'

# creating seperate namespace for container management
if ! test -f \$container_path/.pid; then
  echo "\$BB nohup sleep \$slp_duration > /dev/null 2>&1 &
  echo -n \\\$! > '\$container_path'/.pid" | \$BB unshare -m --propagation private -- sh
else
  container_namespace_pid=\$(cat "\$container_path"/.pid)
  if ! test -d /proc/\$container_namespace_pid; then
    echo "\$BB nohup sleep \$slp_duration > /dev/null 2>&1 &
    echo -n \\\$! > '\$container_path'/.pid" | \$BB unshare -m --propagation private -- sh
  fi
fi
container_namespace_pid=\$(cat "\$container_path"/.pid)
nBB="\$BB nsenter -m -t \$container_namespace_pid -- \$BB"
n="\$BB nsenter -m -t \$container_namespace_pid --"

# Fix setuid issue
\$nBB mount -o remount,dev,suid /data

# mounding necessary pseudo file systems
if ! \$nBB mount | \$BB grep -q "\$rootfs_path"/dev; then
  \$nBB mount --rbind /dev "\$rootfs_path"/dev
fi
if ! \$nBB mount | \$BB grep -q "\$rootfs_path"/sys; then
  \$nBB mount --rbind /sys "\$rootfs_path"/sys
fi
if ! \$nBB mount | \$BB grep -q "\$rootfs_path"/proc; then
  \$nBB mount --rbind /proc "\$rootfs_path"/proc
fi
if ! \$nBB mount | \$BB grep -q "\$rootfs_path"/dev/pts; then
  \$nBB mount -t devpts devpts "\$rootfs_path"/dev/pts
fi

# /dev/shm for Electron apps
if ! \$nBB mount | \$BB grep -q "\$rootfs_path"/dev/shm; then
  \$nBB mkdir -p "\$rootfs_path"/dev/shm
  \$nBB mount -t tmpfs tmpfs "\$rootfs_path"/dev/shm
fi

if ! \$nBB mount | \$BB grep -q "\$rootfs_path"/mnt/internal; then
  mkdir -p "\$rootfs_path"/mnt/internal
  \$n $container_path/bindfs --force-user=1000 --create-for-user=1000 --force-group=100 --create-for-group=100 --chmod-allow-x /data/media/0 "\$rootfs_path"/mnt/internal
fi

if ! test -z "\$ext_sdcard_path"; then
  if ! test -d "\$ext_sdcard_path"; then
    echo "Extenal sdcard can not be mounted. Directory \$ext_sdcard_path doesn't exit"
  else
    if ! \$nBB mount | \$BB grep -q "\$rootfs_path"/mnt/ext_sdcard; then
      mkdir -p "\$rootfs_path"/mnt/ext_sdcard
      \$n $container_path/bindfs --force-user=1000 --create-for-user=1000 --force-group=100 --create-for-group=100 --chmod-allow-x "\$ext_sdcard_path" "\$rootfs_path"/mnt/ext_sdcard
    fi
  fi
fi

if ! \$nBB mount | \$BB grep -q "\$rootfs_path"/mnt/android-data; then
  mkdir -p "\$rootfs_path"/mnt/android-data
  \$n $container_path/bindfs --force-user=1000 --create-for-user=1000 --force-group=100 --create-for-group=100 --chmod-allow-x /data/ "\$rootfs_path"/mnt/android-data
fi

if ! \$nBB mount | \$BB grep -q "\$rootfs_path"/mnt/android-system; then
  mkdir -p "\$rootfs_path"/mnt/android-system
  \$n $container_path/bindfs --force-user=1000 --create-for-user=1000 --force-group=100 --create-for-group=100 /system "\$rootfs_path"/mnt/android-system
fi

# entering chroot
\$nBB chroot "\$rootfs_path" $su_path -l root -c '
  if ! test -d /tmp/runtime; then
    mkdir -p /tmp/runtime
  fi
  if test "\$(stat -c "%a" /tmp/runtime)" != "700"; then
    chmod 700 /tmp/runtime
  fi
'
EOF
chmod +x "$scripts_path/start_${container_dirname}.sh"




# creating login script
cat << EOF > "$scripts_path/login_${container_dirname}.sh"
$at_start

$bb_check_func

#Path of distro rootfs
rootfs_path='$rootfs_path'
scripts_path='$scripts_path'
container_path='$container_path'

# creating seperate namespace for container management
if ! test -f "\$container_path"/.pid; then
  sh "\$scripts_path/start_${container_dirname}.sh"
else
  container_namespace_pid=\$(cat "\$container_path"/.pid)
  if ! test -d /proc/\$container_namespace_pid; then
    sh "\$scripts_path/start_${container_dirname}.sh"
  fi
fi
container_namespace_pid=\$(cat "\$container_path"/.pid)
nBB="\$BB nsenter -m -t \$container_namespace_pid -- \$BB"
n="\$BB nsenter -m -t \$container_namespace_pid --"

# entering chroot
\$nBB chroot "\$rootfs_path" $su_path - $user
EOF
chmod +x "$scripts_path/login_${container_dirname}.sh"





# creating run command script
cat << EOF > "$scripts_path/run_${container_dirname}.sh"
$at_start

$bb_check_func

#Path of distro rootfs
rootfs_path='$rootfs_path'
scripts_path='$scripts_path'
container_path='$container_path'

# creating seperate namespace for container management
if ! test -f "\$container_path"/.pid; then
  sh "\$scripts_path/start_${container_dirname}.sh"
else
  container_namespace_pid=\$(cat "\$container_path"/.pid)
  if ! test -d /proc/\$container_namespace_pid; then
    sh "\$scripts_path/start_${container_dirname}.sh"
  fi
fi
container_namespace_pid=\$(cat "\$container_path"/.pid)
nBB="\$BB nsenter -m -t \$container_namespace_pid -- \$BB"
n="\$BB nsenter -m -t \$container_namespace_pid --"

# entering chroot
\$nBB chroot "\$rootfs_path" $su_path -l $user -c "\$1"
EOF
chmod +x "$scripts_path/run_${container_dirname}.sh"






# creating stop script
cat << EOF > "$scripts_path/stop_${container_dirname}.sh"
$at_start

$bb_check_func

#Path of distro rootfs
container_path='$container_path'

# getting pid of seperate mount namespace program
if test -f "\$container_path"/.pid; then
  container_namespace_pid=\$(cat "\$container_path"/.pid)
  if test -d /proc/\$container_namespace_pid; then
    mnt=\$(\$BB readlink /proc/\$container_namespace_pid/ns/mnt)
    for pid in /proc/[0-9]*; do
      ns=\$(\$BB readlink \$pid/ns/mnt || true)
      if test "\$ns" == "\$mnt"; then
        \$BB kill -9 "\$(echo \$pid | \$BB cut -c 7-)" 2>/dev/null
      fi
    done
  fi
  
  rm -rf "\$container_path"/.pid
fi
echo -e "\nContainer stopped"
EOF
chmod +x "$scripts_path/stop_${container_dirname}.sh"





# creating remove script
cat << EOF > "$scripts_path/remove_${container_dirname}.sh"
$at_start

$bb_check_func

#Path of distro rootfs
scripts_path='$scripts_path'
container_path='$container_path'

sh "\$scripts_path/stop_${container_dirname}.sh"
rm -rf "\$container_path"
echo "Container removed"
EOF
chmod +x "$scripts_path/remove_${container_dirname}.sh"






# creating backup script
cat << EOF > "$scripts_path/backup_${container_dirname}.sh"
$at_start

$bb_check_func

#Path of distro rootfs
scripts_path='$scripts_path'
installation_path='$installation_path'
container_dirname='$container_dirname'

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

sh "\$scripts_path/stop_${container_dirname}.sh"

echo "Creating backup..."
\$BB tar czpf "\$backup_dir/${container_dirname}_backup.tar.gz" -C "\$installation_path" "\$container_dirname" --numeric-owner
echo "Backup created successfully"
EOF
chmod +x "$scripts_path/backup_${container_dirname}.sh"






# creating snapshot script
cat << EOF > "$scripts_path/snapshot_${container_dirname}.sh"
$at_start

$bb_check_func

#Path of distro rootfs
rootfs_path='$rootfs_path'
snap_dir='$snap_dir'
scripts_path='$scripts_path'

echo "Press 1 or 2"
echo "1) create a snapshot"
echo "2) restore from a snapshot"
echo -n "> "
read -n 1 choice
echo -e "\n"

if test "\$choice" -eq 1; then
  echo "Creating snapshot..."
  echo "Shutting container before creating snapshot..."
  sh "\$scripts_path/stop_${container_dirname}.sh"
  \$BB tar czpf "\$snap_dir"/snap-\$(date "+%S%M%H%Y%m%d").tar.gz -C "\$rootfs_path" . --numeric-owner
  echo "Snapshot created successfully"

elif test "\$choice" -eq 2; then
  echo "choose a snapshot to restore"
  count=1
  for snap in \$(ls -1 "\$snap_dir"/snap-*.tar.gz); do
    echo "\$count) \$(basename -s '.tar.gz' \$snap)"
    count=$(expr $count + 1)
  done
  echo -n "> "
  read numb
  
  sel_snap=\$(ls -1 "\$snap_dir"/snap-*.tar.gz | awk "NR==\$numb")
  echo "Restoring snapshot..."
  echo "Shutting container before restoring snapshot..."
  sh "\$scripts_path/stop_${container_dirname}.sh"
  rm -rf "\$rootfs_path"/*
  \$BB tar xzpf "\$sel_snap" -C "\$rootfs_path" --numeric-owner
  echo "Snapshot restored successfully"
  
else
  echo -e "\nInvalid option"
  exit 1
fi
EOF
chmod +x "$scripts_path/snapshot_${container_dirname}.sh"





# killing namespace that was created for setup
mnt=$($BB readlink /proc/"$container_namespace_pid/ns/mnt")
for pid in /proc/[0-9]*; do
  ns=$($BB readlink "$pid/ns/mnt" || true)
  if test "$ns" == "$mnt"; then
    $BB kill -9 "$(echo $pid | cut -c 7-)" 2>/dev/null
  fi
done
rm -rf "$container_path/.pid"






echo -e "\033c"
echo -e "\n$distro_name installation completed. Now you can use start_${container_dirname}.sh script to login to container\n"
