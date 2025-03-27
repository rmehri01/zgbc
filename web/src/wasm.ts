import { useEffect, useState } from "react";
import init from "../../zig-out/bin/zgbc.wasm?init";
import { getSaveRAM, setSaveRAM } from "./saving";

export const CLOCK_RATE = 4194304;

export const SCREEN_WIDTH = 160;
export const SCREEN_HEIGHT = 144;
export const CYCLES_PER_FRAME = 70224;

const AUDIO_BUFFER_SIZE = 2048;
const AUDIO_BUFFER_BYTES = AUDIO_BUFFER_SIZE * 4;

type GameboyPtr = number;

/** The raw interface for interacting with zgbc.wasm. */
interface ZgbcRaw {
  memory: WebAssembly.Memory;

  allocUint8Array: (len: number) => GameboyPtr;
  freeUint8Array: (ptr: GameboyPtr, len: number) => void;

  init: () => GameboyPtr;
  deinit: (gb: GameboyPtr) => void;
  reset: (gb: GameboyPtr) => void;
  loadROM: (gb: GameboyPtr, ptr: GameboyPtr, len: number) => void;
  romTitle: (gb: GameboyPtr) => GameboyPtr;
  supportsSaving: (gb: GameboyPtr) => boolean;
  getBatteryBackedRAM: (gb: GameboyPtr) => GameboyPtr;
  setBatteryBackedRAM: (gb: GameboyPtr, ptr: GameboyPtr, len: number) => void;

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
  romTitle: () => string;
  supportsSaving: () => boolean;
  getBatteryBackedRAM: () => Uint8Array;

  stepCycles: (cycles: number) => number;
  pixels: () => Uint8ClampedArray;
  buttonPress: (button: Button) => void;
  buttonRelease: (button: Button) => void;
  readLeftAudioChannel: () => Float32Array;
  readRightAudioChannel: () => Float32Array;
}

function createZgbc(raw: ZgbcRaw, onLoad: () => void): Zgbc {
  const gb = raw.init();
  const leftAudioChannelPtr = raw.allocUint8Array(AUDIO_BUFFER_BYTES);
  const rightAudioChannelPtr = raw.allocUint8Array(AUDIO_BUFFER_BYTES);

  const romTitle = () => {
    const structPtr = raw.romTitle(gb);
    const [titlePtr, titleLen] = new Uint32Array(
      raw.memory.buffer,
      structPtr,
      2,
    );
    return decodeString(raw, titlePtr, titleLen);
  };
  const supportsSaving = () => raw.supportsSaving(gb);
  const getBatteryBackedRAM = () => {
    const structPtr = raw.getBatteryBackedRAM(gb);
    const [ramPtr, ramLen] = new Uint32Array(raw.memory.buffer, structPtr, 2);
    return new Uint8Array(raw.memory.buffer, ramPtr, ramLen);
  };

  let romBuf: {
    ptr: GameboyPtr;
    len: number;
  };

  return {
    loadROM: (rom) => {
      if (supportsSaving()) {
        const title = romTitle();
        const ram = getBatteryBackedRAM();
        setSaveRAM(title, ram);
      }

      raw.reset(gb);
      if (romBuf) {
        raw.freeUint8Array(romBuf.ptr, romBuf.len);
      }

      const romBufPtr = raw.allocUint8Array(rom.length);
      romBuf = {
        ptr: romBufPtr,
        len: rom.length,
      };

      const romArray = new Uint8Array(
        raw.memory.buffer,
        romBuf.ptr,
        romBuf.len,
      );
      romArray.set(rom);
      raw.loadROM(gb, romBuf.ptr, romBuf.len);

      const title = romTitle();
      const ram = getSaveRAM(title);
      if (ram) {
        const ramArrayPtr = raw.allocUint8Array(ram.length);
        const ramArray = new Uint8Array(
          raw.memory.buffer,
          ramArrayPtr,
          ram.length,
        );
        ramArray.set(ram);
        raw.setBatteryBackedRAM(gb, ramArrayPtr, ram.length);
        raw.freeUint8Array(ramArrayPtr, ram.length);
      }
      onLoad();
    },
    romTitle,
    supportsSaving,
    getBatteryBackedRAM,

    stepCycles: (cycles) => raw.stepCycles(gb, cycles),
    pixels: () => {
      const addr = raw.pixels(gb);
      return new Uint8ClampedArray(
        raw.memory.buffer,
        addr,
        SCREEN_WIDTH * SCREEN_HEIGHT * 4,
      );
    },
    buttonPress: (button: Button) => raw.buttonPress(gb, button),
    buttonRelease: (button: Button) => raw.buttonRelease(gb, button),
    readLeftAudioChannel: () => {
      const num_read = raw.readLeftAudioChannel(
        gb,
        leftAudioChannelPtr,
        AUDIO_BUFFER_SIZE,
      );
      return new Float32Array(raw.memory.buffer, leftAudioChannelPtr, num_read);
    },
    readRightAudioChannel: () => {
      const num_read = raw.readRightAudioChannel(
        gb,
        rightAudioChannelPtr,
        AUDIO_BUFFER_SIZE,
      );
      return new Float32Array(
        raw.memory.buffer,
        rightAudioChannelPtr,
        num_read,
      );
    },
  };
}

