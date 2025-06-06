import cv2
from fer import FER

# カメラを開く
cap = cv2.VideoCapture(0, cv2.CAP_V4L2)
detector = FER()

while True:
    ret, frame = cap.read()
    if not ret:
        break

    # 表情推定
    result = detector.top_emotion(frame)
    if result:
        emotion, score = result
        if emotion is not None and score is not None:
            label = f"{emotion} ({score:.2f})"
        else:
            label = "No face detected"
    else:
        label = "No face detected"

    # 結果を表示
    cv2.putText(frame, label, (10, 50),
                cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 0, 0), 2)

    cv2.imshow("Emotion", frame)
    # qキーで終了
    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()
