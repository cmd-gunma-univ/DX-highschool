sudo apt update
sudo apt install python3-pip libopencv-dev
pip3 install opencv-python numpy ultralytics supervision deep-sort-realtime mediapipe moviepy==1.0.3 --break-system-packages
pip install moviepy==1.0.3 --no-cache-dir --break-system-packages
pip install tensorflow-aarch64 --extra-index-url https://google-coral.github.io/py-repo/ --break-system-packages
pip3 install ml-dtypes==0.5.1 --break-system-packages --no-cache-dir
