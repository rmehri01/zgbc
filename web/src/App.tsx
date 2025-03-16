import "./App.css";
import LoadROMButton from "./LoadROMButton";
import Display from "./Display";
import { useZgbc } from "./wasm";
import { useSetupInputs } from "./inputs";
import { useSetupAudio } from "./audio";

function App() {
  const zgbc = useZgbc();

  const { checkGamepadInputs } = useSetupInputs(zgbc);
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
