import { useRef } from "react";
import { Zgbc } from "./wasm";

export default function LoadROMButton({ zgbc }: { zgbc: Zgbc | null }) {
  const romRef = useRef<HTMLInputElement>(null);

  const handleLoadROM = async (file: File) => {
    const bytes = await file.arrayBuffer();
    zgbc?.loadROM(new Uint8Array(bytes));
  };

  return (
    <>
      <button onClick={() => romRef.current?.click()} tabIndex={-1}>
        Load ROM
      </button>
      <input
        onChange={(e) => {
          void handleLoadROM(e.target.files![0]);
          e.target.blur();
        }}
        multiple={false}
        ref={romRef}
        type="file"
        hidden
      />
    </>
  );
}
