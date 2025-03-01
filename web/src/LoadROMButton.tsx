import { useRef } from "react";
import { Zgbc } from "./wasm";

export default function LoadROMButton({ zgbc }: { zgbc: Zgbc | null }) {
  const romRef = useRef<HTMLInputElement>(null);

  const handleLoadROM = async (file: File) => {
    const bytes = await file.bytes();
    zgbc?.loadROM(bytes);
  };

  return (
    <>
      <button onClick={() => romRef.current?.click()}>Load ROM</button>
      <input
        onChange={(e) => {
          void handleLoadROM(e.target.files![0]);
        }}
        multiple={false}
        ref={romRef}
        type="file"
        hidden
      />
    </>
  );
}
