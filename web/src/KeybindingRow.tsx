import { useCallback, useEffect, useState } from "react";
import { Button } from "./wasm";
import { BUTTON_KEY_MAP, KEY_BUTTON_MAP } from "./inputs";

export const KEYBINDINGS_PREFIX = "keybindings__";

export function KeybindingRow({ buttonName }: { buttonName: string }) {
  const button = Button[buttonName as keyof typeof Button];
  const [currentKey, setCurrentKey] = useState(BUTTON_KEY_MAP[button]);
  const [setting, setSetting] = useState(false);

  const captureInput = useCallback(
    (e: KeyboardEvent) => {
      if (e.code !== "KeyEscape") {
        e.preventDefault();

        delete KEY_BUTTON_MAP[currentKey];
        BUTTON_KEY_MAP[button] = e.code;
        KEY_BUTTON_MAP[e.code] = button;
        setCurrentKey(e.code);

        window.localStorage.setItem(`${KEYBINDINGS_PREFIX}${button}`, e.code);
      }

      setSetting(false);
    },
    [button, currentKey],
  );

  useEffect(() => {
    if (setting) {
      window.addEventListener("keydown", captureInput);
    }

    return () => {
      window.removeEventListener("keydown", captureInput);
    };
  }, [setting, captureInput]);

  return (
    <tr>
      <td>
        <h2>{buttonName}:</h2>
      </td>

      <td>
        <button
          onClick={() => {
            setSetting(!setting);
          }}
        >
          {setting
            ? "Press a key..."
            : currentKey
                .replace("Key", "")
                .replace("Arrow", "")
                .replace("Right", "→")
                .replace("Left", "←")
                .replace("Up", "↑")
                .replace("Down", "↓")}
        </button>
      </td>
    </tr>
  );
}
