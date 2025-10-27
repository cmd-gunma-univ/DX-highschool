sudo apt update -y
sudo apt remove -y python3-opencv
sudo apt install -y python3-pip libopencv-dev --fix-missing
pip3 install numpy ultralytics supervision deep-sort-realtime mediapipe moviepy==1.0.3 --break-system-packages
pip3 install opencv-python opencv-python-headless opencv-contrib-python -y --break-system-packages
pip install moviepy==1.0.3 --no-cache-dir --break-system-packages
pip install tensorflow-aarch64 --extra-index-url https://google-coral.github.io/py-repo/ --break-system-packages
pip3 install ml-dtypes==0.5.1 fer==22.5.1 --break-system-packages --no-cache-dir
