# Vamp Companion 0.1.10 (14)

A stability fix for Mac Control live video.

- Fixed a crash when the Mac locked or switched users while an iPhone was
  watching the screen. Companion now finishes the frame it is encoding before
  it stops the video encoder.

Everything from 0.1.9 is included: the new design that matches the iPhone app,
bundled llama.cpp and Prism runtimes, LFM3 Omni media tools, Bonsai 2 support,
and MLX Swift 0.32.3. Existing model files, settings, and paired devices are
kept.
