#!/bin/bash
set -euo pipefail

PY_VER="3.11.15"
PY_PREFIX="/opt/python311"
VENV_DIR="$HOME/dx311"
KERNEL_NAME="dx311"
KERNEL_DISPLAY="Python (dx311)"
SERVICE_NAME="jupyterlab311"

echo "=== sudo 認証 ==="
sudo -v
while true; do
  sudo -n true
  sleep 60
  kill -0 "$$" || exit
done 2>/dev/null &

echo "=== apt update / upgrade ==="
sudo apt update -y
sudo apt upgrade -y

echo "=== 必要パッケージ導入 ==="
sudo apt install -y \
  nginx git curl wget ca-certificates xz-utils \
  build-essential pkg-config make \
  libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
  libffi-dev liblzma-dev tk-dev uuid-dev libgdbm-dev libnss3-dev \
  libncursesw5-dev libexpat1-dev \
  portaudio19-dev ffmpeg avahi-daemon network-manager \
  i2c-tools \
  python3-picamera2 python3-libcamera libcamera-apps-lite

echo "=== Python ${PY_VER} ソース取得 ==="
cd /tmp
if [ ! -f "Python-${PY_VER}.tgz" ]; then
  wget "https://www.python.org/ftp/python/${PY_VER}/Python-${PY_VER}.tgz"
fi

rm -rf "Python-${PY_VER}"
tar xf "Python-${PY_VER}.tgz"
cd "Python-${PY_VER}"

echo "=== Python ${PY_VER} configure ==="
./configure \
  --prefix="${PY_PREFIX}" \
  --enable-shared

echo "=== Python ${PY_VER} build ==="
make -j"$(nproc)"

echo "=== Python ${PY_VER} install ==="
sudo make altinstall

echo "=== ldconfig 更新 ==="
echo "${PY_PREFIX}/lib" | sudo tee /etc/ld.so.conf.d/python311.conf >/dev/null
sudo ldconfig

echo "=== Python 確認 ==="
"${PY_PREFIX}/bin/python3.11" --version

echo "=== venv 作成 ==="
rm -rf "${VENV_DIR}" || true
"${PY_PREFIX}/bin/python3.11" -m venv --system-site-packages "${VENV_DIR}"
source "${VENV_DIR}/bin/activate"

echo "=== pip 更新 ==="
python -m pip install --upgrade pip setuptools wheel

echo "=== Python ライブラリ導入 ==="
python -m pip install \
  jupyterlab notebook jupyter-server ipykernel \
  ipywidgets rpi-lgpio gdown \
  numpy matplotlib pillow sounddevice librosa \
  opencv-contrib-python supervision deep-sort-realtime \
  moviepy==1.0.3 ultralytics tflite-runtime==2.14.0

echo "=== Jupyter カーネル登録 ==="
python -m ipykernel install --user --name "${KERNEL_NAME}" --display-name "${KERNEL_DISPLAY}" || true

echo "=== Jupyter 優先カーネル設定 ==="
mkdir -p "$HOME/.jupyter/lab/user-settings/@jupyterlab/notebook-extension"
cat > "$HOME/.jupyter/lab/user-settings/@jupyterlab/notebook-extension/tracker.jupyterlab-settings" <<EOF
{
  "preferredKernel": {
    "name": "${KERNEL_NAME}"
  }
}
EOF

echo "=== Jupyter 設定 ==="
mkdir -p "$HOME/.jupyter"
cat > "$HOME/.jupyter/jupyter_lab_config.py" <<EOL
c.ServerApp.ip = "0.0.0.0"
c.ServerApp.port = 8888
c.ServerApp.open_browser = False
c.ServerApp.allow_root = False
c.ServerApp.token = ""
c.ServerApp.root_dir = "${HOME}"
c.ServerApp.max_body_size = 0
c.ServerApp.max_buffer_size = 0
EOL

echo "=== nginx 設定 ==="
cat > /tmp/jupyter <<'EOL'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    # ★追加（重要）
    client_max_body_size 2000M;

    location / {
        proxy_pass http://127.0.0.1:8888/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_buffering off;
    }
}
EOL

sudo mv /tmp/jupyter /etc/nginx/sites-available/jupyter
sudo ln -sf /etc/nginx/sites-available/jupyter /etc/nginx/sites-enabled/jupyter
sudo rm -f /etc/nginx/sites-enabled/default

echo "=== Jupyter systemd 登録 ==="
cat > /tmp/${SERVICE_NAME}.service <<EOL
[Unit]
Description=Jupyter Lab
After=network.target

