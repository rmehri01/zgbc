import { useRef } from "react";

export default function LoadROMButton() {
  const romRef = useRef<HTMLInputElement>(null);

  const handleLoadROM = (file: File) => {
    console.log(file);
  };

  return (
    <>
      <button onClick={() => romRef.current?.click()}>Load ROM</button>
      <input
        onChange={(e) => handleLoadROM(e.target.files![0])}
        multiple={false}
        ref={romRef}
        type="file"
        hidden
      />
    </>
  );
}
