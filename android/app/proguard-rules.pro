# tflite_flutter exposes an optional Java GPU delegate. This app uses the
# package's native interpreter and does not instantiate that delegate.
-dontwarn org.tensorflow.lite.gpu.GpuDelegateFactory$Options
