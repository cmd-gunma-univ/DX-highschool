#!/bin/bash

#!/usr/bin/env bash
set -euo pipefail

# ===== 入力 =====
read -rp "Raspberry Pi No. (1-254): " RPNo
if ! [[ "$RPNo" =~ ^[0-9]+$ ]] || [ "$RPNo" -lt 1 ] || [ "$RPNo" -gt 254 ]; then
  echo "ERROR: 1〜254 の整数で入力してください"; exit 1
fi

SERVER_IP="192.168.100.${RPNo}"
SERVER_HN="RP${RPNo}"

echo "============================"
echo "Server IP:      $SERVER_IP"
echo "Server HOSTNAME ${SERVER_HN}.local"
echo "============================"
read -rp "Is this correct? (y/n): " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Installation aborted."; exit 1; }

# ===== 準備 =====
sudo apt -y update
sudo apt -y install nginx git portaudio19-dev python3-pip avahi-daemon network-manager

# NetworkManager を有効化（dhcpcd がいたら停止）
if systemctl is-enabled dhcpcd 2>/dev/null | grep -q enabled; then
  echo "[INFO] disable dhcpcd"
  sudo systemctl disable --now dhcpcd || true
fi
echo "[INFO] enable NetworkManager"
sudo systemctl enable --now NetworkManager

# Wi-Fi国設定やブロック解除（失敗しても続行）
if command -v raspi-config >/dev/null 2>&1; then
  sudo raspi-config nonint do_wifi_country JP || true
fi
sudo rfkill unblock wifi || true

# ===== ホスト名設定 =====
echo "[INFO] set hostname: ${SERVER_HN}"
sudo hostnamectl set-hostname "$SERVER_HN"
# /etc/hosts 更新（127.0.1.1 行）
if grep -qE '^127\.0\.1\.1' /etc/hosts; then
  sudo sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t${SERVER_HN}/" /etc/hosts
else
  echo -e "127.0.1.1\t${SERVER_HN}" | sudo tee -a /etc/hosts >/dev/null
fi

# ===== 変数 =====
GATEWAY="192.168.100.1"
DNS="8.8.8.8,1.1.1.1"

CON_NAME="dx-school5"
SSID="dx-school5"
PASSWORD="dx-school"
PRIORITY=9

# Wi-Fi IF 自動検出（必要なら固定で書き換え）
WIFI_IF="$(nmcli -t -f DEVICE,TYPE device status | awk -F: '$2=="wifi"{print $1; exit}')"
if [ -z "$WIFI_IF" ]; then
  echo "ERROR: Wi-Fi インタフェースが見つかりません"; nmcli device status; exit 1
fi
echo "[INFO] Wi-Fi IF: $WIFI_IF"

# IP重複の簡易チェック
if ping -c1 -W1 "$SERVER_IP" >/dev/null 2>&1; then
  read -rp "WARNING: $SERVER_IP は応答あり（重複の可能性）。続行しますか？ [y/N]: " ans
  [[ "$ans" =~ ^[Yy]$ ]] || { echo "中止しました。"; exit 1; }
fi

# ===== 既存プロファイルの削除（同名のみ） =====
if nmcli -t -f NAME connection show | grep -Fxq "$CON_NAME"; then
  echo "[INFO] delete existing connection: $CON_NAME"
  sudo nmcli connection delete "$CON_NAME"
fi

# ※ 全接続ファイル削除は危険なので既定ではしない
# sudo rm -f /etc/NetworkManager/system-connections/*.nmconnection || true
# sudo nmcli connection reload

# ===== 新規 Wi-Fi プロファイル作成 =====
sudo nmcli connection add type wifi con-name "$CON_NAME" ifname "$WIFI_IF" ssid "$SSID"
sudo nmcli connection modify "$CON_NAME" \
  wifi-sec.key-mgmt "wpa-psk" \
  wifi-sec.psk "$PASSWORD" \
  connection.autoconnect yes \
  connection.autoconnect-priority "$PRIORITY" \
  ipv4.addresses "${SERVER_IP}/24" \
  ipv4.gateway "$GATEWAY" \
  ipv4.dns "$DNS" \
  ipv4.method manual
