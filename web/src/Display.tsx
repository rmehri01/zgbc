import { useEffect, useRef } from "react";
import {
  CLOCK_RATE,
  CYCLES_PER_FRAME,
  SCREEN_HEIGHT,
  SCREEN_WIDTH,
  Zgbc,
} from "./wasm";
import { loadAsync } from "jszip";

export default function Display({
  zgbc,
  checkGamepadInputs,
  updateAudio,
}: {
  zgbc: Zgbc | null;
  checkGamepadInputs: () => void;
  updateAudio: () => void;
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const romRef = useRef<HTMLInputElement>(null);

  const handleLoadROM = async (file: File) => {
    const buffer = await file.arrayBuffer();
    let bytes = new Uint8Array(buffer);

    if (file.name.endsWith(".zip")) {
      const zip = await loadAsync(bytes);
      bytes = await Object.values(zip.files)[0].async("uint8array");
    }

    zgbc?.loadROM(bytes);
  };

  useEffect(() => {
    if (!zgbc) return;

    const canvas = canvasRef.current;
    if (!canvas) return;

    const context = canvas.getContext("2d");
    if (!context) return;

    context.imageSmoothingEnabled = false;

    let animationFrameId: number;
    let lastTime = performance.now();
    let cyclesRemaining = 0;
    let paused = false;

    const renderFrame = (time: DOMHighResTimeStamp) => {
      if (!paused) {
        // run cpu cycles based on elapsed time
        const elapsedMs = time - lastTime;
        lastTime = time;

        cyclesRemaining += (CLOCK_RATE / 1000) * elapsedMs;
        const numFrames = Math.floor(cyclesRemaining / CYCLES_PER_FRAME);
        if (numFrames > 0) {
          for (let i = 0; i < numFrames; i++) {
            // update gamepad controller if attached
            checkGamepadInputs();

            // run one frame
            cyclesRemaining += zgbc.stepCycles(CYCLES_PER_FRAME);

            // update rendered state
            const imageData = new ImageData(
              zgbc.pixels(),
              context.canvas.width,
              context.canvas.height,
            );
            context.putImageData(imageData, 0, 0);

            // update audio
            updateAudio();
          }
        }

        cyclesRemaining -= numFrames * CYCLES_PER_FRAME;
      }

      animationFrameId = window.requestAnimationFrame(renderFrame);
    };

    renderFrame(lastTime);

    const pauseRendering = () => {
      if (document.visibilityState === "visible") {
        lastTime = performance.now();
        paused = false;
      } else {
        paused = true;
      }
    };

    window.addEventListener("visibilitychange", pauseRendering);

    return () => {
      window.cancelAnimationFrame(animationFrameId);
      window.removeEventListener("visibilitychange", pauseRendering);
    };
  }, [zgbc, checkGamepadInputs, updateAudio]);

  return (
    <>
      <canvas
        ref={canvasRef}
        onClick={(e) => {
          romRef.current?.click();
          e.currentTarget.blur();
        }}
        width={SCREEN_WIDTH}
        height={SCREEN_HEIGHT}
      />
      <input
        onChange={(e) => {
          void handleLoadROM(e.target.files![0]);
        }}
        multiple={false}
        ref={romRef}
        type="file"
        hidden
      />
    </>
  );
}
