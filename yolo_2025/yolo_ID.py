from ultralytics import YOLO
import cv2
from deep_sort_realtime.deepsort_tracker import DeepSort

model = YOLO("yolov8n.pt")
tracker = DeepSort(max_age=5)

cap = cv2.VideoCapture(0)
cap.set(cv2.CAP_PROP_FRAME_WIDTH, 320*4)
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 240*4)

while True:
    ret, frame = cap.read()
    if not ret:
        break

    results = model(frame, verbose=False)[0]
    detections = []
    
    for box in results.boxes:
        if int(box.cls[0]) == 0:
            x1, y1, x2, y2 = box.xyxy[0].tolist()
            w, h = x2 - x1, y2 - y1
            conf = float(box.conf[0])
            detections.append([[x1, y1, w, h], conf])  # ← ここ重要
    tracks = tracker.update_tracks(detections, frame=frame)
    print(f"👥 現在の追跡人数: {len(tracks)}")

    for track in tracks:
        if not track.is_confirmed():
            continue
        track_id = track.track_id
        l, t, r, b = map(int, track.to_ltrb())
    
        # 中心座標の計算
        cx = int((l + r) / 2)
        cy = int((t + b) / 2)
    
        # 枠とIDを描画
        cv2.rectangle(frame, (l, t), (r, b), (0, 255, 0), 2)
        cv2.putText(frame, f'ID:{track_id}', (l, t - 10),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 255), 2)
    
        # 位置座標（中心）を描画
        cv2.circle(frame, (cx, cy), 3, (255, 0, 0), -1)
        cv2.putText(frame, f'({cx},{cy})', (cx + 5, cy),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)


    cv2.imshow("YOLOv8 + DeepSort", frame)
    if cv2.waitKey(1) & 0xFF == ord("q"):
        break

cap.release()
cv2.destroyAllWindows()
