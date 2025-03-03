import { useEffect } from "react";
import { Button, Zgbc } from "./wasm";

const KEY_BUTTON_MAP: Record<string, Button> = {
  KeyW: Button.Up,
  KeyS: Button.Down,
  KeyA: Button.Left,
  KeyD: Button.Right,
  Enter: Button.Start,
  Space: Button.Select,
  KeyK: Button.A,
  KeyJ: Button.B,
};

export function useSetupInputs(zgbc: Zgbc | null) {
  useEffect(() => {
    window.onkeydown = (e) => {
      if (e.repeat) return;

      const button = KEY_BUTTON_MAP[e.code];
      if (button !== undefined) {
        zgbc?.buttonPress(button);
      }
    };
    window.onkeyup = (e) => {
      if (e.repeat) return;

      const button = KEY_BUTTON_MAP[e.code];
      if (button !== undefined) {
        zgbc?.buttonRelease(button);
      }
    };
  }, [zgbc]);
}
