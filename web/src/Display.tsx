import { useEffect, useRef } from "react";
import { CLOCK_RATE, SCREEN_HEIGHT, SCREEN_WIDTH, Zgbc } from "./wasm";

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
        // update gamepad controller if attached
        checkGamepadInputs();

        // run cpu cycles based on elapsed time
        const elapsedMs = time - lastTime;
        lastTime = time;

        const cycles = (CLOCK_RATE / 1000) * elapsedMs + cyclesRemaining;
        const wholeCycles = Math.floor(cycles);
        cyclesRemaining = cycles - wholeCycles;
        cyclesRemaining += zgbc.stepCycles(wholeCycles);

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

      animationFrameId = window.requestAnimationFrame(renderFrame);
    };

    renderFrame(lastTime);

    const pauseRendering = () => {
      if (document.visibilityState === "visible") {
        lastTime = performance.now();
        cyclesRemaining = 0;
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

  return <canvas ref={canvasRef} width={SCREEN_WIDTH} height={SCREEN_HEIGHT} />;
}