# IPv6不要なら：
# sudo nmcli connection modify "$CON_NAME" ipv6.method ignore

# 反映
sudo nmcli connection down "$CON_NAME" || true
sudo nmcli connection up   "$CON_NAME"

# JupyterLab のインストール
sudo pip3 install --break-system-packages jupyterlab

# 必要な Python ライブラリをインストール
sudo pip3 install --break-system-packages opencv-python opencv-contrib-python numpy matplotlib tflite-runtime pillow ipywidgets sounddevice librosa 

# YOLO関係
pip3 install numpy ultralytics supervision deep-sort-realtime mediapipe moviepy==1.0.3 --break-system-packages
pip3 install opencv-python opencv-python-headless opencv-contrib-python -y --break-system-packages
pip install moviepy==1.0.3 --no-cache-dir --break-system-packages
pip install tensorflow-aarch64 --extra-index-url https://google-coral.github.io/py-repo/ --break-system-packages
pip3 install ml-dtypes==0.5.1 --break-system-packages --no-cache-dir

# Jupyter Lab の設定ディレクトリを作成
mkdir -p $HOME/.jupyter
jupyter-lab --generate-config


# Nginx の設定ファイルを作成
echo "Nginx の設定を行います"
cat <<EOL > /tmp/jupyterlab_nginx
server {
    listen 80;
    server_name $SERVER_HN.local $SERVER_IP;
    client_max_body_size 1000M;
    location / {
        proxy_pass http://127.0.0.1:8888/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        # WebSocket サポート
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_buffering off;
    }
}
EOL

sudo mv /tmp/jupyterlab_nginx /etc/nginx/sites-available/jupyterlab
sudo ln -s /etc/nginx/sites-available/jupyterlab /etc/nginx/sites-enabled/

# Jupyter Lab の設定ファイルを作成
echo "Jupyter Lab の設定を行います"
cat <<EOL > $HOME/.jupyter/jupyter_lab_config.py
c.ServerApp.ip = '0.0.0.0'
c.ServerApp.port = 8888
c.NotebookApp.allow_remote_access = True
c.ServerApp.open_browser = False
c.ServerApp.allow_root = True
c.ServerApp.token = ''
c.ServerApp.notebook_dir = '$HOME'
c.ServerApp.base_url = '/'
c.ServerApp.trust_xheaders = True
EOL

# JupyterLab の systemd サービスファイルを作成
echo "JupyterLab の systemd サービスを設定します"
cat <<EOL > /tmp/Jupyterlab.service
[Unit]
Description=Jupyter Lab
After=network.target

[Service]
Type=simple
User=$USER
ExecStart=/usr/local/bin/jupyter-lab --config=/home/$USER/.jupyter/jupyter_lab_config.py
WorkingDirectory=/home/$USER
Restart=always

[Install]
WantedBy=multi-user.target
EOL

sudo mv /tmp/Jupyterlab.service /etc/systemd/system/Jupyterlab.service

# systemd に登録して起動
sudo systemctl daemon-reload
sudo systemctl enable Jupyterlab.service
sudo systemctl start Jupyterlab.service
# Nginx を再起動
sudo systemctl restart nginx


# ホスト名の変更
echo "Changing hostname to $SERVER_HN..."
echo "$SERVER_HN" | sudo tee /etc/hostname > /dev/null

# /etc/hosts の変更
echo "Updating /etc/hosts..."
sudo sed -i "s/127.0.1.1.*/127.0.1.1 $SERVER_HN.local/" /etc/hosts

# hostnamectl で設定変更
echo "Applying hostname with hostnamectl..."
sudo hostnamectl set-hostname "$SERVER_HN.local"

# avahi-daemon の有効化（mDNS 用）
echo "Ensuring avahi-daemon is running for .local resolution..."
sudo systemctl enable avahi-daemon
sudo systemctl restart avahi-daemon


# SSH を有効化
sudo systemctl --now enable ssh
sudo systemctl start ssh

# SPI を有効化
sudo raspi-config nonint do_spi 0

# I2C を有効化
sudo raspi-config nonint do_i2c 0

# 設定を確認
sudo systemctl is-active ssh
lsmod | grep spi
lsmod | grep i2c

# 終了
sudo shutdown -h now
