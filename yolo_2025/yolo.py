from ultralytics import YOLO
import cv2

# モデルを読み込む（最軽量モデル）
model = YOLO('yolov8n.pt')  # 初回のみ自動ダウンロード

# カメラ初期化
cap = cv2.VideoCapture(0, cv2.CAP_V4L2)

# 解像度を下げる（320x240）
cap.set(cv2.CAP_PROP_FRAME_WIDTH, 320*4)
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 240*4)

while True:
    ret, frame = cap.read()
    if not ret:
        break

    # 推論（stream=Falseは画像単位）
    results = model(frame, verbose=False)[0]

    # 「person」クラス（class_id == 0）をカウント
    person_count = sum(1 for box in results.boxes if int(box.cls[0]) == 0)

    # 結果の描画
    annotated_frame = results.plot()
    cv2.putText(annotated_frame, f'Persons: {person_count}', (10, 40),
                cv2.FONT_HERSHEY_SIMPLEX, 1.2, (0, 255, 0), 2)

    # 表示
    cv2.imshow('YOLOv8 Person Counter', annotated_frame)

    # qキーで終了
    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()
