import { useEffect, useState } from "react";
import init from "../../zig-out/bin/zgbc.wasm?init";

export const SCREEN_WIDTH = 160;
export const SCREEN_HEIGHT = 140;

type GameboyPtr = number;

/** The raw interface for interacting with zgbc.wasm. */
interface ZgbcRaw {
  memory: WebAssembly.Memory;

  init: () => GameboyPtr;
  pixels: (gb: GameboyPtr) => GameboyPtr;
}

/** The main interface for interacting with zgbc.wasm. */
export interface Zgbc {
  pixels: () => Uint8ClampedArray;
}

function createZgbc(exports: WebAssembly.Exports): Zgbc {
  const raw = exports as unknown as ZgbcRaw;
  const gb = raw.init();

  return {
    pixels: () => {
      const addr = raw.pixels(gb);
      return new Uint8ClampedArray(
        raw.memory.buffer,
        addr,
        SCREEN_WIDTH * SCREEN_HEIGHT * 4,
      );
    },
  };
}

export function useZgbc(): Zgbc | null {
  const [zgbc, setZgbc] = useState<Zgbc | null>(null);

  useEffect(() => {
    async function run() {
      const instance = await init();
      setZgbc(createZgbc(instance.exports));
    }

    void run();
  }, []);

  return zgbc;
}
