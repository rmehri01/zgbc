import { useEffect, useState } from "react";
import init from "../../zig-out/bin/zgbc.wasm?init";

export const CLOCK_RATE = 4194304;

export const SCREEN_WIDTH = 160;
export const SCREEN_HEIGHT = 144;

const AUDIO_BUFFER_SIZE = 2048;

type GameboyPtr = number;

/** The raw interface for interacting with zgbc.wasm. */
interface ZgbcRaw {
  memory: WebAssembly.Memory;

  allocUint8Array: (len: number) => GameboyPtr;
  init: () => GameboyPtr;
  deinit: (gb: GameboyPtr) => void;
  loadROM: (gb: GameboyPtr, ptr: GameboyPtr, len: number) => void;
  stepCycles: (gb: GameboyPtr, cycles: number) => number;
  pixels: (gb: GameboyPtr) => GameboyPtr;
  buttonPress: (gb: GameboyPtr, button: Button) => void;
  buttonRelease: (gb: GameboyPtr, button: Button) => void;
  readLeftAudioChannel: (
    gb: GameboyPtr,
    ptr: GameboyPtr,
    len: number,
  ) => number;
  readRightAudioChannel: (
    gb: GameboyPtr,
    ptr: GameboyPtr,
    len: number,
  ) => number;
}

export enum Button {
  Right,
  Left,
  Up,
  Down,
  A,
  B,
  Select,
  Start,
}

/** The main interface for interacting with zgbc.wasm. */
export interface Zgbc {
  loadROM: (rom: Uint8Array) => void;
  stepCycles: (cycles: number) => number;
  pixels: () => Uint8ClampedArray;
  buttonPress: (button: Button) => void;
  buttonRelease: (button: Button) => void;
  readLeftAudioChannel: () => Float32Array;
  readRightAudioChannel: () => Float32Array;
}

// TODO: return a new zgbc instance when loading rom?
function createZgbc(raw: ZgbcRaw): Zgbc {
  let gb = raw.init();
  const leftAudioChannel = raw.allocUint8Array(AUDIO_BUFFER_SIZE * 4);
  const rightAudioChannel = raw.allocUint8Array(AUDIO_BUFFER_SIZE * 4);

  return {
    pixels: () => {
      const addr = raw.pixels(gb);
      return new Uint8ClampedArray(
        raw.memory.buffer,
        addr,
        SCREEN_WIDTH * SCREEN_HEIGHT * 4,
      );
    },
    stepCycles: (cycles) => raw.stepCycles(gb, cycles),
    loadROM: (rom) => {
      raw.deinit(gb);
      gb = raw.init();

      const bufPtr = raw.allocUint8Array(rom.length);
      const buf = new Uint8Array(raw.memory.buffer, bufPtr, rom.length);

      buf.set(rom);
      raw.loadROM(gb, bufPtr, rom.length);
    },
    buttonPress: (button: Button) => raw.buttonPress(gb, button),
    buttonRelease: (button: Button) => raw.buttonRelease(gb, button),
    readLeftAudioChannel: () => {
      const num_read = raw.readLeftAudioChannel(
        gb,
        leftAudioChannel,
        AUDIO_BUFFER_SIZE,
      );
      return new Float32Array(raw.memory.buffer, leftAudioChannel, num_read);
    },
    readRightAudioChannel: () => {
      const num_read = raw.readRightAudioChannel(
        gb,
        rightAudioChannel,
        AUDIO_BUFFER_SIZE,
      );
      return new Float32Array(raw.memory.buffer, rightAudioChannel, num_read);
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
