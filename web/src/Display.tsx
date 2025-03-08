import { useEffect, useRef } from "react";
import { SCREEN_HEIGHT, SCREEN_WIDTH, Zgbc } from "./wasm";

export default function Display({ zgbc }: { zgbc: Zgbc | null }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  const draw = (ctx: CanvasRenderingContext2D) => {
    if (!zgbc) return;

    for (let i = 0; i < 15000; i++) {
      zgbc.step();
    }
    const imageData = new ImageData(
      zgbc.pixels(),
      ctx.canvas.width,
      ctx.canvas.height,
    );
    ctx.putImageData(imageData, 0, 0);
  };

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const context = canvas.getContext("2d");
    if (!context) return;

    context.imageSmoothingEnabled = false;

    let animationFrameId: number;

    const renderFrame = () => {
      draw(context);
      animationFrameId = window.requestAnimationFrame(renderFrame);
    };

    renderFrame();

    return () => {
      window.cancelAnimationFrame(animationFrameId);
    };
  });

  return <canvas ref={canvasRef} width={SCREEN_WIDTH} height={SCREEN_HEIGHT} />;
}
