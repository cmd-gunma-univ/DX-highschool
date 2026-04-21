#!/bin/bash
set -euo pipefail

PY_VER="3.11.15"
PY_PREFIX="/opt/python311"
VENV_DIR="$HOME/dx311"
JUPYTER_TOKEN=""
SERVICE_NAME="jupyterlab311"

echo "=== 1. apt update / upgrade ==="
sudo apt update -y
sudo apt upgrade -y

echo "=== 2. build tools / runtime packages ==="
sudo apt install -y \
  git curl wget ca-certificates xz-utils \
  build-essential pkg-config make \
  libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
  libffi-dev liblzma-dev tk-dev uuid-dev libgdbm-dev libnss3-dev \
  libncursesw5-dev libexpat1-dev \
  portaudio19-dev ffmpeg avahi-daemon network-manager \
  libcap-dev \
  python3-picamera2 python3-libcamera libcamera-apps-lite

echo "=== 3. cleanup old broken global installs (best effort) ==="
sudo python3 -m pip uninstall -y \
  torch torchvision torchaudio triton \
  facenet-pytorch fer \
  nvidia-cublas nvidia-cuda-cupti nvidia-cuda-nvrtc nvidia-cuda-runtime \
  nvidia-cudnn-cu13 nvidia-cufft nvidia-cufile nvidia-curand \
  nvidia-cusolver nvidia-cusparse nvidia-cusparselt-cu13 \
  nvidia-nccl-cu13 nvidia-nvjitlink nvidia-nvshmem-cu13 nvidia-nvtx \
  cuda-toolkit cuda-bindings cuda-pathfinder \
  tensorflow-aarch64 || true

echo "=== 4. build Python ${PY_VER} ==="
cd /tmp
if [ ! -f "Python-${PY_VER}.tgz" ]; then
  wget "https://www.python.org/ftp/python/${PY_VER}/Python-${PY_VER}.tgz"
fi

rm -rf "Python-${PY_VER}"
tar xf "Python-${PY_VER}.tgz"
cd "Python-${PY_VER}"

./configure \
  --prefix="${PY_PREFIX}" \
  --enable-optimizations \
  --with-lto \
  --enable-shared

make -j4
sudo make altinstall

echo "=== 5. refresh linker cache ==="
echo "${PY_PREFIX}/lib" | sudo tee /etc/ld.so.conf.d/python311.conf >/dev/null
sudo ldconfig

echo "=== 6. create venv ==="
if [ -d "${VENV_DIR}" ]; then
  echo "既存の venv を削除して作り直します: ${VENV_DIR}"
  rm -rf "${VENV_DIR}"
fi

"${PY_PREFIX}/bin/python3.11" -m venv --system-site-packages "${VENV_DIR}"
source "${VENV_DIR}/bin/activate"

echo "=== 7. pip upgrade ==="
python -m pip install --upgrade pip setuptools wheel

echo "=== 8. install Python packages for Pi 5 / Python 3.11 ==="
python -m pip install --no-cache-dir \
  jupyterlab \
  notebook \
  jupyter-server \
  ipykernel \
  ipywidgets \
  rpi-lgpio \
  gdown \
  numpy \
  matplotlib \
  pillow \
  sounddevice \
  librosa \
  opencv-contrib-python \
  supervision \
  deep-sort-realtime \
  moviepy==1.0.3 \
  ultralytics \
  tflite-runtime==2.14.0

echo "=== 8.5 register Jupyter kernel ==="
python -m ipykernel install --user --name dx311 --display-name "Python (dx311)" || true

echo "=== 8.6 set preferred kernel (best effort) ==="
mkdir -p "$HOME/.jupyter/lab/user-settings/@jupyterlab/notebook-extension"
cat > "$HOME/.jupyter/lab/user-settings/@jupyterlab/notebook-extension/tracker.jupyterlab-settings" <<EOF
{
  "preferredKernel": {
    "name": "dx311"
  }
}
EOF

echo "=== 9. quick sanity check ==="
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
]
for m in mods:
    try:
        __import__(m)
        print("[OK]", m)
    except Exception as e:
        print("[NG]", m, "->", e)
PYEOF

echo "=== 10. Jupyter config ==="
mkdir -p "$HOME/.jupyter"
cat > "$HOME/.jupyter/jupyter_lab_config.py" <<EOL
c.ServerApp.ip = "0.0.0.0"
c.ServerApp.port = 8888
c.ServerApp.open_browser = False
c.ServerApp.allow_root = False
c.ServerApp.allow_remote_access = True
c.ServerApp.token = "${JUPYTER_TOKEN}"
c.ServerApp.root_dir = "${HOME}"
c.ServerApp.base_url = "/"
c.ServerApp.trust_xheaders = True
EOL

echo "=== 11. systemd service ==="
cat > /tmp/${SERVICE_NAME}.service <<EOL
[Unit]
Description=Jupyter Lab (Python 3.11 venv)
After=network.target

[Service]
Type=simple
User=${USER}
WorkingDirectory=${HOME}
Environment=LD_LIBRARY_PATH=${PY_PREFIX}/lib
ExecStart=${VENV_DIR}/bin/jupyter-lab --config=${HOME}/.jupyter/jupyter_lab_config.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL

sudo mv /tmp/${SERVICE_NAME}.service /etc/systemd/system/${SERVICE_NAME}.service
sudo systemctl daemon-reload
sudo systemctl enable ${SERVICE_NAME}.service
sudo systemctl restart ${SERVICE_NAME}.service

echo "=== 12. avahi / ssh ==="
sudo systemctl enable avahi-daemon
sudo systemctl restart avahi-daemon
sudo systemctl enable ssh
sudo systemctl restart ssh

echo "=== 13. SPI / I2C ==="
if command -v raspi-config >/dev/null 2>&1; then
  sudo raspi-config nonint do_spi 0
  sudo raspi-config nonint do_i2c 0
else
  echo "raspi-config がないため SPI/I2C 設定はスキップ"
fi

echo "=== 14. locale fix (best effort) ==="
sudo locale-gen en_GB.UTF-8 ja_JP.UTF-8 || true
sudo update-locale LANG=en_GB.UTF-8 || true

echo "=== 15. status ==="
sudo systemctl is-active ${SERVICE_NAME}.service || true
sudo systemctl is-active ssh || true
lsmod | grep spi || true
lsmod | grep i2c || true

echo "=== DONE ==="
echo "Python: ${PY_PREFIX}/bin/python3.11"
echo "Venv  : ${VENV_DIR}"
echo "URL   : http://$(hostname).local:8888"
echo "Token : ${JUPYTER_TOKEN}"
echo
echo "Use:"
echo "  source ${VENV_DIR}/bin/activate"
echo "  python -V"
echo "  python -c 'import sys; print(sys.executable)'"
echo
echo "Jupyter kernel:"
echo "  Python (dx311)"
echo
echo "Camera check (system Python):"
echo "  python3 -c 'from picamera2 import Picamera2; print(\"picamera2 OK\")'"
