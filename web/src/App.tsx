import "./App.css";
import LoadROMButton from "./LoadROMButton";
import Display from "./Display";
import { useZgbc } from "./wasm";
import { useSetupInputs } from "./inputs";
import { useSetupAudio } from "./audio";
import { useRef } from "react";

function App() {
  const gamepad = useRef<Gamepad | null>(null);
  const zgbc = useZgbc(gamepad);

  const { checkGamepadInputs } = useSetupInputs(zgbc, gamepad);
  const { updateAudio } = useSetupAudio();

  return (
    <>
      <nav>
        <LoadROMButton zgbc={zgbc} />
      </nav>
      <div className="display-container">
        <Display
          zgbc={zgbc}
          checkGamepadInputs={checkGamepadInputs}
          updateAudio={updateAudio}
        />
        <a
          className="tm-text"
          href="https://github.com/rmehri01/zgbc"
          target="_blank"
          rel="noreferrer"
        >
          zgbc
        </a>
      </div>
    </>
  );
}

export default App;
