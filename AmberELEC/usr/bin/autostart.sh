#!/bin/sh

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2019-present Shanti Gilbert (https://github.com/shantigilbert)

# Source predefined functions and variables
. /etc/profile

DEVICE=$(tr -d '\0' < /sys/firmware/devicetree/base/model)

# Boot time optimization - disable unnecessary services
systemctl mask systemd-hwdb-update.service
systemctl disable wait-time-sync.service
systemctl mask wait-time-sync.service
systemctl disable joyled.service
systemctl mask joyled.service

# Set performance mode to start the boot
performance

/usr/bin/r36s-set-volume.sh &

# Check ES splash is a symlink ...Show splash logo
es_rlogo="/storage/.config/emulationstation/resources/logo.png"
usr_splash="/storage/.config/splash"
usr_eslogo="${usr_splash}/logo.png"

if [ -e "${es_rlogo}" ]; then
    if [ ! -h "${es_rlogo}" ]; then
        cp -f "${es_rlogo}" "${usr_splash}/"
        rm -f "${es_rlogo}"; ln -sf "${usr_eslogo}" "${es_rlogo}"
    fi
fi

/usr/bin/show_splash.sh &

# write logs to tmpfs not the sdcard
mkdir /tmp/logs
mkdir -p /storage/.config/emulationstation/logs/
ln -s /storage/roms/gamedata/retroarch/logs/ /tmp/logs/retroarch
ln -s /storage/.config/emulationstation/logs/ /tmp/logs/emulationstation

# Apply some kernel tuning
sysctl vm.swappiness=1

# Restore config if backup exists
BPATH="/storage/roms/backup/"
BACKUPFILE="${BPATH}/AmberELEC_BACKUP.zip"

if [ -e "${BPATH}/.restore" ]
then
  if [ -f "${BACKUPFILE}" ]; then
    echo -en '\e[0;0H\e[37mRestoring backup and rebooting...\e[0m' >/dev/console
    unzip -o ${BACKUPFILE} -d /
    rm ${BACKUPFILE}
    systemctl reboot
  fi
fi

# Restore identity if it exists from a factory reset
IDENTITYFILE="${BPATH}/identity.tar.gz"

if [ -e "${IDENTITYFILE}" ]
then
  cd /
  tar -xvzf ${IDENTITYFILE} >${BPATH}/restore.log
  rm ${IDENTITYFILE}
  echo -en '\e[0;0H\e[37mIdentity restored, rebooting...\e[0m' >/dev/console
  systemctl reboot
fi

if [ ! -e "/storage/.newcfg" ]
then
  echo -en '\e[0;0H\e[37mPlease wait, initializing system...\e[0m' >/dev/console
fi

# It seems some slow SDcards have a problem creating the symlink on time :/
CONFIG_DIR="/storage/.emulationstation"
CONFIG_DIR2="/storage/.config/emulationstation"

if [ ! -L "$CONFIG_DIR" ]; then
  ln -sf $CONFIG_DIR2 $CONFIG_DIR
fi

# Setup default artbook symlink for use in ES
DEFAULT_THEME_USR=/usr/config/emulationstation/themes/art-book-next-es-demake/
DEFAULT_THEME_STORAGE=/storage/.config/emulationstation/themes/art-book-next-es-demake
if [ ! -e "$DEFAULT_THEME_STORAGE" ]; then
  ln -s $DEFAULT_THEME_USR $DEFAULT_THEME_STORAGE
fi

# Create the distribution directory if it doesn't exist, sync it if it does
if [ ! -d "/storage/.config/distribution" ]
then
  rsync -a /usr/config/distribution/ /storage/.config/distribution/ &
else
  rsync -a --delete --exclude=custom_start.sh --exclude=configs --exclude=lzdoom.ini --exclude=gzdoom.ini --exclude=raze.ini --exclude=ecwolf.cfg /usr/config/distribution/ /storage/.config/distribution/ &
fi

# Clean cache garbage when boot up.
rsync -a --delete /tmp/cache/ /storage/.cache/cores/ &

# Copy in build metadata
rsync /usr/config/.OS* /storage/.config &

# Copy remappings
rsync --ignore-existing -raz /usr/config/remappings/* /storage/remappings/ &

# Move ports to the GAMES volume
rsync -a --exclude gamelist.xml /usr/config/ports/* /storage/roms/homebrew &

# Sync ES locale if missing
if [ ! -d "/storage/.config/emulationstation/locale" ]
then
  rsync -a /usr/config/locale/ /storage/.config/emulationstation/locale/ &
fi

# Wait for the rsync processes to finish.
wait

if [ ! -e "/storage/roms/homebrew/gamelist.xml" ]
then
  cp -f /usr/config/ports/gamelist.xml /storage/roms/homebrew
fi

# Move portmaster gamelist to PORTS
if [ ! -e "/storage/roms/ports/gamelist.xml" ]; then
  cp -rf /usr/config/portmaster-gl/* /storage/roms/ports &
fi

# End Automatic updates

# restart volume control service
systemctl stop volume; systemctl start volume &

# /usr/bin/r36s-set-volume.sh &

# start services
/usr/bin/startservices.sh &

# Migrate game data to the games partition
GAMEDATA="/storage/roms/gamedata"
if [ ! -d "${GAMEDATA}" ]
then
  mkdir -p "${GAMEDATA}"
fi

for GAME in ppsspp dosbox retroarch hatari
do
  # Migrate or copy fresh data
  if [ ! -d "${GAMEDATA}/${GAME}" ]
  then
    if [ -d "/storage/.config/${GAME}" ]
    then
      mv "/storage/.config/${GAME}" "${GAMEDATA}/${GAME}"
    else
      rsync -a "/usr/config/${GAME}/" "${GAMEDATA}/${GAME}/"
    fi
  fi

  # Link the original location to the new data location
  if [ ! -L "/storage/.config/${GAME}" ]
  then
    rm -rf "/storage/.config/${GAME}" 2>/dev/null
    ln -sf "${GAMEDATA}/${GAME}" "/storage/.config/${GAME}"
  fi
done

# Create drastic gamedata folder
if [ ! -d "${GAMEDATA}/drastic" ]
then
  mkdir -p "${GAMEDATA}/drastic"
  ln -sf "${GAMEDATA}/drastic" "/storage/drastic"
fi

# Controller remaps
if [ ! -d "${GAMEDATA}/remappings" ]
then
  if [ -d "/storage/remappings" ]
  then
    mv "/storage/remappings" "${GAMEDATA}/remappings"
  else
    mkdir -p "${GAMEDATA}/remappings"
  fi
fi

if [ ! -L "/storage/remappings" ]
then
   rm -rf "/storage/remappings" 2>/dev/null
   ln -sf "${GAMEDATA}/remappings" "/storage/remappings"
fi

## Only call postupdate once after an UPDATE
if [ "UPDATE" == "$(cat /storage/.config/boot.hint)" ]; then
	echo -en '\e[0;0H\e[37mExecuting postupdate...\e[0m' >/dev/console
	/usr/bin/postupdate.sh
	echo "OK" > /storage/.config/boot.hint
fi

sync &

# run custom_start before FE scripts
/storage/.config/custom_start.sh before

#first run
frg="/storage/.config/firstrun.r36"
if [ -f "$frg" ]; then
  rm /storage/.config/splash/usr_logo/*
  rm -f "${frg}"
fi

# Set Gamma for Screen
gcfg="/storage/.config/gamma_p4.cfg"
if [ -f "$gcfg" ]; then
  gamma_set=$(head -n 2 "$gcfg" | tail -1) 
  if [ "$gamma_set" == "enabled" ]; then
    # gamma $(cat "$gcfg")
    gamma $(head -n 1 $gcfg)
  fi
fi

# Restore last saved brightness
BRIGHTNESS=$(get_ee_setting system.brightness)
if [[ ! "${BRIGHTNESS}" =~ [0-9] ]]
then
  BRIGHTNESS=100
fi

# Ensure user doesn't get "locked out" with super low brightness
if [[ "${BRIGHTNESS}" -lt "3" ]]
then
  BRIGHTNESS=3
fi
BRIGHTNESS=$(printf "%.0f" ${BRIGHTNESS})
echo ${BRIGHTNESS} > /sys/class/backlight/backlight/brightness
set_ee_setting system.brightness ${BRIGHTNESS}

# If the WIFI adapter isn't enabled, disable it on startup
# to soft block the radio and save a bit of power.
if [ "$(get_ee_setting wifi.enabled)" == "0" ]
then
  connmanctl disable wifi
  # Power down the WIFI device
  if [ "$DEVICE" == "Anbernic RG552" ]; then
    echo 0 > /sys/class/gpio/gpio113/value
  elif [ "$DEVICE" == "Anbernic RG351P" ]; then
    echo 0 > /sys/class/gpio/gpio110/value
  else
    echo 0 > /sys/class/gpio/gpio5/value
  fi
fi

if [ "$(get_ee_setting wifi.internal.disabled)" == "1" ]
then
  /usr/bin/batocera-internal-wifi disable-no-refresh
fi

rm -f "/storage/.config/device" 2>/dev/null
if [ "$DEVICE" == "Anbernic RG351MP" ]; then
  VOLT1=$(cat /sys/bus/iio/devices/iio:device0/in_voltage1_raw)
  VOLT2=$(cat /sys/bus/iio/devices/iio:device0/in_voltage2_raw)
  if (( ${VOLT2} < 500 )); then
    if ((${VOLT1} >= 450 && ${VOLT1} <= 800)); then
      echo "R3xS" > /storage/.config/device
    elif ((${VOLT1} >= 950 && ${VOLT1} <= 1035)); then
      echo "R33S" > /storage/.config/device
    else
      echo "Unknown" > /storage/.config/device
    fi
  fi
fi

if [ "$DEVICE" == "Anbernic RG351MP" ] || [ "$DEVICE" == "PowKiddy Magicx XU10" ]; then
	amixer -c 0 cset iface=MIXER,name='Playback Path' SPK_HP
fi

# Initialize audio so the softvol mixer is created and audio is allowed to be changed
# - This is the shortest, totally silent .wav I could create with audacity - duration is .001 seconds
aplay /usr/bin/emustation-config-init.wav

if [ "$EE_DEVICE" == "RG552" ] || [[ "$EE_DEVICE" =~ RG351 ]]; then
  # For some reason the audio is being reseted to 100 at boot, so we reapply the saved settings here
  /usr/bin/odroidgoa_utils.sh vol $(get_ee_setting "audio.volume")
fi

# hide tools entries
if [ "$EE_DEVICE" == "RG351MP" ]; then
  if [ "$DEVICE" == "PowKiddy Magicx XU10" ]  || [ "$DEVICE" == "SZDiiER D007 Plus" ]; then
    xmlstarlet ed -L -u "//game[path='./display_fix.sh']/hidden" -v "true" /storage/.config/distribution/modules/gamelist.xml
    xmlstarlet ed -L -u "//game[path='./joyleds_conf.sh']/hidden" -v "false" /storage/.config/distribution/modules/gamelist.xml
  else
    xmlstarlet ed -L -u "//game[path='./display_fix.sh']/hidden" -v "false" /storage/.config/distribution/modules/gamelist.xml
    xmlstarlet ed -L -u "//game[path='./joyleds_conf.sh']/hidden" -v "true" /storage/.config/distribution/modules/gamelist.xml
  fi
fi

# restore last played game
timeout=60 #ms
elapsed=0
if [ -f /storage/.config/lastgame ]; then
  echo -en '\e[0;0H\e[37mRestoring the last running game...\e[0m' >/dev/console
  if [ "$(get_ee_setting retroachievements)" = "1" ]; then
    if [[ $(ls /sys/class/net | grep -E '^(wlan|eth)[0-9]+$') ]]; then
      while [[ ! $(ip route | grep default) ]]; do
          if [[ $elapsed -ge 10 ]]; then
            if [[ $elapsed -ge $timeout ]]; then
              break
            else
              echo -en '\e[0;0H\e[37m\nRetroachievements are enabled...\nWaiting for network to become available...\e[0m' >/dev/console
            fi
          fi
          sleep 0.1
          ((elapsed++))
      done
    fi
  fi
  command=`cat /storage/.config/lastgame`
  sh -c -- "$command"

  #cleanup on exiting retroarch/emu/mpv
  platform_part="${command#*--platform }"
  platform_part="${platform_part%% --*}"


  #final update of meta data on exit
  if [ -f /tmp/gt_launch.inf ]; then
      # get current datetime in seconds
      cur_time="$(date +%s)"
      gl_time="$(cat /tmp/gt_launch.inf | sed -n '3p')"
      # get the difference
      actual_time="$(( ${cur_time}-${gl_time} ))"
      sed -i "3s/.*/${actual_time}/" /tmp/gt_launch.inf
      #clean up rom title for gamelist.xml passing
      rom_name="$(cat /tmp/gt_launch.inf | sed -n '2p')"
      rom_name=".\/${rom_name##*/}"
      sed -i "2s/.*/${rom_name}/" /tmp/gt_launch.inf
      #update metadata including incrementing play count by 1 
      python3 /usr/bin/lg_meta_ud.py count
  fi

  # cleanup temporay files
  if [ -f /storage/.config/lastgame_na ]; then
    # get rom name from gt_launch.inf -- correct for platform path name
    arom_name="$(cat /tmp/gt_launch.inf | sed -n '2p')"
    arom_name="${arom_name##*/}"
    arom_name="${arom_name%.*}"
    rm -rf "/storage/roms/savestates/${platform_part}/${arom_name}.state.auto"
    rm -rf "/storage/roms/savestates/${platform_part}/${arom_name}.state.auto.png"
    rm -rf /storage/.config/lastgame_na
  fi

  if [ -d /storage/.tmp/ep128 ]; then
    rm -rf /storage/.tmp/ep128
  fi

  #set es_settings to point to last played
  es_set="/storage/.config/emulationstation/es_settings.cfg"
  es_chk=$(cat "${es_set}" | grep "LastSystem")

  if [ "${es_chk}" ]; then
    sed -i '/\"LastSystem\"/c\\t<string name\=\"LastSystem\" value\=\"recent\" />' "${es_set}"
  else
    sed -i '/<\/config>/i\\t<string name\=\"LastSystem\" value\=\"recent\" />' "${es_set}"
  fi

  rm -rf /storage/.config/lastgame
fi

# What to start at boot?
DEFE=$(get_ee_setting ee_boot)

case "$DEFE" in
"Retroarch")
        rm -rf /var/lock/start.retro
        touch /var/lock/start.retro
        systemctl start retroarch
        ;;
*)
        rm /var/lock/start.games
        touch /var/lock/start.games
        systemctl start emustation
        ;;
esac

# run custom_start ending scripts
/storage/.config/custom_start.sh after

# default to ondemand/powersave in EmulationStation
POWERSAVE_ES=$(get_ee_setting powersave_es)
if [ "${POWERSAVE_ES}" == "1" ]; then
  es_powersave &
else
  es_ondemand &
fi

#cleanup misc evtest process and allow systemd to start them again
kill -9 $(pgrep evtest)

clear > /dev/console
