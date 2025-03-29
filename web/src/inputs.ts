import "./inputs.css";
import { useCallback, useEffect, useMemo, useRef } from "react";
import { Button, Zgbc } from "./wasm";
import { KEYBINDINGS_PREFIX } from "./KeybindingRow";

export const KEY_BUTTON_MAP: Record<string, Button> = {
  KeyW: Button.Up,
  KeyS: Button.Down,
  KeyA: Button.Left,
  KeyD: Button.Right,
  Enter: Button.Start,
  Space: Button.Select,
  KeyK: Button.A,
  KeyJ: Button.B,
};
export const BUTTON_KEY_MAP: Record<Button, string> = {
  [Button.Up]: "KeyW",
  [Button.Down]: "KeyS",
  [Button.Left]: "KeyA",
  [Button.Right]: "KeyD",
  [Button.Start]: "Enter",
  [Button.Select]: "Space",
  [Button.A]: "KeyK",
  [Button.B]: "KeyJ",
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
    for (const button of Object.values(Button).filter(
      (b) => typeof b !== "string",
    )) {
      const keybinding = window.localStorage.getItem(
        `${KEYBINDINGS_PREFIX}${button}`,
      );
      if (keybinding) {
        KEY_BUTTON_MAP[keybinding] = button;
        BUTTON_KEY_MAP[button] = keybinding;
      }
    }
  }, []);

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

    const lastTouchedMap: Record<number, Button | undefined> = {};
    const classButtonMap: Record<string, Button> = {
      right: Button.Right,
      left: Button.Left,
      up: Button.Up,
      down: Button.Down,
      a: Button.A,
      b: Button.B,
      select: Button.Select,
      start: Button.Start,
      "select-text slanted-text": Button.Select,
      "start-text slanted-text": Button.Start,
    };

    const handleHold = (e: PointerEvent) => {
      e.preventDefault();

      const elem = document.elementFromPoint(e.x, e.y);
      if (!elem) return;

      const button = classButtonMap[elem.className];
      if (button === undefined) return;

      if (lastTouchedMap[e.pointerId] !== button) {
        resetId(e.pointerId);
        pressButton(InputSource.Display, button);
        lastTouchedMap[e.pointerId] = button;
      }
    };
    const handleDown = (e: PointerEvent) => {
      e.preventDefault();

      const elem = document.elementFromPoint(e.x, e.y);
      if (!elem) return;

      const button = classButtonMap[elem.className];
      if (button === undefined) return;

      pressButton(InputSource.Display, button);
      lastTouchedMap[e.pointerId] = button;
    };
    const handleUp = (e: PointerEvent) => {
      e.preventDefault();
      resetId(e.pointerId);
    };
    const resetId = (pointerId: number) => {
      if (lastTouchedMap[pointerId] !== undefined) {
        releaseButton(InputSource.Display, lastTouchedMap[pointerId]);
        delete lastTouchedMap[pointerId];
      }
    };

    window.addEventListener("pointerdown", handleDown);
    window.addEventListener("pointermove", handleHold);
    window.addEventListener("pointerup", handleUp);

    const eventParams = { passive: false };
    const ignore = (e: TouchEvent) => {
      if (!e.target) return;

      if (e.target instanceof Element) {
        const button = classButtonMap[e.target.className];
        if (button === undefined) return;

        e.preventDefault();
      }
    };
    document.body.addEventListener("touchend", ignore, eventParams);

    return () => {
      window.removeEventListener("pointerdown", handleDown);
      window.removeEventListener("pointermove", handleHold);
      window.removeEventListener("pointerup", handleUp);
      document.body.removeEventListener("touchend", ignore);
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