[Service]
Type=simple
User=${USER}
WorkingDirectory=${HOME}
Environment=LD_LIBRARY_PATH=${PY_PREFIX}/lib
Environment=PATH=${VENV_DIR}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=${VENV_DIR}/bin/jupyter-lab --config=${HOME}/.jupyter/jupyter_lab_config.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL

sudo mv /tmp/${SERVICE_NAME}.service /etc/systemd/system/${SERVICE_NAME}.service
sudo systemctl daemon-reload
sudo systemctl enable ${SERVICE_NAME}
sudo systemctl restart ${SERVICE_NAME}

echo "=== RTC 設定（DS3231想定） ==="
sudo raspi-config nonint do_i2c 0 || true

CONFIG_FILE="/boot/firmware/config.txt"
if [ ! -f "$CONFIG_FILE" ]; then
  CONFIG_FILE="/boot/config.txt"
fi

if [ -f "$CONFIG_FILE" ]; then
  if ! grep -q "dtoverlay=i2c-rtc,ds3231" "$CONFIG_FILE"; then
    echo "dtoverlay=i2c-rtc,ds3231" | sudo tee -a "$CONFIG_FILE" >/dev/null
  fi
fi

sudo apt -y remove fake-hwclock || true
sudo systemctl disable fake-hwclock || true
sudo timedatectl set-timezone Asia/Tokyo || true
sudo timedatectl set-ntp true || true
sudo systemctl enable systemd-timesyncd || true
sudo systemctl restart systemd-timesyncd || true

echo "=== firstboot スクリプト作成 ==="
sudo tee /usr/local/sbin/firstboot-netsetup.sh >/dev/null <<'EOF'
#!/bin/bash
set -euo pipefail

BOOT="/boot/firmware"
[ -f "$BOOT/device.conf" ] || BOOT="/boot"

CONF="${BOOT}/device.conf"
DONE="/var/lib/firstboot.done"
LOG="/var/log/firstboot-netsetup.log"

exec > >(tee -a "$LOG") 2>&1

echo "===== firstboot start: $(date) ====="

if [ -f "$DONE" ]; then
  echo "already done"
  exit 0
fi

if [ ! -f "$CONF" ]; then
  echo "device.conf が見つかりません: $CONF"
  exit 1
fi

source "$CONF"

echo "=== hostname 設定 ==="
echo "${HOSTNAME}" > /etc/hostname
sed -i '/127.0.1.1/d' /etc/hosts
echo "127.0.1.1 ${HOSTNAME}.local ${HOSTNAME}" >> /etc/hosts
hostnamectl set-hostname "${HOSTNAME}.local"

echo "=== Wi-Fi / IP 設定 ==="
CONN="wlan0"

mkdir -p /etc/NetworkManager/system-connections

# 既存の netplan 接続を消す
nmcli connection delete "netplan-wlan0-${WIFI_SSID}" 2>/dev/null || true
nmcli connection delete "netplan-wlan0" 2>/dev/null || true
nmcli connection delete "${CONN}" 2>/dev/null || true

# 新しい接続を作成
nmcli connection add type wifi ifname wlan0 con-name "${CONN}" ssid "${WIFI_SSID}"

nmcli connection modify "${CONN}" \
  wifi-sec.key-mgmt wpa-psk \
  wifi-sec.psk "${WIFI_PASS}" \
  connection.autoconnect yes \
  ipv4.method manual \
  ipv4.addresses "${IPADDR}/${PREFIX}" \
  ipv4.gateway "${GATEWAY}" \
  ipv4.dns "${DNS}" \
  ipv4.ignore-auto-dns yes \
  ipv6.method ignore

# 接続を有効化
nmcli connection up "${CONN}"

echo "=== proxy 設定 ==="
if [ "${USE_PROXY:-no}" = "yes" ]; then
  cat > /etc/environment <<EOPROXY
http_proxy=${PROXY_URL}
https_proxy=${PROXY_URL}
HTTP_PROXY=${PROXY_URL}
HTTPS_PROXY=${PROXY_URL}
no_proxy=localhost,127.0.0.1
NO_PROXY=localhost,127.0.0.1
EOPROXY

  mkdir -p /etc/apt/apt.conf.d
  cat > /etc/apt/apt.conf.d/95proxy <<EOAPT
Acquire::http::Proxy "${PROXY_URL}/";
Acquire::https::Proxy "${PROXY_URL}/";
EOAPT

  mkdir -p /etc/pip
  cat > /etc/pip.conf <<EOPIP
