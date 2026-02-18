from ultralytics import YOLO
import cv2
import numpy as np

import matplotlib.pyplot as plt
from collections import deque
from IPython.display import Image, display, update_display

# ===== 検出専用モデル =====
model = YOLO("yolov8n.pt")

# ===== 入力動画 =====
video_path = "Videos/squat.mp4"
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
ratios = deque(maxlen=MAX_POINTS)   # h/w
ts = deque(maxlen=MAX_POINTS)

# ===== matplotlib 準備 =====
fig, ax = plt.subplots(figsize=(6, 3))
(line,) = ax.plot([], [], linewidth=2)
ax.set_title("BBox aspect ratio (h/w) (live)")
ax.set_xlabel("frame")
ax.set_ylabel("h/w")
fig.tight_layout()

# ===== 1回だけ枠を作る（同じ場所で更新する）=====
display(fig, display_id="plot")
display(Image(data=b""), display_id="video")  # 空の枠を確保

frame_i = 0
last_frame = None
last_ratio = None

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
            last_ratio = None

            # ===== 最大bboxの1人だけ =====
            if results.boxes is not None and len(results.boxes) > 0:
                boxes = results.boxes.xyxy.cpu().numpy()
                areas = (boxes[:, 2] - boxes[:, 0]) * (boxes[:, 3] - boxes[:, 1])
                idx = int(np.argmax(areas))

                x1, y1, x2, y2 = boxes[idx].astype(int)

                bw = max(1, (x2 - x1))
                bh = max(1, (y2 - y1))
                last_ratio = bh / bw  # 縦横比 (h/w)

                # bbox描画（確認用）
                cv2.rectangle(annotated, (x1, y1), (x2, y2), (0, 255, 0), 2)
                cv2.putText(
                    annotated, f"h/w={last_ratio:.2f}",
                    (10, 25), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 255), 2
                )

            last_frame = annotated

            # ===== グラフ更新（同じ場所で）=====
            if last_ratio is not None:
                ts.append(frame_i)
                ratios.append(last_ratio)

                t0 = ts[0]
                t_plot = [t - t0 for t in ts]

                line.set_data(t_plot, list(ratios))
                ax.set_xlim(0, max(10, t_plot[-1]))

                # ざっくり見やすい範囲（必要なら調整）
                rmin = min(ratios)
                rmax = max(ratios)
                pad = max(0.1, (rmax - rmin) * 0.2)
                ax.set_ylim(rmin - pad, rmax + pad)

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