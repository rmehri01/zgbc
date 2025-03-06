import { useEffect } from "react";
import { Button, Zgbc } from "./wasm";

const KEY_BUTTON_MAP: Record<string, Button> = {
  KeyT: Button.Up,
  KeyW: Button.Down,
  KeyM: Button.Left,
  KeyV: Button.Right,
  Enter: Button.Start,
  Space: Button.Select,
  KeyU: Button.A,
  KeyE: Button.B,
};

export function useSetupInputs(zgbc: Zgbc | null) {
  useEffect(() => {
    window.onkeydown = (e) => {
      e.preventDefault();
      if (e.repeat) return;

      const button = KEY_BUTTON_MAP[e.code];
      if (button !== undefined) {
        zgbc?.buttonPress(button);
      }
    };
    window.onkeyup = (e) => {
      e.preventDefault();
      if (e.repeat) return;

      const button = KEY_BUTTON_MAP[e.code];
      if (button !== undefined) {
        zgbc?.buttonRelease(button);
      }
    };
  }, [zgbc]);
}
