#!/bin/bash

VERSION=2.10

# printing greetings

echo "pool.52kx.net mining setup script v$VERSION."
echo "(please report issues to dforel@qq.com email with full output of this script with extra \"-x\" \"bash\" option)"
echo

if [ "$(id -u)" == "0" ]; then
  echo "WARNING: Generally it is not adviced to run this script under root"
fi

# command line arguments
WALLET=$1
EMAIL=$2 # this one is optional

# checking prerequisites

if [ -z $WALLET ]; then
  echo "Script usage:"
  echo "> setup_52kx_miner.sh <wallet address> [<your email address>]"
  echo "ERROR: Please specify your wallet address"
  exit 1
fi

WALLET_BASE=`echo $WALLET | cut -f1 -d"."`
if [ ${#WALLET_BASE} != 106 -a ${#WALLET_BASE} != 95 ]; then
  echo "ERROR: Wrong wallet base address length (should be 106 or 95): ${#WALLET_BASE}"
  exit 1
fi

if [ -z $HOME ]; then
  echo "ERROR: Please define HOME environment variable to your home directory"
  exit 1
fi

if [ ! -d $HOME ]; then
  echo "ERROR: Please make sure HOME directory $HOME exists or set it yourself using this command:"
  echo '  export HOME=<dir>'
  exit 1
fi

if ! type curl >/dev/null; then
  echo "ERROR: This script requires \"curl\" utility to work correctly"
  exit 1
fi

if ! type lscpu >/dev/null; then
  echo "WARNING: This script requires \"lscpu\" utility to work correctly"
fi

#if ! sudo -n true 2>/dev/null; then
#  if ! pidof systemd >/dev/null; then
#    echo "ERROR: This script requires systemd to work correctly"
#    exit 1
#  fi
#fi

# calculating port

LSCPU=`lscpu`
CPU_SOCKETS=`echo "$LSCPU" | grep "^Socket(s):" | cut -d':' -f2 | sed "s/^[ \t]*//"`
if [ -z $CPU_SOCKETS ]; then
  echo "WARNING: Can't get CPU sockets from lscpu output"
  export CPU_SOCKETS=1
fi
CPU_CORES_PER_SOCKET=`echo "$LSCPU" | grep "^Core(s) per socket:" | cut -d':' -f2 | sed "s/^[ \t]*//"`
if [ -z "$CPU_CORES_PER_SOCKET" ]; then
  echo "WARNING: Can't get CPU cores per socket from lscpu output"
  export CPU_CORES_PER_SOCKET=1
fi
CPU_THREADS=`echo "$LSCPU" | grep "^CPU(s):" | cut -d':' -f2 | sed "s/^[ \t]*//"`
if [ -z "$CPU_THREADS" ]; then
  echo "WARNING: Can't get CPU cores from lscpu output"
  if ! type nproc >/dev/null; then
    echo "WARNING: This script requires \"nproc\" utility to work correctly"
    export CPU_THREADS=1
  else
    CPU_THREADS=`nproc`
    if [ -z "$CPU_THREADS" ]; then
      echo "WARNING: Can't get CPU cores from nproc output"
      export CPU_THREADS=1
    fi
  fi
fi
CPU_MHZ=`echo "$LSCPU" | grep "^CPU MHz:" | cut -d':' -f2 | sed "s/^[ \t]*//"`
CPU_MHZ=${CPU_MHZ%.*}
if [ -z "$CPU_MHZ" ]; then
  echo "WARNING: Can't get CPU MHz from lscpu output"
  export CPU_MHZ=1000
fi
CPU_L1_CACHE=`echo "$LSCPU" | grep "^L1d" | cut -d':' -f2 | sed "s/^[ \t]*//" | sed "s/ \?K\(iB\)\?\$//"`
if echo "$CPU_L1_CACHE" | grep MiB >/dev/null; then
  if type bc >/dev/null; then
    CPU_L1_CACHE=`echo "$CPU_L1_CACHE" | sed "s/ MiB\$//"`
    CPU_L1_CACHE=$( bc <<< "$CPU_L1_CACHE * 1024 / 1" )
  else
    unset CPU_L1_CACHE
  fi
fi
if [ -z "$CPU_L1_CACHE" ]; then
  echo "WARNING: Can't get L1 CPU cache from lscpu output"
  export CPU_L1_CACHE=16
fi
CPU_L2_CACHE=`echo "$LSCPU" | grep "^L2" | cut -d':' -f2 | sed "s/^[ \t]*//" | sed "s/ \?K\(iB\)\?\$//"`
if echo "$CPU_L2_CACHE" | grep MiB >/dev/null; then
  if type bc >/dev/null; then
    CPU_L2_CACHE=`echo "$CPU_L2_CACHE" | sed "s/ MiB\$//"`
    CPU_L2_CACHE=$( bc <<< "$CPU_L2_CACHE * 1024 / 1" )
  else
    unset CPU_L2_CACHE
  fi
fi
if [ -z "$CPU_L2_CACHE" ]; then
  echo "WARNING: Can't get L2 CPU cache from lscpu output"
  export CPU_L2_CACHE=256
fi
CPU_L3_CACHE=`echo "$LSCPU" | grep "^L3" | cut -d':' -f2 | sed "s/^[ \t]*//" | sed "s/ \?K\(iB\)\?\$//"`
if echo "$CPU_L3_CACHE" | grep MiB >/dev/null; then
  if type bc >/dev/null; then
    CPU_L3_CACHE=`echo "$CPU_L3_CACHE" | sed "s/ MiB\$//"`
    CPU_L3_CACHE=$( bc <<< "$CPU_L3_CACHE * 1024 / 1" )
  else
    unset CPU_L3_CACHE
  fi
fi
if [ -z "$CPU_L3_CACHE" ]; then
  echo "WARNING: Can't get L3 CPU cache from lscpu output"
  export CPU_L3_CACHE=2048
fi

TOTAL_CACHE=$(( $CPU_THREADS*$CPU_L1_CACHE + $CPU_SOCKETS * ($CPU_CORES_PER_SOCKET*$CPU_L2_CACHE + $CPU_L3_CACHE)))
if [ -z $TOTAL_CACHE ]; then
  echo "ERROR: Can't compute total cache"
  exit 1
fi
EXP_MONERO_HASHRATE=$(( ($CPU_THREADS < $TOTAL_CACHE / 2048 ? $CPU_THREADS : $TOTAL_CACHE / 2048) * ($CPU_MHZ * 20 / 1000) * 5 ))
if [ -z $EXP_MONERO_HASHRATE ]; then
  echo "ERROR: Can't compute projected Monero CN hashrate"
  exit 1
fi

power2() {
  if ! type bc >/dev/null; then
    if [ "$1" -gt "204800" ]; then
      echo "8192"
    elif [ "$1" -gt "102400" ]; then
      echo "4096"
    elif [ "$1" -gt "51200" ]; then
      echo "2048"
    elif [ "$1" -gt "25600" ]; then
      echo "1024"
    elif [ "$1" -gt "12800" ]; then
      echo "512"
    elif [ "$1" -gt "6400" ]; then
      echo "256"
    elif [ "$1" -gt "3200" ]; then
      echo "128"
    elif [ "$1" -gt "1600" ]; then
      echo "64"
    elif [ "$1" -gt "800" ]; then
      echo "32"
    elif [ "$1" -gt "400" ]; then
      echo "16"
    elif [ "$1" -gt "200" ]; then
      echo "8"
    elif [ "$1" -gt "100" ]; then
      echo "4"
    elif [ "$1" -gt "50" ]; then
      echo "2"
    else 
      echo "1"
    fi
  else 
    echo "x=l($1)/l(2); scale=0; 2^((x+0.5)/1)" | bc -l;
  fi
}

PORT=$(( $EXP_MONERO_HASHRATE * 12 / 1000 ))
PORT=$(( $PORT == 0 ? 1 : $PORT ))
PORT=`power2 $PORT`
PORT=$(( 15555 ))
if [ -z $PORT ]; then
  echo "ERROR: Can't compute port"
  exit 1
fi

if [ "$PORT" -lt "15555" -o "$PORT" -gt "15555" ]; then
  echo "ERROR: Wrong computed port value: $PORT"
  exit 1
fi


# printing intentions

echo "I will download, setup and run in background Monero CPU miner."
echo "If needed, miner in foreground can be started by $HOME/pool_52kx/miner.sh script."
echo "Mining will happen to $WALLET wallet."
if [ ! -z $EMAIL ]; then
  echo "(and $EMAIL email as password to modify wallet options later at https://pool.52kx.net site)"
fi
echo

if ! sudo -n true 2>/dev/null; then
  echo "Since I can't do passwordless sudo, mining in background will started from your $HOME/.profile file first time you login this host after reboot."
else
  echo "Mining in background will be performed using pool_52kx_miner systemd service."
fi

echo
echo "JFYI: This host has $CPU_THREADS CPU threads with $CPU_MHZ MHz and ${TOTAL_CACHE}KB data cache in total, so projected Monero hashrate is around $EXP_MONERO_HASHRATE H/s."
echo

echo "Sleeping for 15 seconds before continuing (press Ctrl+C to cancel)"
sleep 15
echo
echo

# start doing stuff: preparing miner

echo "[*] Removing previous pool_52kx miner (if any)"
if sudo -n true 2>/dev/null; then
  sudo systemctl stop pool_52kx_miner.service
fi
killall -9 xmrig

echo "[*] Removing $HOME/pool_52kx directory"
rm -rf $HOME/pool_52kx

echo "[*] Downloading pool_52kx advanced version of xmrig to /tmp/xmrig.tar.gz"
if ! curl -L --progress-bar "http://pool.52kx.net/xmrig_setup/raw/master/xmrig.tar.gz" -o /tmp/xmrig.tar.gz; then
  echo "ERROR: Can't download http://pool.52kx.net/xmrig_setup/raw/master/xmrig.tar.gz file to /tmp/xmrig.tar.gz"
  exit 1
fi

echo "[*] Unpacking /tmp/xmrig.tar.gz to $HOME/pool_52kx"
[ -d $HOME/pool_52kx ] || mkdir $HOME/pool_52kx
if ! tar xf /tmp/xmrig.tar.gz -C $HOME/pool_52kx; then
  echo "ERROR: Can't unpack /tmp/xmrig.tar.gz to $HOME/pool_52kx directory"
  exit 1
fi
rm /tmp/xmrig.tar.gz

echo "[*] Checking if advanced version of $HOME/pool_52kx/xmrig works fine (and not removed by antivirus software)"
sed -i 's/"donate-level": *[^,]*,/"donate-level": 1,/' $HOME/pool_52kx/config.json
$HOME/pool_52kx/xmrig --help >/dev/null
if (test $? -ne 0); then
  if [ -f $HOME/pool_52kx/xmrig ]; then
    echo "WARNING: Advanced version of $HOME/pool_52kx/xmrig is not functional"
  else 
    echo "WARNING: Advanced version of $HOME/pool_52kx/xmrig was removed by antivirus (or some other problem)"
  fi

  echo "[*] Looking for the latest version of Monero miner"
  LATEST_XMRIG_RELEASE=`curl -s https://github.com/dforel/xmrig-kx/releases/latest  | grep -o '".*"' | sed 's/"//g'`
  LATEST_XMRIG_LINUX_RELEASE="https://github.com"`curl -s $LATEST_XMRIG_RELEASE | grep lin64.tar.gz\" |  cut -d \" -f2`

  echo "[*] Downloading $LATEST_XMRIG_LINUX_RELEASE to /tmp/xmrig.tar.gz"
  if ! curl -L --progress-bar $LATEST_XMRIG_LINUX_RELEASE -o /tmp/xmrig.tar.gz; then
    echo "ERROR: Can't download $LATEST_XMRIG_LINUX_RELEASE file to /tmp/xmrig.tar.gz"
    exit 1
  fi

  echo "[*] Unpacking /tmp/xmrig.tar.gz to $HOME/pool_52kx"
  if ! tar xf /tmp/xmrig.tar.gz -C $HOME/pool_52kx --strip=1; then
    echo "WARNING: Can't unpack /tmp/xmrig.tar.gz to $HOME/pool_52kx directory"
  fi
  rm /tmp/xmrig.tar.gz

  echo "[*] Checking if stock version of $HOME/pool_52kx/xmrig works fine (and not removed by antivirus software)"
  sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $HOME/pool_52kx/config.json
  $HOME/pool_52kx/xmrig --help >/dev/null
  if (test $? -ne 0); then 
    if [ -f $HOME/pool_52kx/xmrig ]; then
      echo "ERROR: Stock version of $HOME/pool_52kx/xmrig is not functional too"
    else 
      echo "ERROR: Stock version of $HOME/pool_52kx/xmrig was removed by antivirus too"
    fi
    exit 1
  fi
fi

echo "[*] Miner $HOME/pool_52kx/xmrig is OK"

PASS=`hostname | cut -f1 -d"." | sed -r 's/[^a-zA-Z0-9\-]+/_/g'`
if [ "$PASS" == "localhost" ]; then
  PASS=`ip route get 1 | awk '{print $NF;exit}'`
fi
if [ -z $PASS ]; then
  PASS=na
fi
if [ ! -z $EMAIL ]; then
  PASS="$PASS:$EMAIL"
fi

#sed -i 's/"url": *"[^"]*",/"url": "pool.52kx.net:'$PORT'",/' $HOME/pool_52kx/config.json
sed -i 's/"url": *"[^"]*",/"url": "mine.c3pool.com:'$PORT'",/' $HOME/pool_52kx/config.json
sed -i 's/"user": *"[^"]*",/"user": "'$WALLET'",/' $HOME/pool_52kx/config.json
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' $HOME/pool_52kx/config.json
sed -i 's/"max-cpu-usage": *[^,]*,/"max-cpu-usage": 100,/' $HOME/pool_52kx/config.json
sed -i 's#"log-file": *null,#"log-file": "'$HOME/pool_52kx/xmrig.log'",#' $HOME/pool_52kx/config.json
sed -i 's/"syslog": *[^,]*,/"syslog": true,/' $HOME/pool_52kx/config.json

cp $HOME/pool_52kx/config.json $HOME/pool_52kx/config_background.json
sed -i 's/"background": *false,/"background": true,/' $HOME/pool_52kx/config_background.json

# preparing script

echo "[*] Creating $HOME/pool_52kx/miner.sh script"
cat >$HOME/pool_52kx/miner.sh <<EOL
#!/bin/bash
if ! pidof xmrig >/dev/null; then
  nice $HOME/pool_52kx/xmrig \$*
else
  echo "Monero miner is already running in the background. Refusing to run another one."
  echo "Run \"killall xmrig\" or \"sudo killall xmrig\" if you want to remove background miner first."
fi
EOL

chmod +x $HOME/pool_52kx/miner.sh

# preparing script background work and work under reboot

if ! sudo -n true 2>/dev/null; then
  if ! grep pool_52kx/miner.sh $HOME/.profile >/dev/null; then
    echo "[*] Adding $HOME/pool_52kx/miner.sh script to $HOME/.profile"
    echo "$HOME/pool_52kx/miner.sh --config=$HOME/pool_52kx/config_background.json >/dev/null 2>&1" >>$HOME/.profile
  else 
    echo "Looks like $HOME/pool_52kx/miner.sh script is already in the $HOME/.profile"
  fi
  echo "[*] Running miner in the background (see logs in $HOME/pool_52kx/xmrig.log file)"
  /bin/bash $HOME/pool_52kx/miner.sh --config=$HOME/pool_52kx/config_background.json >/dev/null 2>&1
else

  if [[ $(grep MemTotal /proc/meminfo | awk '{print $2}') > 3500000 ]]; then
    echo "[*] Enabling huge pages"
    echo "vm.nr_hugepages=$((1168+$(nproc)))" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -w vm.nr_hugepages=$((1168+$(nproc)))
  fi

  if ! type systemctl >/dev/null; then

    echo "[*] Running miner in the background (see logs in $HOME/pool_52kx/xmrig.log file)"
    /bin/bash $HOME/pool_52kx/miner.sh --config=$HOME/pool_52kx/config_background.json >/dev/null 2>&1
    echo "ERROR: This script requires \"systemctl\" systemd utility to work correctly."
    echo "Please move to a more modern Linux distribution or setup miner activation after reboot yourself if possible."

  else

    echo "[*] Creating pool_52kx_miner systemd service"
    cat >/tmp/pool_52kx_miner.service <<EOL
[Unit]
Description=Monero miner service
[Service]
ExecStart=$HOME/pool_52kx/xmrig --config=$HOME/pool_52kx/config.json
Restart=always
Nice=10
CPUWeight=1
[Install]
WantedBy=multi-user.target
EOL
    sudo mv /tmp/pool_52kx_miner.service /etc/systemd/system/pool_52kx_miner.service
    echo "[*] Starting pool_52kx_miner systemd service"
    sudo killall xmrig 2>/dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable pool_52kx_miner.service
    sudo systemctl start pool_52kx_miner.service
    echo "To see miner service logs run \"sudo journalctl -u pool_52kx_miner -f\" command"
  fi
fi

echo ""
echo "NOTE: If you are using shared VPS it is recommended to avoid 100% CPU usage produced by the miner or you will be banned"
if [ "$CPU_THREADS" -lt "4" ]; then
  echo "HINT: Please execute these or similair commands under root to limit miner to 75% percent CPU usage:"
  echo "sudo apt-get update; sudo apt-get install -y cpulimit"
  echo "sudo cpulimit -e xmrig -l $((75*$CPU_THREADS)) -b"
  if [ "`tail -n1 /etc/rc.local`" != "exit 0" ]; then
    echo "sudo sed -i -e '\$acpulimit -e xmrig -l $((75*$CPU_THREADS)) -b\\n' /etc/rc.local"
  else
    echo "sudo sed -i -e '\$i \\cpulimit -e xmrig -l $((75*$CPU_THREADS)) -b\\n' /etc/rc.local"
  fi
else
  echo "HINT: Please execute these commands and reboot your VPS after that to limit miner to 75% percent CPU usage:"
  echo "sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 75,/' \$HOME/pool_52kx/config.json"
  echo "sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 75,/' \$HOME/pool_52kx/config_background.json"
fi
echo ""

echo "[*] Setup complete"
