from ultralytics import YOLO
import cv2
import numpy as np

import matplotlib.pyplot as plt
from collections import deque
from IPython.display import Image, display, update_display

# ===== 検出専用モデル =====
model = YOLO("yolov8n.pt")

# ===== 入力動画 =====
video_path = "Videos/squat.mp4"   # ←ここをsquat.mp4に
cap = cv2.VideoCapture(video_path)
if not cap.isOpened():
    raise RuntimeError("動画が開けませんでした。パスを確認してください。")

# ===== 高速化パラメータ =====
RESIZE_W = 320
CONF = 0.35
INFER_EVERY = 3
DISPLAY_EVERY = 3

# ===== プロット用 =====
MAX_POINTS = 200
ys = deque(maxlen=MAX_POINTS)
ts = deque(maxlen=MAX_POINTS)

# ===== matplotlib 準備 =====
fig, ax = plt.subplots(figsize=(6, 3))
(line,) = ax.plot([], [], linewidth=2)
ax.set_title("BBox center y (live)")
ax.set_xlabel("frame")
ax.set_ylabel("y")
fig.tight_layout()

# ===== 1回だけ枠を作る（同じ場所で更新する）=====
display(fig, display_id="plot")
display(Image(data=b""), display_id="video")  # 空の枠を確保

frame_i = 0
last_frame = None
last_y = None
H_resized = None  # リサイズ後の高さ

try:
    while True:
        ret, frame = cap.read()
        if not ret:
            print("動画終了")
            break

        frame_i += 1

        # 解像度を下げる（縦横比維持）
        h, w = frame.shape[:2]
        scale = RESIZE_W / w
        frame_small = cv2.resize(frame, (RESIZE_W, int(h * scale)))
        H_resized = frame_small.shape[0]

        # 推論は間引き
        if frame_i % INFER_EVERY == 0:
            results = model.predict(
                source=frame_small,
                imgsz=RESIZE_W,
                conf=CONF,
                classes=[0],     # personのみ
                verbose=False
            )[0]

            annotated = frame_small.copy()
            last_y = None

            # ===== 最大bboxの1人だけ =====
            if results.boxes is not None and len(results.boxes) > 0:
                boxes = results.boxes.xyxy.cpu().numpy()
                areas = (boxes[:, 2] - boxes[:, 0]) * (boxes[:, 3] - boxes[:, 1])
                idx = int(np.argmax(areas))

                x1, y1, x2, y2 = boxes[idx].astype(int)

                # bbox中心の y
                last_y = (y1 + y2) / 2.0

                # bbox描画（確認用）
                cv2.rectangle(annotated, (x1, y1), (x2, y2), (0, 255, 0), 2)
                cv2.putText(
                    annotated, f"y={last_y:.1f}",
                    (10, 25), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 255), 2
                )

            last_frame = annotated

            # ===== グラフ更新（同じ場所で）=====
            if last_y is not None:
                ts.append(frame_i)
                ys.append(last_y)

                t0 = ts[0]
                t_plot = [t - t0 for t in ts]

                line.set_data(t_plot, list(ys))
                ax.set_xlim(0, max(10, t_plot[-1]))
                ax.set_ylim(0, H_resized)   # yは「上が0、下がH」
                ax.set_ylim(100, 130)

                fig.canvas.draw()
                update_display(fig, display_id="plot")

        else:
            if last_frame is None:
                last_frame = frame_small

        # ===== 動画更新（同じ場所で）=====
        if frame_i % DISPLAY_EVERY == 0:
            ok, jpg = cv2.imencode(".jpg", last_frame, [int(cv2.IMWRITE_JPEG_QUALITY), 75])
            if ok:
                update_display(Image(data=jpg.tobytes()), display_id="video")

except KeyboardInterrupt:
    print("⏹ 停止")

finally:
    cap.release()
    print("完了")