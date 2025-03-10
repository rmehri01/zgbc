import { useEffect, useMemo, useState } from "react";
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

export function useSetupInputs(zgbc: Zgbc | null): {
  checkGamepadInputs: (zgbc: Zgbc | null) => void;
} {
  const pressRight = usePressButton(zgbc, Button.Right);
  const pressLeft = usePressButton(zgbc, Button.Left);
  const pressUp = usePressButton(zgbc, Button.Up);
  const pressDown = usePressButton(zgbc, Button.Down);
  const pressA = usePressButton(zgbc, Button.A);
  const pressB = usePressButton(zgbc, Button.B);
  const pressSelect = usePressButton(zgbc, Button.Select);
  const pressStart = usePressButton(zgbc, Button.Start);

  const pressButtonMap: Record<
    Button,
    React.Dispatch<React.SetStateAction<boolean>>
  > = useMemo(
    () => ({
      [Button.Right]: pressRight,
      [Button.Left]: pressLeft,
      [Button.Up]: pressUp,
      [Button.Down]: pressDown,
      [Button.A]: pressA,
      [Button.B]: pressB,
      [Button.Select]: pressSelect,
      [Button.Start]: pressStart,
    }),
    [
      pressRight,
      pressLeft,
      pressUp,
      pressDown,
      pressA,
      pressB,
      pressSelect,
      pressStart,
    ],
  );

  useEffect(() => {
    window.onkeydown = (e) => {
      const button = KEY_BUTTON_MAP[e.code];
      if (button !== undefined) {
        e.preventDefault();

        const pressButton = pressButtonMap[button];
        pressButton(true);
      }
    };
    window.onkeyup = (e) => {
      const button = KEY_BUTTON_MAP[e.code];
      if (button !== undefined) {
        e.preventDefault();

        const pressButton = pressButtonMap[button];
        pressButton(false);
      }
    };
  }, [zgbc, pressButtonMap]);

  const [gamepad, setGamepad] = useState<Gamepad | null>(null);

  useEffect(() => {
    window.addEventListener("gamepadconnected", (e) => {
      setGamepad(window.navigator.getGamepads()[e.gamepad.index]);
    });
    window.addEventListener("gamepaddisconnected", () => {
      setGamepad(null);
    });
  }, [zgbc]);

  return {
    checkGamepadInputs: (zgbc) => {
      if (!gamepad || !zgbc) return;

      for (const [idx, button] of GAMEPAD_BUTTON_MAP) {
        const pressButton = pressButtonMap[button];

        if (gamepad.buttons[idx].pressed) {
          pressButton(true);
        } else {
          pressButton(false);
        }
      }
    },
  };
}

function usePressButton(
  zgbc: Zgbc | null,
  button: Button,
): React.Dispatch<React.SetStateAction<boolean>> {
  const [buttonPressed, setButtonPressed] = useState(false);

  useEffect(() => {
    if (buttonPressed) {
      zgbc?.buttonPress(button);
    } else {
      zgbc?.buttonRelease(button);
    }
  }, [zgbc, buttonPressed, button]);

  return setButtonPressed;
}
