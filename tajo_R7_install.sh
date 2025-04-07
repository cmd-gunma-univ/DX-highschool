
#!/bin/bash


# サーバーのIPアドレスを入力
read -p "Enter server IP address: " SERVER_IP
# HOSTNAMEを入力
read -p "Enter server HOSTNAME (e.g., rp): " SERVER_HN


# 入力の確認
echo "============================"
echo "Server IP: $SERVER_IP"
echo "Server HOSTNAME: $SERVER_HN"
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

# 変数を設定
CON_NAME="tajo_5G"
SSID="PCROOM_5G"
PASSWORD="tajo1921"
PRIORITY=10 # 大きい方が優先度高

# 設定の追加
sudo nmcli connection add type wifi \
    con-name "$CON_NAME" \
    ifname wlan0 \
    ssid "$SSID" \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk $(wpa_passphrase "$SSID" "$PASSWORD" | grep "psk=" | grep -v "#" | awk -F= '{print $2}') \
    connection.autoconnect yes \
    connection.autoconnect-priority $PRIORITY \
    802-11-wireless.hidden false

# 変数を設定
CON_NAME="tajo"
SSID="PCROOM"
PASSWORD="tajo1921"
PRIORITY=9 # 大きい方が優先度高


# 変数を設定
CON_NAME="ASUS_2G"
SSID="ASUS_D8_2G"
PASSWORD="55nosbig"
PRIORITY=1 # 大きい方が優先度高

# 設定の追加
sudo nmcli connection add type wifi \
    con-name "$CON_NAME" \
    ifname wlan0 \
    ssid "$SSID" \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk $(wpa_passphrase "$SSID" "$PASSWORD" | grep "psk=" | grep -v "#" | awk -F= '{print $2}') \
    connection.autoconnect yes \
    connection.autoconnect-priority $PRIORITY \
    802-11-wireless.hidden false

# 設定の追加
sudo nmcli connection add type wifi \
    con-name "$CON_NAME" \
    ifname wlan0 \
    ssid "$SSID" \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk $(wpa_passphrase "$SSID" "$PASSWORD" | grep "psk=" | grep -v "#" | awk -F= '{print $2}') \
    connection.autoconnect yes \
    connection.autoconnect-priority $PRIORITY \
    802-11-wireless.hidden false



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
sudo systemctl enable ssh
sudo systemctl start ssh

# SPI を有効化
sudo raspi-config nonint do_spi 0

# I2C を有効化
sudo raspi-config nonint do_i2c 0

# 設定を確認
sudo systemctl is-active ssh
lsmod | grep spi
lsmod | grep i2c

# 変更を適用するための再起動
sudo reboot
