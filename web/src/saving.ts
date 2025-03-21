import { useEffect } from "react";
import { Zgbc } from "./wasm";

export function setSaveRAM(title: string, ram: Uint8Array) {
  window.localStorage.setItem(title, bytesToBase64(ram));
}

export function getSaveRAM(title: string): Uint8Array | null {
  const ram = window.localStorage.getItem(title);
  if (ram === null) return null;

  return base64ToBytes(ram);
}

export function useSetupSaving(zgbc: Zgbc | null) {
  useEffect(() => {
    if (!zgbc?.supportsSaving()) return;

    const title = zgbc.romTitle();
    const save = () => setSaveRAM(title, zgbc.getBatteryBackedRAM());

    const interval = setInterval(save, 2000);
    window.onbeforeunload = save;

    return () => {
      clearInterval(interval);
    };
  }, [zgbc]);
}

function base64ToBytes(base64: string) {
  const binString = atob(base64);
  return Uint8Array.from(binString, (m) => m.codePointAt(0)!);
}

function bytesToBase64(bytes: Uint8Array) {
  const binString = String.fromCodePoint(...bytes);
  return btoa(binString);
}
