#!/bin/bash

# サーバーのIPアドレスを入力
read -p "Enter server IP address: " SERVER_IP

# HOSTNAMEを入力
read -p "Enter server HOSTNAME (e.g., rp): " SERVER_HN


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


# 変更を適用するための再起動
sudo reboot
