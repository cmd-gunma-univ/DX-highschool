from ultralytics import YOLO
import cv2, time
import numpy as np

import matplotlib.pyplot as plt
from collections import deque
from IPython.display import Image, display, update_display

plt.ioff()  # ★ 自動で図が再表示されるのを防ぐ（重要）

# =========================
# モデル & 動画
# =========================
model = YOLO("yolov8n-pose.pt")

video_path = "Videos/squat.mp4"
cap = cv2.VideoCapture(video_path)
if not cap.isOpened():
    raise RuntimeError("動画が開けませんでした。パスを確認してください。")

# =========================
# 調整パラメータ
# =========================
RESIZE_W = 320
CONF = 0.35
INFER_EVERY = 3
DISPLAY_EVERY = 3
SLEEP = 0.0

KP_CONF_TH = 0.25

L_HIP, R_HIP       = 11, 12
L_KNEE, R_KNEE     = 13, 14
L_ANKLE, R_ANKLE   = 15, 16

DOWN_ANGLE_TH = 140
UP_ANGLE_TH   = 160
STABLE_FRAMES = 2

def angle_3pts(a, b, c):
    ba = a - b
    bc = c - b
    nba = np.linalg.norm(ba)
    nbc = np.linalg.norm(bc)
    if nba < 1e-6 or nbc < 1e-6:
        return None
    cosang = np.dot(ba, bc) / (nba * nbc)
    cosang = np.clip(cosang, -1.0, 1.0)
    return float(np.degrees(np.arccos(cosang)))

def get_knee_angle_one_person(kxy, kconf):
    def ok(i):
        return (kconf is None) or (kconf[i] >= KP_CONF_TH)

    candidates = []

    if ok(L_HIP) and ok(L_KNEE) and ok(L_ANKLE):
        ang = angle_3pts(kxy[L_HIP].astype(float), kxy[L_KNEE].astype(float), kxy[L_ANKLE].astype(float))
        if ang is not None:
            conf_score = (kconf[L_HIP] + kconf[L_KNEE] + kconf[L_ANKLE]) if kconf is not None else 1.0
            candidates.append((conf_score, ang))

    if ok(R_HIP) and ok(R_KNEE) and ok(R_ANKLE):
        ang = angle_3pts(kxy[R_HIP].astype(float), kxy[R_KNEE].astype(float), kxy[R_ANKLE].astype(float))
        if ang is not None:
            conf_score = (kconf[R_HIP] + kconf[R_KNEE] + kconf[R_ANKLE]) if kconf is not None else 1.0
            candidates.append((conf_score, ang))

    if not candidates:
        return None
    candidates.sort(reverse=True, key=lambda x: x[0])
    return candidates[0][1]

# =========================
# リアルタイムプロット準備
# =========================
MAX_POINTS = 200
angles = deque(maxlen=MAX_POINTS)
frames = deque(maxlen=MAX_POINTS)

fig, ax = plt.subplots(figsize=(7, 3))
(line,) = ax.plot([], [], linewidth=2)
ax.set_title("Knee Angle (live)")
ax.set_xlabel("frame (relative)")
ax.set_ylabel("deg")
ax.set_ylim(50, 180)
ax.set_xlim(0, 10)
fig.tight_layout()

display(fig, display_id="plot")
display(Image(data=b""), display_id="video")

# =========================
# スクワット状態機械（任意）
# =========================
state = "UP"
stable = 0
squat_count = 0

frame_i = 0
last_frame = None
last_angle = None

try:
    while True:
        ret, frame = cap.read()
        if not ret:
            print("動画終了")
            break

        frame_i += 1

        h, w = frame.shape[:2]
        scale = RESIZE_W / w
        frame_small = cv2.resize(frame, (RESIZE_W, int(h * scale)))

        if frame_i % INFER_EVERY == 0:
            results = model.predict(source=frame_small, imgsz=RESIZE_W, conf=CONF, verbose=False)[0]

            annotated = results.plot()
            last_angle = None

            if results.keypoints is not None and len(results.keypoints) > 0:
                kxy_all = results.keypoints.xy.cpu().numpy()
                kconf_all = None
                if hasattr(results.keypoints, "conf") and results.keypoints.conf is not None:
                    kconf_all = results.keypoints.conf.cpu().numpy()

                kxy = kxy_all[0]
                kconf = kconf_all[0] if kconf_all is not None else None
                last_angle = get_knee_angle_one_person(kxy, kconf)

            if last_angle is not None:
                want_state = None
                if last_angle <= DOWN_ANGLE_TH:
                    want_state = "DOWN"
                elif last_angle >= UP_ANGLE_TH:
                    want_state = "UP"

                if want_state is not None and want_state != state:
                    stable += 1
                    if stable >= STABLE_FRAMES:
                        if state == "DOWN" and want_state == "UP":
                            squat_count += 1
                        state = want_state
                        stable = 0
                else:
                    stable = 0

            angle_txt = f"{last_angle:.1f} deg" if last_angle is not None else "N/A"
            cv2.putText(annotated, f"KneeAngle: {angle_txt}", (10, 30),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 0, 255), 2, cv2.LINE_AA)
            cv2.putText(annotated, f"Squats: {squat_count}", (10, 65),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 0, 255), 2, cv2.LINE_AA)

            last_frame = annotated

            if last_angle is not None:
                frames.append(frame_i)
                angles.append(last_angle)

                f0 = frames[0]
                x_plot = [f - f0 for f in frames]

                line.set_data(x_plot, list(angles))
                ax.set_xlim(0, max(10, x_plot[-1]))
                ax.set_ylim(50, 180)

                fig.canvas.draw_idle()
                update_display(fig, display_id="plot")

        else:
            if last_frame is None:
                last_frame = frame_small

        if frame_i % DISPLAY_EVERY == 0:
            ok, jpg = cv2.imencode(".jpg", last_frame, [int(cv2.IMWRITE_JPEG_QUALITY), 75])
            if ok:
                update_display(Image(data=jpg.tobytes()), display_id="video")

        if SLEEP > 0:
            time.sleep(SLEEP)

except KeyboardInterrupt:
    print("⏹ 停止")

finally:
    cap.release()
    print("完了")
    print("スクワット回数:", squat_count)
    plt.close(fig)  # ★ 最後に図を閉じて二重表示を防ぐ（重要）

None  # ★ セル末尾の自動表示防止（保険）