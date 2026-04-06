# Heilmeiter Answers

1. What are you trying to do?

I want to build an accelerator to perform one specific math-heavy step in an object detection system - the step where the system scans across an image looking for patterns like edges, shapes, and textures. Today this runs on general-purpose processors that waste energy doing things my task doesn't need. My chip does only this one operation, so it can do it faster and with less power. The goal is a chip that could sit inside a small camera or sensor and find objects in images without needing a big computer.

2. How is it done today, and what are the limits of current practice?
Today, object detection models like YOLO run on either GPUs (fast but power-hungry, too expensive for small devices) or CPUs (available everywhere but slow for this workload). The bottleneck is the convolutional layers — they require billions of multiply-and-add operations per image. On a typical laptop CPU, a single YOLO-nano inference takes roughly 20–50ms, and most of that time is spent in convolutions. Mobile and edge devices either can't run these models at useful speeds, or they drain the battery doing so. Existing edge AI chips (like Google's Edge TPU) solve this but are fixed products you can't customize for your specific model or deployment constraints.

3. What is new in your approach and why do you think it will be successful?
I'm designing a custom convolution engine specifically tuned for the dominant layer shape in YOLO-nano, using 8-bit integer arithmetic instead of floating point. This reduces the size of each multiply unit by roughly 4× compared to FP32 and cuts memory bandwidth proportionally. The architecture streams image data through the chip continuously rather than loading and storing tiles, which avoids the memory bottleneck that limits general-purpose processors. I believe it will be successful because the arithmetic intensity of 3×3 convolution is well-understood and high enough that a dedicated compute array should be compute-bound rather than memory-bound — meaning the chip's throughput scales directly with how many multipliers I can fit, and INT8 lets me fit more.

