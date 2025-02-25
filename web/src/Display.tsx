import { useEffect, useRef } from "react";

export default function Display() {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  const draw = (ctx: CanvasRenderingContext2D, frameCount: number) => {
    ctx.fillStyle = "#000000";
    ctx.fillRect(0, 0, ctx.canvas.width, ctx.canvas.height);

    ctx.fillStyle = "#ffffff";
    ctx.beginPath();
    ctx.arc(
      ctx.canvas.width / 2,
      ctx.canvas.height / 2,
      50 * Math.sin(frameCount * 0.015) ** 2,
      0,
      2 * Math.PI,
    );
    ctx.fill();
  };

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const context = canvas.getContext("2d");
    if (!context) return;

    context.imageSmoothingEnabled = false;

    let frameCount = 0;
    let animationFrameId: number;

    const renderFrame = () => {
      frameCount++;
      draw(context, frameCount);
      animationFrameId = window.requestAnimationFrame(renderFrame);
    };

    renderFrame();

    return () => {
      window.cancelAnimationFrame(animationFrameId);
    };
  });

  return <canvas ref={canvasRef} width={160} height={144} />;
}
