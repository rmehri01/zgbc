import { useEffect, useState } from "react";
import init from "../../zig-out/bin/zgbc.wasm?init";

export const SCREEN_WIDTH = 160;
export const SCREEN_HEIGHT = 140;

type GameboyPtr = number;

/** The raw interface for interacting with zgbc.wasm. */
interface ZgbcRaw {
  memory: WebAssembly.Memory;

  allocUint8Array: (len: number) => GameboyPtr;
  init: () => GameboyPtr;
  pixels: (gb: GameboyPtr) => GameboyPtr;
  execute: (gb: GameboyPtr) => void;
  loadROM: (gb: GameboyPtr, ptr: GameboyPtr, len: number) => void;
}

/** The main interface for interacting with zgbc.wasm. */
export interface Zgbc {
  pixels: () => Uint8ClampedArray;
  execute: () => void;
  loadROM: (rom: Uint8Array) => void;
}

function createZgbc(raw: ZgbcRaw): Zgbc {
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
    execute: () => raw.execute(gb),
    loadROM: (rom) => {
      const bufPtr = raw.allocUint8Array(rom.length);
      const buf = new Uint8Array(raw.memory.buffer, bufPtr, rom.length);

      buf.set(rom);
      raw.loadROM(gb, bufPtr, rom.length);
    },
  };
}

export function useZgbc(): Zgbc | null {
  const [zgbc, setZgbc] = useState<Zgbc | null>(null);

  useEffect(() => {
    async function run() {
      let raw: ZgbcRaw;

      const decodeString = (ptr: GameboyPtr, len: number): string => {
        const bytes = new Uint8Array(raw.memory.buffer, ptr, len);
        return new TextDecoder("utf8").decode(bytes);
      };

      const instance = await init({
        env: {
          consoleLog: (ptr: GameboyPtr, len: number) => {
            const msg = decodeString(ptr, len);
            console.log(msg);
          },
          consoleLogJson: (ptr: GameboyPtr, len: number) => {
            const msg = decodeString(ptr, len);
            console.dir(JSON.parse(msg));
          },
          consoleLogJsonDiff: (
            oldPtr: GameboyPtr,
            oldLen: number,
            newPtr: GameboyPtr,
            newLen: number,
          ) => {
            const oldStr = decodeString(oldPtr, oldLen);
            const newStr = decodeString(newPtr, newLen);
            const diffObj = diff(
              JSON.parse(oldStr) as unknown,
              JSON.parse(newStr) as unknown,
            );
            console.dir(diffObj);
          },
        },
      });
      raw = instance.exports as unknown as ZgbcRaw;

      setZgbc(createZgbc(raw));
    }

    void run();
  }, []);

  return zgbc;
}

/** Simple diff that assumes both parameters have the same structure and only updated fields. */
function diff<T>(oldObj: T, newObj: T): T | Record<string, unknown> {
  // for primitives, just check if they are equal
  if (!isObject(oldObj) || !isObject(newObj)) {
    return oldObj === newObj ? {} : newObj;
  }

  // for objects, recursively check each key
  return Object.keys(oldObj).reduce<Record<string, unknown>>((acc, key) => {
    const difference = diff(oldObj[key], newObj[key]);

    if (!isObject(difference) || Object.keys(difference).length !== 0) {
      acc[key] = difference;
    }

    return acc;
  }, {});
}

function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object";
}