[global]
proxy = ${PROXY_URL}
EOPIP

  CERT_NAME="sharedpx_ca_sha2.crt"
  if [ -f "${BOOT}/${CERT_NAME}" ]; then
    cp "${BOOT}/${CERT_NAME}" "/usr/local/share/ca-certificates/${CERT_NAME}"
    update-ca-certificates || true
  fi
else
  rm -f /etc/apt/apt.conf.d/95proxy
  rm -f /etc/pip.conf
fi

echo "=== NTP 設定 ==="
timedatectl set-timezone Asia/Tokyo || true

for i in $(seq 1 30); do
  if getent hosts ntp.nict.jp >/dev/null 2>&1 || getent hosts time.google.com >/dev/null 2>&1; then
    break
  fi
  echo "waiting DNS for NTP..."
  sleep 2
done

timedatectl set-ntp false || true
systemctl enable systemd-timesyncd || true
systemctl restart systemd-timesyncd || true
sleep 5
timedatectl set-ntp true || true

echo "=== cloud-init 無効化 ==="
touch /etc/cloud/cloud-init.disabled || true

echo "=== firstboot 完了 ==="
touch "$DONE"
systemctl disable firstboot-netsetup.service || true

echo "=== reboot ==="
reboot
EOF

sudo chmod +x /usr/local/sbin/firstboot-netsetup.sh

echo "=== firstboot systemd 作成 ==="
sudo tee /etc/systemd/system/firstboot-netsetup.service >/dev/null <<'EOF'
[Unit]
Description=First boot network and hostname setup
After=multi-user.target
ConditionPathExists=!/var/lib/firstboot.done

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/firstboot-netsetup.sh
RemainAfterExit=yes
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

echo "=== firstboot service 有効化 ==="
sudo systemctl daemon-reload
sudo systemctl enable firstboot-netsetup.service

echo "=== avahi / ssh / nginx 有効化 ==="
sudo systemctl enable nginx
sudo systemctl restart nginx
sudo systemctl enable avahi-daemon
sudo systemctl restart avahi-daemon
sudo systemctl enable ssh
sudo systemctl restart ssh

echo "=== SPI / I2C 有効化 ==="
if command -v raspi-config >/dev/null 2>&1; then
  sudo raspi-config nonint do_spi 0
  sudo raspi-config nonint do_i2c 0
fi

echo "=== locale 設定 ==="
sudo sed -i '/^# *ja_JP.UTF-8 UTF-8/s/^# *//' /etc/locale.gen
sudo sed -i '/^# *en_GB.UTF-8 UTF-8/s/^# *//' /etc/locale.gen
grep -q '^ja_JP.UTF-8 UTF-8' /etc/locale.gen || echo 'ja_JP.UTF-8 UTF-8' | sudo tee -a /etc/locale.gen
grep -q '^en_GB.UTF-8 UTF-8' /etc/locale.gen || echo 'en_GB.UTF-8 UTF-8' | sudo tee -a /etc/locale.gen
sudo locale-gen
sudo update-locale LANG=ja_JP.UTF-8


echo "=== 動作確認 ==="
python - <<'PYEOF'
import sys
print("Python:", sys.version)
mods = [
    "cv2",
    "numpy",
    "matplotlib",
    "librosa",
    "sounddevice",
    "ultralytics",
    "supervision",
    "tflite_runtime.interpreter",
    "gdown",
]
for m in mods:
    try:
        __import__(m)
        print("[OK]", m)
    except Exception as e:
        print("[NG]", m, "->", e)
PYEOF

echo "=== サービス状態 ==="
sudo systemctl is-active ${SERVICE_NAME} || true
sudo systemctl is-active nginx || true
sudo systemctl is-active ssh || true
sudo systemctl is-active firstboot-netsetup.service || true

echo "=== ゴールデンSD化のための注意 ==="
echo "このSDを複製したあと、各SDの boot パーティションに device.conf を置いてください。"
echo "プロキシありの場合のみ sharedpx_ca_sha2.crt も boot パーティションに置いてください。"

echo "=== 完了 ==="
echo "Python : ${PY_PREFIX}/bin/python3.11"
echo "Venv   : ${VENV_DIR}"
echo "Jupyter: http://$(hostname).local/"
echo
echo "次の作業:"
echo "  1. このSDをゴールデンSDとして複製"
echo "  2. 各SDの boot に device.conf を配置"
echo "  3. 初回起動で firstboot-netsetup.sh が実行される"
