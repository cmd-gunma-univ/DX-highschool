from ultralytics import YOLO
import cv2

# YOLOv8 ポーズ推定モデルの読み込み（最軽量モデル）
model = YOLO("yolov8n-pose.pt")

# USBカメラの起動
cap = cv2.VideoCapture(0)
cap.set(cv2.CAP_PROP_FRAME_WIDTH, 320*4)
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 240*4)

while True:
    ret, frame = cap.read()
    if not ret:
        break

    # 推論実行（stream=Falseにすることで直接描画用の出力が得られる）
    results = model(frame, stream=False)[0]

    # 骨格を描画したフレームを取得
    annotated_frame = results.plot()

    # 表示
    cv2.imshow("YOLOv8 Pose Estimation", annotated_frame)

    # qキーで終了
    if cv2.waitKey(1) & 0xFF == ord("q"):
        break

# 解放
cap.release()
cv2.destroyAllWindows()
