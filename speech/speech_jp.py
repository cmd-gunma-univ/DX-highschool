import sounddevice as sd
import queue
import json
from vosk import Model, KaldiRecognizer

model = Model("vosk-model-small-ja-0.22")
rec = KaldiRecognizer(model, 16000)
q = queue.Queue()

def callback(indata, frames, time, status):
    q.put(bytes(indata))

with sd.RawInputStream(samplerate=16000, blocksize=8000, dtype='int16',
                       channels=1, callback=callback):
    print(" 話してください...")
    while True:
        data = q.get()
        if rec.AcceptWaveform(data):
            result = json.loads(rec.Result())
            print(f" 認識: {result['text']}")
