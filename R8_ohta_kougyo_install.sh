
#!/bin/bash


# apt の更新
sudo apt -y update

# 必要なパッケージをインストール
sudo apt -y install git portaudio19-dev python3-pip avahi-daemon network-manager

# JupyterLab のインストール
sudo pip3 install --break-system-packages jupyterlab

# 必要な Python ライブラリをインストール
sudo pip3 install --break-system-packages matplotlib tflite-runtime pillow ipywidgets sounddevice librosa

sudo apt remove -y python3-opencv
sudo apt install -y python3-pip libopencv-dev --fix-missing
pip3 install numpy ultralytics supervision deep-sort-realtime mediapipe moviepy==1.0.3 --break-system-packages
pip3 install opencv-python opencv-python-headless opencv-contrib-python -y --break-system-packages
pip install moviepy==1.0.3 --no-cache-dir --break-system-packages
pip install tensorflow-aarch64 --extra-index-url https://google-coral.github.io/py-repo/ --break-system-packages
pip3 install ml-dtypes==0.5.1 fer==22.5.1 --break-system-packages --no-cache-dir

# Jupyter Lab の設定ディレクトリを作成
mkdir -p $HOME/.jupyter
jupyter-lab --generate-config

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
