from ultralytics import YOLO
import cv2
from IPython.display import display, Image, clear_output
import numpy as np

# ===== 検出専用モデル =====
model = YOLO("yolov8n.pt")

video_path = "Videos/横断.mp4"
cap = cv2.VideoCapture(video_path)
if not cap.isOpened():
    raise RuntimeError("動画が開けませんでした。")

# ===== 高速化パラメータ =====
RESIZE_W = 320
CONF = 0.35
INFER_EVERY = 3
DISPLAY_EVERY = 3

# ===== 横断判定パラメータ =====
LEFT_TH = 100
RIGHT_TH = 200

# ===== カウント用状態 =====
state = "UNKNOWN"   # "LEFT" / "RIGHT" / "UNKNOWN"
L_to_R = 0
R_to_L = 0

frame_i = 0
last_annotated = None

try:
    while True:
        ret, frame = cap.read()
        if not ret:
            print("動画終了")
            break

        frame_i += 1

        # ===== 解像度を下げる =====
        h, w = frame.shape[:2]
        scale = RESIZE_W / w
        frame_small = cv2.resize(frame, (RESIZE_W, int(h * scale)))

        if frame_i % INFER_EVERY == 0:
            # ===== personのみ検出 =====
            results = model.predict(
                source=frame_small,
                imgsz=RESIZE_W,
                conf=CONF,
                classes=[0],
                verbose=False
            )[0]

            annotated = frame_small.copy()
            x_center = None

            # ===== 最大bboxの1人だけ =====
            if results.boxes is not None and len(results.boxes) > 0:
                boxes = results.boxes.xyxy.cpu().numpy()
                confs = results.boxes.conf.cpu().numpy()

                areas = (boxes[:, 2] - boxes[:, 0]) * (boxes[:, 3] - boxes[:, 1])
                idx = np.argmax(areas)

                x1, y1, x2, y2 = boxes[idx].astype(int)
                conf = confs[idx]
                x_center = (x1 + x2) / 2.0

                # bbox描画
                cv2.rectangle(annotated, (x1, y1), (x2, y2), (0, 255, 0), 2)
                cv2.putText(
                    annotated,
                    f"person {conf:.2f}",
                    (x1, max(0, y1 - 10)),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.7,
                    (0, 255, 0),
                    2
                )

            # ===== 横断カウント（ヒステリシス方式）=====
            # 200以上→RIGHT確定、100以下→LEFT確定、それ以外は状態維持
            if x_center is not None:
                prev = state

                if x_center >= RIGHT_TH:
                    state = "RIGHT"
                elif x_center <= LEFT_TH:
                    state = "LEFT"
                # else: 100 < x < 200 のときは state を変えない

                # 変化が確定した瞬間にカウント
                if prev == "RIGHT" and state == "LEFT":
                    R_to_L += 1
                elif prev == "LEFT" and state == "RIGHT":
                    L_to_R += 1

                # 画面に表示
                cv2.putText(
                    annotated,
                    f"L->R={L_to_R}  R->L={R_to_L}",
                    (10, 30),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.65,
                    (0, 0, 255),
                    2,
                    cv2.LINE_AA
                )
            last_annotated = annotated

        else:
            if last_annotated is None:
                last_annotated = frame_small

        # ===== 表示 =====
        if frame_i % DISPLAY_EVERY == 0:
            ok, jpg = cv2.imencode(".jpg", last_annotated, [int(cv2.IMWRITE_JPEG_QUALITY), 75])
            if ok:
                clear_output(wait=True)
                display(Image(data=jpg.tobytes()))

except KeyboardInterrupt:
    print("⏹ 停止")

finally:
    cap.release()
    print("完了")
    print("L to R:", L_to_R)
    print("R to L:", R_to_L)