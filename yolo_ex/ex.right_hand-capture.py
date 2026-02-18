from ultralytics import YOLO
import cv2
from IPython.display import display, Image, clear_output

import numpy as np

# ===== モデル =====
model = YOLO("yolov8n-pose.pt")

# ===== カメラ =====
cap = cv2.VideoCapture(0)
if not cap.isOpened():
    raise RuntimeError("カメラが開けませんでした")

# 解像度（高速化）
cap.set(cv2.CAP_PROP_FRAME_WIDTH, 320)
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 240)

# ===== 高速化 =====
INFER_EVERY = 3
DISPLAY_EVERY = 3

# ===== 右手挙げ判定 =====
R_SHOULDER = 6
R_WRIST = 10
KP_CONF_TH = 0.3

frame_i = 0
last_annotated = None
captured = False

try:
    while True:
        ret, frame = cap.read()
        if not ret:
            break

        frame_i += 1

        # ===== 推論 =====
        if frame_i % INFER_EVERY == 0:
            results = model.predict(
                source=frame,
                imgsz=256,
                conf=0.35,
                verbose=False
            )[0]

            last_annotated = results.plot()

            # ===== キーポイント取得（安全に）=====
            if results.keypoints is not None:
                kxy_all = results.keypoints.xy.cpu().numpy()  # (N, K, 2)

                # 人がいない / keypointsが空 の両方を弾く
                if kxy_all.ndim == 3 and kxy_all.shape[0] >= 1 and kxy_all.shape[1] >= 11:
                    kxy = kxy_all[0]  # 1人目

                    # conf も同様に安全に
                    kconf = None
                    if hasattr(results.keypoints, "conf") and results.keypoints.conf is not None:
                        kconf_all = results.keypoints.conf.cpu().numpy()  # (N, K)
                        if kconf_all.ndim == 2 and kconf_all.shape[0] >= 1 and kconf_all.shape[1] >= 11:
                            kconf = kconf_all[0]

                    def ok(i):
                        return (kconf is None) or (kconf[i] > KP_CONF_TH)

                    if ok(R_WRIST) and ok(R_SHOULDER):
                        wrist_y = float(kxy[R_WRIST, 1])
                        shoulder_y = float(kxy[R_SHOULDER, 1])

                        # ===== 右手を挙げたら撮影して終了 =====
                        if wrist_y < shoulder_y and not captured:
                            filename = "right_hand.jpg"
                            cv2.imwrite(filename, frame)
                            print("📸 撮影しました:", filename)
                            captured = True
                            break

        # ===== 表示 =====
        if frame_i % DISPLAY_EVERY == 0 and last_annotated is not None:
            ok, jpg = cv2.imencode(".jpg", last_annotated, [int(cv2.IMWRITE_JPEG_QUALITY), 70])
            if ok:
                clear_output(wait=True)
                display(Image(data=jpg.tobytes()))

except KeyboardInterrupt:
    print("停止")

finally:
    cap.release()
    print("完了")