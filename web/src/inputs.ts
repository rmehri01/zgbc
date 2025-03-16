import { useCallback, useEffect, useRef } from "react";
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

const GAMEPAD_BUTTON_MAP = new Map<number, Button>([
  [12, Button.Up],
  [13, Button.Down],
  [14, Button.Left],
  [15, Button.Right],
  [8, Button.Select],
  [9, Button.Start],
  [0, Button.B],
  [1, Button.A],
]);

enum ButtonState {
  unpressed,
  pressed,
}

export function useSetupInputs(zgbc: Zgbc | null): {
  checkGamepadInputs: () => void;
} {
  const buttonStateMap = useRef<Record<Button, ButtonState>>({
    [Button.Right]: ButtonState.unpressed,
    [Button.Left]: ButtonState.unpressed,
    [Button.Up]: ButtonState.unpressed,
    [Button.Down]: ButtonState.unpressed,
    [Button.A]: ButtonState.unpressed,
    [Button.B]: ButtonState.unpressed,
    [Button.Select]: ButtonState.unpressed,
    [Button.Start]: ButtonState.unpressed,
  });

  const pressButton = useCallback(
    (button: Button) => {
      if (buttonStateMap.current[button] === ButtonState.unpressed) {
        buttonStateMap.current[button] = ButtonState.pressed;
        zgbc?.buttonPress(button);
      }
    },
    [zgbc],
  );

  const releaseButton = useCallback(
    (button: Button) => {
      if (buttonStateMap.current[button] === ButtonState.pressed) {
        buttonStateMap.current[button] = ButtonState.unpressed;
        zgbc?.buttonRelease(button);
      }
    },
    [zgbc],
  );

  useEffect(() => {
    window.onkeydown = (e) => {
      const button = KEY_BUTTON_MAP[e.code];
      if (button !== undefined) {
        e.preventDefault();
        pressButton(button);
      }
    };
    window.onkeyup = (e) => {
      const button = KEY_BUTTON_MAP[e.code];
      if (button !== undefined) {
        e.preventDefault();
        releaseButton(button);
      }
    };
  }, [zgbc, pressButton, releaseButton]);

  const gamepad = useRef<Gamepad | null>(null);

  useEffect(() => {
    window.addEventListener("gamepadconnected", (e) => {
      gamepad.current = window.navigator.getGamepads()[e.gamepad.index];
    });
    window.addEventListener("gamepaddisconnected", () => {
      gamepad.current = null;
    });
  }, [zgbc]);

  return {
    checkGamepadInputs: () => {
      if (!gamepad.current) return;

      for (const [idx, button] of GAMEPAD_BUTTON_MAP) {
        if (gamepad.current.buttons[idx].pressed) {
          pressButton(button);
        } else {
          releaseButton(button);
        }
      }
    },
  };
}