export function useZgbc(gamepad: React.RefObject<Gamepad | null>): Zgbc | null {
  const [zgbc, setZgbc] = useState<Zgbc | null>(null);

  useEffect(() => {
    async function run() {
      let raw: ZgbcRaw;

      let vibrationInterval: number | undefined = undefined;
      const rumbleChanged = (on: boolean) => {
        if (on) {
          if (window.navigator.vibrate || gamepad.current !== null) {
            const gamepadVibrate = () => {
              if (window.navigator.vibrate) {
                window.navigator.vibrate(1000);
              }

              if (gamepad.current !== null) {
                void gamepad.current.vibrationActuator?.playEffect(
                  "dual-rumble",
                  {
                    startDelay: 0,
                    duration: 1000,
                    weakMagnitude: 0.8,
                    strongMagnitude: 0.8,
                  },
                );
              }
            };
            vibrationInterval = setInterval(gamepadVibrate, 1000);
            gamepadVibrate();
          }
        } else {
          clearInterval(vibrationInterval);
          if (window.navigator.vibrate) {
            window.navigator.vibrate(0);
          }
          if (gamepad.current !== null) {
            void gamepad.current.vibrationActuator?.reset();
          }
        }
      };

      const instance = await init({
        env: {
          rumbleChanged,
          consoleLog: (ptr: GameboyPtr, len: number) => {
            const msg = decodeString(raw, ptr, len);
            console.log(msg);
          },
          consoleLogJson: (ptr: GameboyPtr, len: number) => {
            const msg = decodeString(raw, ptr, len);
            console.dir(JSON.parse(msg));
          },
          consoleLogJsonDiff: (
            oldPtr: GameboyPtr,
            oldLen: number,
            newPtr: GameboyPtr,
            newLen: number,
          ) => {
            const oldStr = decodeString(raw, oldPtr, oldLen);
            const newStr = decodeString(raw, newPtr, newLen);
            const diffObj = diff(
              JSON.parse(oldStr) as unknown,
              JSON.parse(newStr) as unknown,
            );
            console.dir(diffObj);
          },
        },
      });
      raw = instance.exports as unknown as ZgbcRaw;

      const initialZgbc = createZgbc(raw, () => setZgbc(initialZgbc));
      setZgbc(initialZgbc);
    }

    void run();
  }, [gamepad]);

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

function decodeString(raw: ZgbcRaw, ptr: GameboyPtr, len: number): string {
  const bytes = new Uint8Array(raw.memory.buffer, ptr, len);
  return new TextDecoder("utf8").decode(bytes);
}
