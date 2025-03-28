import { useCallback, useEffect, useMemo, useRef } from "react";
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

enum InputSource {
  Keyboard,
  Gamepad,
  Display,
}

enum ButtonState {
  Unpressed,
  Pressed,
}

export function useSetupInputs(
  zgbc: Zgbc | null,
  gamepad: React.RefObject<Gamepad | null>,
  isMobile: boolean,
): {
  checkGamepadInputs: () => void;
} {
  const buttonStateMap = useMemo(
    () => ({
      [Button.Right]: ButtonState.Unpressed,
      [Button.Left]: ButtonState.Unpressed,
      [Button.Up]: ButtonState.Unpressed,
      [Button.Down]: ButtonState.Unpressed,
      [Button.A]: ButtonState.Unpressed,
      [Button.B]: ButtonState.Unpressed,
      [Button.Select]: ButtonState.Unpressed,
      [Button.Start]: ButtonState.Unpressed,
    }),
    [],
  );
  const initialInputStateMap = useMemo(
    () => ({
      [InputSource.Keyboard]: structuredClone(buttonStateMap),
      [InputSource.Gamepad]: structuredClone(buttonStateMap),
      [InputSource.Display]: structuredClone(buttonStateMap),
    }),
    [buttonStateMap],
  );
  const inputStateMap = useRef<
    Record<InputSource, Record<Button, ButtonState>>
  >(structuredClone(initialInputStateMap));

  const pressButton = useCallback(
    (inputSource: InputSource, button: Button) => {
      if (!zgbc) return;

      if (
        inputStateMap.current[inputSource][button] === ButtonState.Unpressed
      ) {
        inputStateMap.current[inputSource][button] = ButtonState.Pressed;
        zgbc.buttonPress(button);
      }
    },
    [zgbc],
  );

  const releaseButton = useCallback(
    (inputSource: InputSource, button: Button) => {
      if (!zgbc) return;

      if (inputStateMap.current[inputSource][button] === ButtonState.Pressed) {
        inputStateMap.current[inputSource][button] = ButtonState.Unpressed;
        zgbc.buttonRelease(button);
      }
    },
    [zgbc],
  );

  useEffect(() => {
    window.onkeydown = (e) => {
      const button = KEY_BUTTON_MAP[e.code];
      if (button !== undefined) {
        pressButton(InputSource.Keyboard, button);
      }
    };
    window.onkeyup = (e) => {
      const button = KEY_BUTTON_MAP[e.code];
      if (button !== undefined) {
        releaseButton(InputSource.Keyboard, button);
      }
    };
  }, [pressButton, releaseButton]);

  useEffect(() => {
    window.addEventListener("gamepadconnected", (e) => {
      gamepad.current = window.navigator.getGamepads()[e.gamepad.index];
    });
    window.addEventListener("gamepaddisconnected", () => {
      gamepad.current = null;
      inputStateMap.current = structuredClone(initialInputStateMap);
    });
  }, [gamepad, initialInputStateMap]);

  useEffect(() => {
    if (!isMobile) return;

    let lastPressed: Button | undefined = undefined;
    const classButtonMap: Record<string, Button> = {
      right: Button.Right,
      left: Button.Left,
      up: Button.Up,
      down: Button.Down,
      a: Button.A,
      b: Button.B,
      select: Button.Select,
      start: Button.Start,
    };

    const handleHover = (e: PointerEvent) => {
      const elem = document.elementFromPoint(e.x, e.y);
      if (!elem) return;

      const button = classButtonMap[elem.className];
      if (button === undefined) return;

      if (lastPressed !== button) {
        reset();
        pressButton(InputSource.Display, button);
        lastPressed = button;
      }
    };
    const handleDown = (e: PointerEvent) => {
      const elem = document.elementFromPoint(e.x, e.y);
      if (!elem) return;

      const button = classButtonMap[elem.className];
      if (button === undefined) return;

      pressButton(InputSource.Display, button);
    };
    const reset = () => {
      for (const button of Object.values(Button).filter(
        (b) => typeof b !== "string",
      )) {
        releaseButton(InputSource.Display, button);
      }
      lastPressed = undefined;
    };

    window.addEventListener("pointerdown", handleDown);
    window.addEventListener("pointermove", handleHover);
    window.addEventListener("pointerup", reset);

    return () => {
      window.removeEventListener("pointerdown", handleDown);
      window.removeEventListener("pointermove", handleHover);
      window.removeEventListener("pointerup", reset);
    };
  }, [isMobile, pressButton, releaseButton]);

  return {
    checkGamepadInputs: () => {
      if (gamepad.current === null) return;

      /// refresh gamepad state since this doesn't automatically happen on chrome
      gamepad.current = window.navigator.getGamepads()[gamepad.current.index];
      if (gamepad.current === null) return;

      for (const [idx, button] of GAMEPAD_BUTTON_MAP) {
        if (gamepad.current.buttons[idx].pressed) {
          pressButton(InputSource.Gamepad, button);
        } else {
          releaseButton(InputSource.Gamepad, button);
        }
      }
    },
  };
}
