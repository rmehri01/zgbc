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
      <Display
        zgbc={zgbc}
        checkGamepadInputs={checkGamepadInputs}
        updateAudio={updateAudio}
      />
    </>
  );
}

export default App;
