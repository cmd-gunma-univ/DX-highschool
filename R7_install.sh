#!/bin/bash

# サーバーのIPアドレスを入力
read -p "Enter server IP address: " SERVER_IP
read -p "Enter gateway IP address: " GW_IP

# HOSTNAMEを入力
read -p "Enter server HOSTNAME (e.g., rp): " SERVER_HN

# 新しいSSIDとパスワードを入力
read -p "Enter SSID: " SSID
read -p "Enter Wi-Fi Password: " SSID_PW

# 入力の確認
echo "============================"
echo "Server IP Address: $SERVER_IP"
echo "Server HOSTNAME: $SERVER_HN"
echo "Server SSID: $SSID"
echo "Server SSID PW: $SSID_PW"
echo "============================"


# 確認のプロンプト
read -p "Is this correct? (y/n): " CONFIRM

# "n" または "N" が入力された場合にスクリプトを中止
if [[ "$CONFIRM" == "n" || "$CONFIRM" == "N" ]]; then
    echo "Installation aborted."
    exit 1
fi

# apt の更新
sudo apt -y update

# 必要なパッケージをインストール
sudo apt -y install nginx git portaudio19-dev python3-pip avahi-daemon network-manager

# JupyterLab のインストール
sudo pip3 install --break-system-packages jupyterlab

# 必要な Python ライブラリをインストール
sudo pip3 install --break-system-packages opencv-python opencv-contrib-python numpy matplotlib tflite-runtime pillow ipywidgets sounddevice librosa

# Jupyter Lab の設定ディレクトリを作成
mkdir -p $HOME/.jupyter
jupyter-lab --generate-config

# Nginx の設定ファイルを作成
echo "Nginx の設定を行います"
cat <<EOL > /tmp/jupyterlab_nginx
server {
    listen 80;
    server_name $SERVER_HN.local $SERVER_IP;

    location / {
        proxy_pass http://127.0.0.1:8888;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
        proxy_buffering off;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
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
c.ServerApp.token = '${JUPYTER_TOKEN:-dx-school}'
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

# Wi-Fi を NetworkManager で設定
echo "Connecting to new Wi-Fi network..."
sudo nmcli device wifi connect "$SSID" password "$SSID_PW"

# 接続確認
echo "Checking Wi-Fi connection..."
sleep 5
nmcli device status | grep wlan0

# 静的IPアドレスを設定
sudo nmcli connection modify $SSID ipv4.addresses $SERVER_IP/24 ipv4.gateway $GW_IP ipv4.dns "8.8.8.8,8.8.4.4" ipv4.method manual
sudo nmcli connection down $SSID && sudo nmcli connection up $SSID 

# SSH を有効化
sudo systemctl enable ssh
sudo systemctl start ssh

# SPI を有効化
sudo raspi-config nonint do_spi 0

# I2C を有効化
sudo raspi-config nonint do_i2c 0

# 設定を確認
echo "🔍 設定確認: SSH"
sudo systemctl is-active ssh

echo "🔍 設定確認: SPI"
lsmod | grep spi

echo "🔍 設定確認: I2C"
lsmod | grep i2c

# 変更を適用するための再起動
sudo reboot
